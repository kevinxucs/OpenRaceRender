import AppKit
import AVFoundation

/// Independent serializers for the documented-by-observation RR3 interchange records.
/// These do not require RaceRender or its library. Unsupported edits fail before a file is written.
public enum LegacyWriter {
  public enum Format: String, CaseIterable, Sendable { case rrp, rrt, rro }
  static let version: UInt32 = 20191031
  static let minimumVersion: UInt32 = 20161216

  public static func write(_ project: RaceProject, to url: URL) throws {
    guard let format = Format(rawValue: url.pathExtension.lowercased()) else {
      throw RaceError.invalid("Choose .rrp, .rrt or .rro for RaceRender export.")
    }
    let bytes = try data(project, format: format)
    try bytes.write(to: url, options: .atomic)
  }

  /// RRT seeds are adjusted when an encrypted source ID would collide with its raw delimiter.
  public static func data(_ sourceProject: RaceProject, format: Format, seed: UInt32 = .random(in: .min ... .max)) throws -> Data {
    guard !sourceProject.inputs.contains(where:{$0.isTimeFiller == true}) else {
      throw RaceError.invalid("Time filler records have no verified RaceRender encoding. Save this sequence in .orrp format.")
    }
    guard Set(sourceProject.objects.map(\.id)).count == sourceProject.objects.count else {
      throw RaceError.invalid("Display identities must be unique before RaceRender export.")
    }
    guard Set(sourceProject.inputs.map(\.legacyIndex)).count == sourceProject.inputs.count,
      sourceProject.inputs.allSatisfy({ (0...1_000_000).contains($0.legacyIndex) }) else {
      throw RaceError.invalid("Input identifiers must be unique nonnegative integers in the supported range.")
    }
    var project = format == .rrp ? try canonicalJoins(sourceProject) : sourceProject
    // Convert stable identities to this file's object table, never reuse template indexes.
    for object in project.objects {
      if object.parentID == object.id || (object.parentID == nil && object.parentIndex >= 0 && project.parentID(of: object) == nil) {
        throw RaceError.invalid("The parent group is missing or invalid.")
      }
      if let parent = object.parentID, !project.objects.contains(where: { $0.id == parent && $0.kind == .group }) {
        throw RaceError.invalid("The parent group is missing.")
      }
      guard !project.ancestors(of: object.id).contains(where: { parent in project.ancestors(of: parent).contains(object.id) }) else {
        throw RaceError.invalid("A display group contains a parent cycle.")
      }
    }
    project.stabilizeHierarchy()
    project = bakingGroupState(project)
    let parentsByID = Dictionary(uniqueKeysWithValues: project.objects.enumerated().map { ($0.element.id, $0.offset) })
    for i in project.objects.indices {
      project.objects[i].legacyIndex = i
      project.objects[i].parentIndex = project.objects[i].parentID.flatMap { parentsByID[$0] } ?? -1
    }
    if format == .rrp, let original = project.legacyData {
      guard original.u32(12) == 2152, original.u32(20) == 2216, original.u32(24) == 11312, original.u32(28) == 56,
        original.u32(36) == 344, original.u32(44) == 208,
        original.u32(4) <= version else {
        throw RaceError.invalid("This RRP record variant cannot be rebuilt safely. Save as .orrp, or use the conservative copy API for unchanged opaque records.")
      }
      let decoded = try LegacyReader.project(original,base:URL(fileURLWithPath:project.sourcePath ?? "/").deletingLastPathComponent())
      if decoded.warnings.contains(where: { $0.contains("Timeline segment") && $0.contains("unsupported") }) {
        throw RaceError.invalid("This project contains unsupported timeline flags. Save in .orrp format to retain the original data.")
      }
    }
    guard project.inputs.count <= 255, project.objects.count <= 10000 else {
      throw RaceError.invalid("RaceRender export allows at most 255 inputs and 10,000 displays.")
    }
    guard Set(project.inputs.map(\.legacyIndex)).count == project.inputs.count else {
      throw RaceError.invalid("Input identifiers must be unique before RaceRender export.")
    }
    let sources = Dictionary(uniqueKeysWithValues: project.inputs.enumerated().map { ($0.element.legacyIndex, $0.offset) })
    let objectIDs = Dictionary(project.objects.enumerated().map { ($0.element.legacyIndex ?? $0.offset, $0.offset) }, uniquingKeysWith: { first, _ in first })
    let records = try project.objects.map { object in
      var object = object
      if format == .rro {
        guard object.parentIndex < 0 else { throw RaceError.invalid("Ungroup this display before exporting it as an individual style.") }
        object.inputIndex = -1
      }
      return try record(object, sources: sources, parents: objectIDs)
    }
    switch format {
    case .rrp:
      if let duration = project.explicitDuration, !duration.isFinite || duration <= 0 || duration >= 1_000_000 {
        throw RaceError.invalid("RaceRender project length must be positive and below 1,000,000 seconds.")
      }
      if let end = project.rangeEnd, end <= 0 { throw RaceError.invalid("RaceRender cannot store an output end marker at zero. Clear the end marker or choose a positive time.") }
      var b = Data(repeating: 0, count: 2152)
      b.replaceSubrange(0..<4, with: Data("RRP3".utf8))
      for (offset, value) in [(4,version),(8,minimumVersion),(12,2152),(16,UInt32(project.inputs.count)),(20,2216),(24,11312),(28,56),(32,UInt32(records.count)),(36,344),(40,24),(44,208)] { b.putU32(value,offset) }
      try string(project.notes ?? "", into: &b, at: 48, size: 2048, field: "Project notes")
      b.putFloat(try finite(project.explicitDuration ?? 0, "Project length"),2096)
      b[2120] = project.speedUnit == "km/h" ? 2 : project.speedUnit == "knots" ? 3 : project.speedUnit == "m/s" ? 4 : 1
      b[2121] = try input(project.lengthInputIndex ?? -1, sources: sources)
      b[2126] = try workspace(project); b[2127] = 1
      b.putFloat(try finite(project.rangeStart ?? 0, "Output start"),2128)
      b.putFloat(try finite(project.rangeEnd ?? 0, "Output end"),2132)
      b.putFloat(56,2148)
      for source in project.inputs { b.append(try sourceRecord(source, project: project, sources: sources)) }
      for r in records { b.append(r.common); b.append(word(r.payload.count)); b.append(r.payload); b.append(r.image) }
      let segments = try project.objects.map { try timeline($0, sources: sources, parents: objectIDs) }
      for s in segments { b.append(word(s.count)) }
      for s in segments { for record in s { b.append(record) } }
      return b
    case .rrt:
      guard project.inputs.count <= 8 else { throw RaceError.invalid("RaceRender templates support up to eight input roles.") }
      try noTimeline(project)
      var b = Data("rrt2".utf8) + word(version) + word(minimumVersion)
      b.append(try workspace(project)); b.append(preview(project, width: 180, height: 120))
      // The input table terminates with a raw 0xFF. Avoid a seed whose
      // encrypted input identifier would be indistinguishable from that marker.
      var templateSeed = seed, key = LegacyCodec.templateKey(seed)
      for _ in 0..<4096 {
        let pad = LegacyCodec.transform(Data(repeating:0,count:136),key:key)[0]
        if !(0..<project.inputs.count).contains(where: { UInt8($0) ^ pad == 255 }) { break }
        templateSeed &+= 1; key = LegacyCodec.templateKey(templateSeed)
      }
      let pad = LegacyCodec.transform(Data(repeating:0,count:136),key:key)[0]
      guard !(0..<project.inputs.count).contains(where: { UInt8($0) ^ pad == 255 }) else { throw RaceError.invalid("Could not encode template input identifiers.") }
      b.append(word(templateSeed)); b.append(word(136)); b.append(word(216))
      for (index, source) in project.inputs.enumerated() {
        var r = Data(repeating: 0, count: 136); r[0] = UInt8(index)
        r[1] = source.kind == "data" ? 4 : source.kind == "audio" ? 2 : 1
        try string(source.name, into: &r, at: 8, size: 128, field: "Input role name")
        b.append(LegacyCodec.transform(r,key:key))
      }
      b.append(255)
      for (index, r) in records.enumerated().reversed() {
        let meta = Data(r.common[128..<344])
        b.append(word(index)); b.append(LegacyCodec.transform(Data(r.common[0..<128]),key:key))
        b.append(LegacyCodec.transform(meta,key:key)); b.append(word(r.payload.count))
        b.append(integrity(meta,seed:version &+ UInt32(r.payload.count)))
        b.append(LegacyCodec.transform(r.payload,key:key))
        if !r.payload.isEmpty { b.append(integrity(r.payload,seed:version)) }
        b.append(r.image)
      }
      b.append(word(UInt32.max)); return b
    case .rro:
      guard records.count == 1 else { throw RaceError.invalid("A RaceRender style contains exactly one display. Select one display to export.") }
      try noTimeline(project)
      let r = records[0], meta = Data(r.common[260..<344]), key = LegacyCodec.templateKey(seed,salt:"RaceRender LLC")
      var b = Data("rro2".utf8) + word(seed) + word(version) + word(minimumVersion)
      b.append(preview(project,width:120,height:120)); b.append(word(84))
      b.append(LegacyCodec.transform(meta,key:key)); b.append(word(r.payload.count))
      b.append(integrity(meta,seed:version &+ UInt32(r.payload.count)))
      b.append(LegacyCodec.transform(r.payload,key:key))
      if !r.payload.isEmpty { b.append(integrity(r.payload,seed:version)) }
      b.append(r.image); return b
    }
  }

  /// RaceRender's own group inspector copies activation changes to member records;
  /// bake native group gates the same way so RR does not need inherited alpha/state.
  static func bakingGroupState(_ source: RaceProject) -> RaceProject {
    guard source.objects.contains(where: { $0.kind == .group }) else { return source }
    var result = source
    let times = source.timelineBoundaries.filter { $0 >= 0 && $0 < 1_000_000 }
    for time in times {
      let effective = source.resolvedObjects(at: time)
      for i in result.objects.indices where result.objects[i].kind != .group && source.parentID(of: source.objects[i]) != nil {
        let state = effective[i]
        var value = result.objects[i].resolved(at: time)
        value.visible = state.visible && time >= state.start && time < state.end; value.opacity = state.opacity
        if time == 0 { result.objects[i].visible = value.visible; result.objects[i].opacity = value.opacity }
        else {
          let old = result.objects[i].resolved(at: time)
          result.objects[i].editSegment(at:time,from:old,to:value)
        }
      }
    }
    for i in result.objects.indices where result.objects[i].kind == .group {
      result.objects[i].visible = true; result.objects[i].opacity = 1; result.objects[i].start = 0; result.objects[i].end = 1_000_000
      for j in (result.objects[i].segments ?? []).indices {
        result.objects[i].segments?[j].visible = nil; result.objects[i].segments?[j].opacity = nil
      }
    }
    return result
  }

  struct Record { var common: Data; var payload: Data; var image: Data }

  static func record(_ object: DisplayObject, sources: [Int:Int], parents: [Int:Int]) throws -> Record {
    let o = object
    func unsupported(_ detail: String) -> RaceError { .invalid("‘\(o.name)’: \(detail) Save this project in .orrp format.") }
    guard o.hud == nil else { throw unsupported("GT/HUD instruments have no equivalent RaceRender display.") }
    var common = o.legacyCommon?.count == 344 ? o.legacyCommon! : Data(repeating:0,count:344)
    var payload = o.legacyPayload ?? Data()
    let type: Int
    if let legacy = o.legacyType { type = legacy }
    else {
      switch o.kind {
      case .video: type = 10
      case .audio: type = 11
      case .text: type = 13
      case .shape: type = 12
      case .image: type = 14
      case .speed, .rpm, .gauge: type = 30
      case .graph: type = 35
      case .group: type = 0
      default: throw unsupported("This native widget does not yet have a compatible legacy encoding.")
      }
    }
    if type == 13 {
      if payload.count < 808 { payload = Data(repeating:0,count:808) }
      let t = o.typography ?? TextSettings()
      if t.outline && t.outlineWidth != 2 { throw unsupported("RaceRender uses a fixed text outline width.") }
      payload.putU32(try rgb(o.color),0)
      try string(o.text,into:&payload,at:4,size:512,field:"Text")
      try string(t.font,into:&payload,at:516,size:128,field:"Font")
      payload.putFloat(try finite(t.size * 480 / max(1,t.referenceHeight),"Font size"),644)
      payload[648] = (t.bold ? 1 : 0) | (t.italic ? 2 : 0) | (t.underline ? 4 : 0) | (t.strikethrough ? 8 : 0)
      payload[649] = t.alignment == .center ? 1 : t.alignment == .right ? 2 : 0
      payload[650] = t.fitToBox ? 1 : 0; payload[651] = t.outline ? 1 : 0
      payload.putU32(try rgb(t.outlineColor),652)
    } else if type == 12 {
      let s = o.shape ?? ShapeSettings()
      guard [.rectangle,.roundedRectangle,.rounderRectangle,.ellipse].contains(s.kind) else {
        throw unsupported("RaceRender's shape record supports rectangles and ellipses; \(s.kind.rawValue) is a native shape.")
      }
      guard !s.gradient || s.gradientAngle == 90 else { throw unsupported("Rotated shape gradients cannot be stored in this RaceRender record.") }
      if payload.count < 20 { payload = Data(repeating:0,count:20) }
      payload.putU32(try rgb(s.strokeColor,enabled:s.stroke),0); payload.putU32(try rgb(o.color,enabled:s.fill),4)
      payload[8] = s.kind == .ellipse ? 3 : s.kind == .roundedRectangle ? 1 : s.kind == .rounderRectangle ? 2 : 0
      payload[9] = try byte(s.strokeWidth * 480 / max(1,s.referenceHeight),"Shape border width")
      payload.putU32(try rgb(s.gradientColor,enabled:s.gradient),12)
    } else if type == 30 {
      try gauge(o,common:&common,payload:&payload)
    } else if type == 14 {
      let s = o.imageControl ?? ImageControlSettings()
      guard s.output != .visibility else { throw unsupported("Use opacity endpoints 0 and 100 to export visibility to RaceRender.") }
      if payload.count < 168 { payload.append(Data(repeating:0,count:168-payload.count)) }
      try string(o.channel,into:&payload,at:0,size:128,field:"Image channel")
      payload.putDouble(try finite(s.inputMinimum,"Image input minimum"),128)
      payload.putDouble(try finite(s.inputMaximum,"Image input maximum"),136)
      payload.putDouble(try finite(s.output == .opacity ? 100-s.outputMinimum : s.outputMinimum,"Image output minimum"),144)
      payload.putDouble(try finite(s.output == .opacity ? 100-s.outputMaximum : s.outputMaximum,"Image output maximum"),152)
      payload[160] = s.mode == .simple ? 0 : s.mode == .proportional ? 1 : s.mode == .greaterOrEqual ? 2 : 3
      payload[161] = s.output == .rotation ? 2 : s.output == .opacity ? 3 : s.output == .brightness ? 4 : 5
      guard s.pulseInterval.isFinite, s.pulseInterval >= 0, s.pulseInterval <= 25.5,
        abs(s.pulseInterval*10-(s.pulseInterval*10).rounded()) < 1e-7 else { throw unsupported("RaceRender image pulse intervals use tenths of a second from 0 to 25.5.") }
      payload[162] = UInt8((s.pulseInterval*10).rounded())
    } else if type == 35 {
      let g = o.graph ?? GraphSettings()
      guard g.lap == nil, !g.flipSides else { throw unsupported("Graph lap selection and alternate number placement have no verified legacy encoding.") }
      guard (!g.axes && !g.numbers) || (g.interval.isFinite && g.interval > 0) else {
        throw unsupported("Choose a positive graph axis interval before legacy export; RaceRender stores one fixed interval for both axes.")
      }
      if payload.count < 624 { payload.append(Data(repeating:0,count:624-payload.count)) }
      try string(o.channel,into:&payload,at:0,size:128,field:"Y channel")
      try string(g.axis == .time ? "" : g.axis == .distance ? "(Distance)" : g.resolvedHorizontalChannel,into:&payload,at:472,size:128,field:"X channel")
      payload.putDouble(g.automaticMinimum ? 100_000_000 : try finite(o.minimum,"Y minimum"),256)
      payload.putDouble(g.automaticMaximum ? -100_000_000 : try finite(o.maximum,"Y maximum"),264)
      payload.putDouble(g.xMinimum ?? 100_000_000,600); payload.putDouble(g.xMaximum ?? -100_000_000,608)
      payload.putFloat(g.safeSpan,272)
      payload[429] = (payload[429] & ~UInt8(79)) | g.mode.legacyBits | (g.reverse ? 1 : 0) | (g.vertical ? 64 : 0)
      if g.timeStart != nil || g.timeEnd != nil {
        let start = try finite(g.timeStart ?? 0,"Graph start"), end = try finite(g.timeEnd ?? 60,"Graph end")
        guard start >= 0, end > start else { throw unsupported("Graph end must follow its start.") }
        payload.putFloat(start,448); payload.putFloat(end,452)
      } else { payload.putFloat(0,448); payload.putFloat(-1,452) }
      payload[616] = (g.connect ? 1 : 0) | (g.sortX ? 2 : 0)
      payload.putU32(try rgb(g.markerColor),276); payload[428] = try byte(g.markerSize,"Graph marker size")
      payload.putU32(try rgb(g.backgroundColor,enabled:g.background),280)
      payload.putU32(try rgb(g.trimColor,enabled:g.trim),284); payload[430] = try byte(g.trimWidth,"Graph border width")
      payload.putU32(try rgb(g.lineColor),288); payload[431] = try byte(g.lineWidth,"Graph line width")
      payload.putU32(try rgb(g.axisColor,enabled:g.axes),432); payload[440] = try byte(g.axisWidth,"Graph axis width")
      payload.putFloat(try finite(g.interval,"Axis interval"),436)
      payload.putU32(try rgb(g.lineGradient ?? "#000000",enabled:g.lineGradient != nil),444)
      payload.putU32(try rgb(g.fillColor,enabled:g.fill),456)
      payload.putU32(try rgb(g.fillGradient ?? "#000000",enabled:g.fillGradient != nil),460)
      payload.putU32(try rgb(g.numberColor,enabled:g.numbers),464); payload.putFloat(try finite(g.numberSize,"Graph number size"),468)
      try string(g.label,into:&payload,at:128,size:128,field:"Graph label")
      payload.putU32(try rgb(g.labelColor,enabled:!g.label.isEmpty),292); payload.putFloat(try finite(g.labelSize,"Graph label size"),424)
      if o.legacyPayload == nil { payload[441] = 50; try string("Helvetica",into:&payload,at:296,size:128,field:"Graph font") }
      let designWidth = try finite(g.referenceWidth,"Graph design width")
      guard designWidth > 0, designWidth <= 4096 else { throw unsupported("Graph design width must be between 1 and 4096.") }
      let height = max(1,Int((Double(common.u32(296) >> 16) > 0 ? Double(common.u32(296) >> 16) : designWidth/2)))
      common.putU32(UInt32(designWidth) | (UInt32(height) << 16),296)

    } else if ![0,10,11,14].contains(type) {
      guard o.legacyCommon != nil, o.legacyPayload != nil else { throw unsupported("Missing original settings for this display type.") }
      var decoded = LegacyReader.decodeCommon(common,at:0,legacyIndex:0); decoded.legacyPayload = payload
      LegacyReader.inferDetails(&decoded)
      // Specialized editors update the payload directly. Refuse native-only overrides.
      guard o.text == decoded.text, o.color == decoded.color,
        o.gauge == decoded.gauge, o.typography == decoded.typography, o.shape == decoded.shape,
        (o.hasStyleRange || (o.minimum == decoded.minimum && o.maximum == decoded.maximum)) else {
        throw unsupported("Some appearance settings are not represented in the original legacy payload.")
      }
      if [31,35,50].contains(type) { try string(o.channel,into:&payload,at:0,size:128,field:"Channel") }
      else if o.channel != decoded.channel { throw unsupported("This legacy display's data-channel override is not supported.") }
    }
    if let picture = o.picture {
      var extra = picture; extra.maintainAspect = true; extra.flipX = false; extra.flipY = false
      guard extra == PictureSettings() else { throw unsupported("Display-level crop, rotation and color adjustments must be applied to the video input for RaceRender export.") }
    }
    let audio = o.audio ?? AudioSettings()
    guard audio.routing == .stereo else { throw unsupported("Display-level channel routing is not supported by RaceRender; apply it to the input.") }
    try string(o.name,into:&common,at:0,size:128,field:"Display name")
    try string(o.style,into:&common,at:128,size:128,field:"Style name")
    if o.parentIndex >= 0 {
      guard let parent = parents[o.parentIndex] else { throw unsupported("The parent group is missing.") }
      common.putU32(UInt32(parent),256)
    } else { common.putU32(.max,256) }
    guard [o.x,o.y,o.width,o.height].allSatisfy({ $0.isFinite && abs($0) < 10000 }), o.width >= 0.001, o.height >= 0.001,
      o.start.isFinite, o.end.isFinite, o.start >= 0, o.end >= o.start else { throw unsupported("Invalid display size or time bounds.") }
    for (p,v) in [(260,o.x),(264,o.y),(268,o.width),(272,o.height),(276,o.start)] { common.putFloat(try finite(v,"Display geometry/time"),p) }
    common[280] = UInt8(clamping:type); common[281] = 2
    common[282] = ([0,12,13].contains(type) || (type == 14 && !o.imageUsesData)) ? 255 : try input(o.inputIndex,sources:sources)
    let originalVisible = (o.legacyActivation ?? 1) <= 1
    common[284] = o.visible == originalVisible ? UInt8(clamping:o.legacyActivation ?? 1) : o.visible ? 1 : 2
    common[285] = (o.picture?.maintainAspect ?? (type == 14 && o.legacyCommon == nil ? true : common[285] != 0)) ? 1 : 0
    if let picture = o.picture { common[286] = (picture.flipX ? 1 : 0) + (picture.flipY ? 2 : 0) }
    common[292] = try byte(audio.volume*100,"Display volume"); common[293] = try byte((audio.balance+1)*100,"Display balance")
    common[294] = try byte((1-o.opacity)*100,"Transparency")
    if o.legacyCommon == nil { common[288] = 7 }
    guard payload.count <= 4*1024*1024 else { throw unsupported("Oversized display settings.") }
    let background = try o.gauge?.backgroundImage ?? o.gauge?.backgroundPath.map { try Data(contentsOf:URL(fileURLWithPath:$0)) }
    if background != nil, o.artwork != nil || o.embeddedImage != nil {
      throw unsupported("Two background images cannot be stored in a single RaceRender display; remove one before export.")
    }
    let image: Data
    if let background { image = try bitmap(background) }
    else if let data = o.artwork { image = data.isEmpty ? word(0) : try bitmap(data) }
    else if let data = o.embeddedImage {
      image = LegacyArtwork.png(data) != nil ? data : try bitmap(data)
    } else if type == 14, !o.text.isEmpty { image = try bitmap(Data(contentsOf:URL(fileURLWithPath:o.text))) }
    else if type == 14 { throw unsupported("The image is missing; relink it before export.") }
    else { image = word(0) }
    return Record(common:common,payload:payload,image:type == 14 ? word(image.count)+image : image)
  }

  static func sourceRecord(_ source: MediaInput, project: RaceProject, sources: [Int:Int]) throws -> Data {
    let s = source, root = s.isJoinRoot == true
    guard ["video","audio","data"].contains(s.kind) else { throw RaceError.invalid("‘\(s.name)’: unsupported RaceRender input type \(s.kind).") }
    // RCZ has no verified native RR3 reader. A future CSV sidecar exporter can represent it.
    if s.kind == "data", URL(fileURLWithPath:s.path).pathExtension.lowercased() == "rcz" {
      throw RaceError.invalid("‘\(s.name)’: export RaceChrono data as CSV before creating a RaceRender project.")
    }
    var b = Data(repeating:0,count:2216)
    var settings = Data(repeating:0,count:root ? 0 : s.kind == "data" ? 11312 : 56)
    if !root && s.kind != "data" {
      // An alpha byte of 255 disables tinting. All-zero picture settings tint
      // the camera solid black in RR3, despite having neutral color controls.
      settings.putU32(0xff000000,40); settings.putFloat(45,44)
    }
    if let raw = project.legacyData, let offset = s.legacyOffset, offset >= 2152, offset+2216+settings.count <= raw.count {
      b = Data(raw[offset..<offset+2216]); settings = Data(raw[offset+2216..<offset+2216+settings.count])
    }
    try string(s.name,into:&b,at:0,size:128,field:"Input name")
    try string(s.path,into:&b,at:128,size:2048,field:"Input path")
    b[2176] = root ? (s.kind == "audio" ? 6 : 5) : s.kind == "data" ? 4 : s.kind == "audio" ? 2 : 1
    b[2178] = try input(s.joinedTo ?? -1,sources:sources)
    let t = s.timing ?? InputTiming()
    guard t.rate.isFinite, t.rate >= 0.01, t.rate <= 100, t.trimStart >= 0, t.projectStart >= 0 else { throw RaceError.invalid("‘\(s.name)’ has invalid input timing.") }
    b.putFloat(try finite(s.duration,"Source duration"),2184)
    b.putFloat(try finite(t.projectStart+max(0,-s.offset/t.rate),"Source delay"),2188)
    b.putFloat(try finite(t.trimStart+max(0,s.offset),"Source start"),2192)
    b.putFloat(try finite(t.trimEnd ?? 356400,"Source end"),2196)
    b.putU32(UInt32(clamping:s.legacyTrackIndex ?? 0),2200); b.putFloat(t.rate,2204); b[2209] = t.loop == true ? 1 : 0
    if root { return b }
    if s.kind == "data" {
      var warnings: [String] = []
      var original = LegacyProjectSettings.data(settings,warnings:&warnings)
      original?.speedUnit = project.speedUnit
      var desired = s.dataSettings ?? DataSettings()
      if let unit = desired.speedUnit, unit != project.speedUnit, desired.assignments["speed"] != nil {
        func unitsPerMPS(_ unit: String) -> Double { unit == "mph" ? 2.2369362921 : unit == "km/h" ? 3.6 : unit == "knots" ? 1/0.514444 : 1 }
        desired.speedMultiplier = (desired.speedMultiplier ?? 1)*unitsPerMPS(project.speedUnit)/unitsPerMPS(unit)
        desired.speedUnit = project.speedUnit
      }
      if original != desired { try dataSettings(desired, into:&settings) }
    }
    else {
      let a = s.audio ?? AudioSettings(); settings[0] = try byte(s.volume*a.volume*100,"Input volume")
      settings[1] = try byte((a.balance+1)*100,"Input balance")
      settings[2] = a.routing == .swap ? 1 : a.routing == .left ? 2 : a.routing == .right ? 3 : a.routing == .mono ? 4 : 0
      if s.kind == "video" {
        let p = s.picture ?? PictureSettings()
        var dimensions = b.u32(2180)
        if dimensions == 0, !s.path.isEmpty,
          let track = AVURLAsset(url:URL(fileURLWithPath:s.path)).tracks(withMediaType:.video).first {
          dimensions = UInt32(clamping:Int(abs(track.naturalSize.width))) | (UInt32(clamping:Int(abs(track.naturalSize.height))) << 16)
          b.putU32(dimensions,2180)
        }
        let width = Double(dimensions & 0xffff), height = Double(dimensions >> 16)
        if [p.left,p.right,p.top,p.bottom].contains(where: { $0 != 0 }), width == 0 || height == 0 { throw RaceError.invalid("‘\(s.name)’: relink the video to export its crop.") }
        for (offset,v) in [(4,p.left*width),(8,p.top*height),(12,p.right*width),(16,p.bottom*height)] {
          guard v.isFinite, v >= 0, v < Double(UInt32.max) else { throw RaceError.invalid("Invalid source crop.") }
          settings.putU32(UInt32(v.rounded()),offset)
        }
        settings.putFloat(try finite(p.rotation,"Rotation"),20)
        settings[24] = (p.flipX ? 1 : 0)+(p.flipY ? 2 : 0)
        for (offset,v) in [(25,p.brightness),(26,p.contrast),(27,p.saturation),(30,p.sharpness ?? 1)] { settings[offset] = try byte(v*100,"Picture adjustment") }
        let hue = try finite(p.hue ?? 0,"Hue")
        guard abs(hue) <= 180 else { throw RaceError.invalid("Hue must be between -180 and 180 degrees.") }
        let bits = UInt16(bitPattern:Int16(hue.rounded())); settings[28] = UInt8(truncatingIfNeeded:bits); settings[29] = UInt8(truncatingIfNeeded:bits >> 8)
      }
    }
    return b+settings
  }

  /// Native joins use the first physical clip as their source role. RR3 uses
  /// a separate virtual stream followed by its physical clips instead.
  /// Keep the role identifier and clock, giving only that first clip a new ID.
  static func canonicalJoins(_ original: RaceProject) throws -> RaceProject {
    var p = original
    let parents = Set(p.inputs.compactMap(\.joinedTo))
    var next = (p.inputs.map(\.legacyIndex).max() ?? -1)+1
    for parent in parents.sorted() {
      guard let index = p.inputs.firstIndex(where: { $0.legacyIndex == parent }), p.inputs[index].joinedTo == nil else {
        throw RaceError.invalid("A joined stream references a missing or nested parent.")
      }
      if p.inputs[index].isJoinRoot == true { continue }
      let source = p.inputs[index]
      guard ["video","audio"].contains(source.kind) else { throw RaceError.invalid("Only video/audio inputs can be joined in RaceRender.") }
      let clips = [source]+p.inputs.filter { $0.joinedTo == parent }
      guard clips.allSatisfy({ $0.kind == source.kind }) else { throw RaceError.invalid("A joined stream mixes incompatible input types.") }
      let length = clips.reduce(0.0) { sum, clip in
        let t = clip.timing ?? InputTiming(), rate = t.safeRate
        return sum+max(0,-clip.offset/rate)+max(0,min(clip.duration,t.trimEnd ?? clip.duration)-max(0,t.trimStart)-max(0,clip.offset))/rate
      }
      var root = MediaInput(name:source.name,path:"",kind:source.kind,legacyIndex:parent)
      root.isJoinRoot = true; root.duration = length
      var timing = InputTiming(); timing.projectStart = source.timing?.projectStart ?? 0; timing.loop = source.timing?.loop
      root.timing = timing
      var child = source; child.legacyIndex = next; next += 1; child.joinedTo = parent
      child.timing?.projectStart = 0; child.timing?.loop = nil
      for i in p.inputs.indices where p.inputs[i].joinedTo == parent { p.inputs[i].timing?.projectStart = 0 }
      p.inputs.replaceSubrange(index...index,with:[root,child])
    }
    return p
  }

  static func dataSettings(_ s: DataSettings, into b: inout Data) throws {
    guard s.detectGPSUpdates != true,s.smoothCurves != true else {
      throw RaceError.invalid("GPS update reconstruction and smooth map curves require .orrp; their native flags are not verified.")
    }
    guard s.accuracyMultiplier == nil, s.speedConversionEnabled == nil else {
      throw RaceError.invalid("Explicit speed-unit overrides and GPS accuracy conversion require .orrp; their native representation is not verified.")
    }
    guard s.gearDerivation != .recordedOnly,(s.gearEstimation ?? GearEstimationSettings()) == GearEstimationSettings() else {
      throw RaceError.invalid("Recorded-only gear and custom gear calibration require .orrp; their native settings are not verified.")
    }
    guard s.headingDerivation != .recordedOnly,
      (s.longitudinalDerivation ?? .automatic) == .automatic,
      (s.lateralDerivation ?? .automatic) == .automatic else {
      throw RaceError.invalid("Explicit recorded-only heading and G-force calculation modes require .orrp; their native source controls are not verified.")
    }
    let fields = [("time",0),("lon",132),("lat",260),("altitude",388),("accuracy",516),("lap",648),("speed",776),("heading",908),("rpm",1040),("gear",1168),("gx",1296),("gy",1424)]
    guard Set(s.assignments.filter{!$0.value.isEmpty}.map(\.key)).isSubset(of:Set(fields.map(\.0))) else { throw RaceError.invalid("Some custom data assignments have no RaceRender input-setting field.") }
    for (alias,offset) in fields { try string(s.assignments[alias] ?? "",into:&b,at:offset,size:128,field:"Data assignment") }
    if s.headingDerivation == .calculate { try string("(Calculate)",into:&b,at:908,size:128,field:"Heading calculation") }
    if s.gearDerivation == .calculate { try string("(Calculate)",into:&b,at:1168,size:128,field:"Gear calculation") }
    b.putFloat(try finite(s.timeUnitsPerSecond ?? 1,"Time units"),128)
    b.putFloat(try finite(s.speedMultiplier ?? 1,"Speed conversion"),904)
    b.putFloat(try finite(s.headingAdjustment ?? 0,"Heading adjustment"),1036)
    b[1593] = s.reverseHeading == true ? 1 : 0
    b[1594] = try byte(Double(s.ignoreLapTriggers ?? 0),"Ignored lap triggers")
    b[1595] = s.interpolate == false ? b[1595] & ~1 : b[1595] | 1
    let gear = s.gearAdjustment ?? 0
    guard gear.isFinite, gear.rounded() == gear, (-128...127).contains(gear) else { throw RaceError.invalid("RaceRender supports only whole-number gear adjustments (-128…127).") }
    b[2656] = UInt8(bitPattern:Int8(gear))
    guard s.finishLine == nil else { throw RaceError.invalid("Custom GPS finish-line export is not verified; save in .orrp format.") }
    b[1592] &= ~128
    guard s.fields.count <= 4 else { throw RaceError.invalid("RaceRender supports four calculated data fields.") }
    for i in 0..<4 {
      let offset = 1600+i*264
      b.replaceSubrange(offset..<offset+264,with:Data(repeating:0,count:264)); b[1596+i] = 0
      guard i < s.fields.count else { continue }
      let f = s.fields[i]
      let operation: UInt8, operand: Double
      if f.absolute == true, f.multiply == 1, f.add == 0 { operation = 4; operand = 0 }
      else if f.absolute != true, f.multiply == 1 { operation = 0; operand = f.add }
      else if f.absolute != true, f.add == 0 { operation = 2; operand = f.multiply }
      else { throw RaceError.invalid("Calculated field ‘\(f.name)’ combines operations. RaceRender supports one operation per field.") }
      try string(f.name,into:&b,at:offset,size:128,field:"Calculated field name")
      try string(f.source,into:&b,at:offset+128,size:128,field:"Calculated source")
      b.putFloat(try finite(operand,"Calculated operand"),offset+256); b[1596+i] = operation
    }
  }

  static func timeline(_ object: DisplayObject, sources: [Int:Int], parents: [Int:Int]) throws -> [Data] {
    var previous = object, result: [Data] = []
    var segments = object.segments ?? []
    if object.end < 1_000_000 { var end = ObjectSegment(time:object.end); end.visible = false; segments.append(end) }
    guard segments.count <= 10000 else { throw RaceError.invalid("Too many timeline segments.") }
    for segment in segments.sorted(by: { $0.time < $1.time }) {
      guard segment.time.isFinite, segment.time >= 0 else { throw RaceError.invalid("Invalid timeline time.") }
      var value = previous; segment.apply(to:&value)
      let old = try record(previous,sources:sources,parents:parents), new = try record(value,sources:sources,parents:parents)
      guard old.common[280] == new.common[280] else {
        throw RaceError.invalid("Changing display renderer types in a timeline segment requires .orrp format.")
      }
      if old.image != new.image, new.image == word(0), old.image != word(0) {
        throw RaceError.invalid("Clearing background artwork in a timeline segment requires .orrp format.")
      }
      var b = Data(repeating:0,count:208), flags: UInt32 = 0
      b.putFloat(segment.time,0)
      if old.common[282] != new.common[282] { flags |= 1 }
      if previous.x != value.x || previous.y != value.y { flags |= 2 }
      if previous.width != value.width || previous.height != value.height { flags |= 4 }
      if previous.visible != value.visible { flags |= 8 }
      if old.common[285] != new.common[285] { flags |= 16 }
      if old.common[286] != new.common[286] { flags |= 32 }
      if old.common[294] != new.common[294] { flags |= 128 }
      if previous.style != value.style { flags |= 256 }
      if old.common[292] != new.common[292] { flags |= 1024 }
      if old.common[293] != new.common[293] { flags |= 2048 }
      if old.payload != new.payload { flags |= 4096 }
      b.putU32(flags,4)
      b.replaceSubrange(8..<136,with:new.common[128..<256])
      for (dest,source) in [(136,260),(140,264),(144,268),(148,272)] { b.putU32(new.common.u32(source),dest) }
      b[152] = value.visible ? 1 : 0; b[153] = new.common[285]; b[154] = new.common[286]
      b[156] = new.common[294]; b[157] = new.common[282]; b[159] = new.common[292]; b[160] = new.common[293]
      let payload = flags & 4096 != 0 ? new.payload : Data()
      b.append(word(payload.count)); b.append(payload); b.append(old.image != new.image ? new.image : word(0))
      result.append(b); previous = value
    }
    return result
  }

  static func gauge(_ o: DisplayObject, common: inout Data, payload: inout Data) throws {
    // Retain richer imported settings exactly when their decoded controls are unchanged.
    if let original = o.legacyPayload, original.count >= 640, o.legacyCommon?.count == 344 {
      var decoded = LegacyReader.decodeCommon(o.legacyCommon!,at:0,legacyIndex:0)
      decoded.legacyPayload = original; LegacyReader.inferDetails(&decoded)
      if decoded.gauge == o.gauge, decoded.minimum == o.minimum, decoded.maximum == o.maximum, decoded.color == o.color {
        try string(o.channel,into:&payload,at:0,size:128,field:"Gauge channel"); return
      }
    }
    let g = o.gauge ?? GaugeSettings(), d = o.editableGaugeDesign
    guard d.majorStyle == .dash, d.minorStyle == .dash,
      !d.needleChange.enabled, !d.markingChange.enabled, !d.faceChange.enabled,
      [0.0,0.2].contains(d.smoothing), d.numberStyle.font == d.labelStyle.font,
      d.numberStyle.automaticPosition else {
      throw RaceError.invalid("‘\(o.name)’: this expanded gauge design has no verified RaceRender encoding. Unchanged imported designs can be exported; save new advanced designs in .orrp format.")
    }
    guard [1.0,10,100,1000].contains(g.numberingScale), [0,2].contains(g.decimals) else { throw RaceError.invalid("RaceRender gauges support zero or two decimals, and numbering scales of 1, 10, 100 or 1000.") }
    if payload.count < 712 { payload = Data(repeating:0,count:712) }
    common.putU32(640 | (640 << 16),296); common[283] = 0; common[285] = 1
    let radius = 153.6
    try string(o.channel.isEmpty ? "(Automatic)" : o.channel,into:&payload,at:0,size:128,field:"Gauge channel")
    let label = o.gauge == nil ? (o.kind == .rpm ? "RPM" : o.kind == .speed ? "%su%" : g.label) : g.label
    try string(label,into:&payload,at:128,size:128,field:"Gauge label")
    payload.putDouble(d.automaticMinimum ? 100_000_000 : try finite(o.minimum,"Gauge minimum"),256)
    payload.putDouble(d.automaticMaximum ? 100_000_000 : try finite(o.maximum,"Gauge maximum"),264)
    let interval = g.tickInterval ?? (o.maximum-o.minimum)/Double(max(1,g.divisions))
    guard interval.isFinite, interval > 0 else { throw RaceError.invalid("Gauge interval must be positive.") }
    payload.putDouble(interval,272); payload.putDouble(d.minorInterval ?? interval/Double(max(1,d.minorDivisions)),280)
    payload.putDouble(g.redline ?? 100_000_000,288)
    let sweep = try finite(g.sweep,"Gauge sweep"), rotation = try finite(g.rotation,"Gauge rotation")
    guard (1...360).contains(sweep), abs(rotation) <= 360 else { throw RaceError.invalid("Invalid gauge angles.") }
    payload.putU32(UInt32(sweep.rounded()) | (UInt32(UInt16(bitPattern:Int16(rotation.rounded()))) << 16),296)
    for (offset,color,enabled) in [(300,d.faceColor,g.showFace),(304,d.faceSecondColor,d.faceGradient),(308,d.needleColor,true),(312,d.centerColor,true),(316,d.trimColor,d.trim),(320,d.marksColor,d.showMajor),(324,"#000000",false),(328,g.warningColor,true),(332,d.labelStyle.color,g.showLabels),(336,d.valueStyle.color,g.showNumber),(340,d.pinColor,d.pins),(680,d.dualColor,true),(684,d.minorColor,d.showMinor),(692,d.numberStyle.color,g.showLabels)] { payload.putU32(try rgb(color,enabled:enabled),offset) }
    // Newer records append three indicator gradients and the second alert
    // color. Zero means enabled black, so initialize unused layers disabled.
    for offset in [696,700,704,708] { payload.putU32(0xff000000,offset) }
    try string(d.labelStyle.font,into:&payload,at:352,size:128,field:"Gauge font")
    try string(d.valueStyle.font,into:&payload,at:480,size:128,field:"Gauge value font")
    for (offset,value) in [(608,d.labelStyle.size),(612,d.valueStyle.size),(664,d.numberStyle.size)] { payload.putFloat(try finite(value*radius/100,"Gauge caption size"),offset) }
    payload[616] = (d.labelStyle.bold ? 1 : 0) | (d.labelStyle.italic ? 2 : 0)
    payload[617] = (d.valueStyle.bold ? 1 : 0) | (d.valueStyle.italic ? 2 : 0)
    payload[618] = o.kind == .rpm ? 2 : o.kind == .speed ? 1 : 0
    payload[619] = 128 | (g.counterClockwise ? 1 : 0) | (d.smoothing == 0.2 ? 2 : 0) | (g.decimals == 2 ? 4 : 0) | (d.limitClutter ? 8 : 0)
      | (d.mode == .dualNeedle ? 16 : d.mode == .filled ? 48 : 0)
    payload[627] = 128 | (d.showMajor ? 7 : 0) | (d.showMinor ? 7 << 3 : 0)
    for (offset,value) in [(622,d.trimWidth),(623,d.needleWidth/2),(624,d.tip),(626,d.centerSize),(629,d.majorWidth*2),(630,d.minorWidth*2),(688,d.majorLength),(689,d.minorLength)] { payload[offset] = try byte(value*radius/100,"Gauge geometry") }
    let tail = try finite(d.tail*radius/100,"Needle tail")
    guard (-128...127).contains(tail) else { throw RaceError.invalid("Needle tail is outside RaceRender's signed-byte range.") }
    payload[625] = UInt8(bitPattern:Int8(tail.rounded())); payload[635] = try byte(d.taper,"Needle taper")
    payload[633] = (g.showLabels ? 1 : 0) | (d.everyOtherNumber ? 2 : 0) | (d.numberExtremes ? 4 : 0)
      | (g.numberingScale == 1000 ? 8 : g.numberingScale == 100 ? 16 : g.numberingScale == 10 ? 24 : 0)
    payload[634] = g.redline == nil ? 0 : 1
    payload[628] = try byte(d.pinSize*radius/100,"Pin size")
    if let split = d.splitValue {
      guard split.isFinite, split > o.minimum, split < o.maximum, d.splitAngle.isFinite, (1...360).contains(d.splitAngle) else { throw RaceError.invalid("Gauge split must lie within its data range and have an angle of 1–360 degrees.") }
      payload.putDouble(split,648)
      payload.putU32(UInt32(d.splitAngle.rounded()),656)
    } else { payload.putDouble(0,648); payload.putU32(0,656) }
    payload[669] = try byte(d.dualWidth*radius/100,"Second needle width")
    payload[670] = try byte(d.dualTip*radius/100,"Second needle tip")
    let dualTail = try finite(d.dualTail*radius/100,"Second needle tail")
    guard (-128...127).contains(dualTail) else { throw RaceError.invalid("Second needle tail is outside RaceRender's signed-byte range.") }
    payload[671] = UInt8(bitPattern:Int8(dualTail.rounded()))
    payload.putDouble(try finite(d.dualInterval,"Dual needle interval"),672)
    for (offset,caption) in [(344,d.labelStyle),(348,d.valueStyle)] {
      if caption.automaticPosition { payload.putU32(.max,offset) }
      else {
        let x = try finite(caption.x*3.2,"Gauge caption X"), y = try finite((100-caption.y)*3.2,"Gauge caption Y")
        guard (0...65535).contains(x), (0...65535).contains(y) else { throw RaceError.invalid("Gauge caption lies outside the legacy raster.") }
        payload.putU32(UInt32(x.rounded()) | (UInt32(y.rounded()) << 16),offset)
      }
    }
  }

  /// Byte-folded checksum/key derivation. Arithmetic is intentionally wrapping.
  static func integrity(_ data: Data, seed: UInt32, count: Int = 8) -> Data {
    guard count > 0 else { return Data() }
    var result = [UInt8](repeating:UInt8(truncatingIfNeeded:seed),count:count)
    if !data.isEmpty { for i in 0..<max(data.count,count) { result[i%count] &+= data[i%data.count] ^ 0xaa } }
    let stride = UInt32(data.count+count)
    var state = Int32(bitPattern:seed), acc = seed &* stride
    for i in 0..<count {
      let positive = state < 0 ? UInt32(0x7fff_ffff) &- UInt32(bitPattern:state) : UInt32(state)
      state = Int32(Int16(truncatingIfNeeded:positive &* 18000 &+ (positive >> 16)))
      result[i] &+= UInt8(truncatingIfNeeded:positive &* 80 &+ (positive >> 16) &+ acc)
      acc &+= stride
    }
    return Data(result)
  }
  static func word(_ value: Int) -> Data { word(UInt32(clamping:value)) }
  static func word(_ value: UInt32) -> Data { var b = Data(count:4); b.putU32(value,0); return b }
  static func finite(_ value: Double, _ field: String) throws -> Double {
    guard value.isFinite, Float(value).isFinite else { throw RaceError.invalid("\(field) must be a finite number in the RaceRender range.") }; return value
  }
  static func byte(_ value: Double, _ field: String) throws -> UInt8 {
    guard value.isFinite, value.rounded() >= 0, value.rounded() <= 255 else { throw RaceError.invalid("\(field) is outside RaceRender's 0–255 range.") }; return UInt8(value.rounded())
  }
  static func string(_ value: String, into b: inout Data, at offset: Int, size: Int, field: String) throws {
    guard value.utf16.count < size/2, !value.contains("\0") else { throw RaceError.invalid("\(field) is too long for RaceRender (maximum \(size/2-1) UTF-16 units).") }
    b.putUTF16(value,offset,size)
  }
  static func rgb(_ value: String, enabled: Bool = true) throws -> UInt32 {
    let text = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard text.count == 6, let rgb = UInt32(text,radix:16) else { throw RaceError.invalid("Invalid RGB color \(value).") }
    return rgb | (enabled ? 0 : 0xff000000)
  }
  static func input(_ index: Int, sources: [Int:Int]) throws -> UInt8 {
    if index < 0 { return 255 }
    if let mapped = sources[index], mapped < 255 { return UInt8(mapped) }
    if index == 255 { return 255 } // imported unassigned byte, absent from actual source roles
    throw RaceError.invalid("Display or join references missing input \(index).")
  }
  static func workspace(_ project: RaceProject) throws -> UInt8 {
    let ratio = Double(project.width)/Double(max(1,project.height))
    if abs(ratio-16.0/9) < 0.001 { return 2 }; if abs(ratio-4.0/3) < 0.001 { return 0 }
    throw RaceError.invalid("RaceRender export currently supports 16:9 and 4:3 workspaces. Save other canvas sizes in .orrp format.")
  }
  static func noTimeline(_ p: RaceProject) throws {
    guard p.objects.allSatisfy({ ($0.segments ?? []).isEmpty && $0.start == 0 && $0.end >= 1_000_000 }) else {
      throw RaceError.invalid("RaceRender templates/styles cannot carry timeline events or display time bounds. Export an RRP project to retain them, or use .orrt.")
    }
  }
  static func bitmap(_ data: Data) throws -> Data {
    guard let image = NSImage(data:data)?.cgImage(forProposedRect:nil,context:nil,hints:nil), image.width <= 4096, image.height <= 4096,
      let c = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:OverlayRenderer.colorSpace,
        bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw RaceError.invalid("Artwork cannot be encoded as a legacy BGRA bitmap (maximum 4096×4096).") }
    c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    var b = word(8 | (UInt32(image.width) << 16)); b.append(word(UInt32(image.height)))
    b.append(Data(bytes:c.data!,count:image.width*image.height*4)); return b
  }
  static func preview(_ project: RaceProject, width: Int, height: Int) -> Data {
    guard let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo) else { return Data(repeating:0,count:width*height*3) }
    OverlayRenderer.draw(c,scene:WidgetDesign.scene(project),time:18,size:CGSize(width:width,height:height))
    let pixels = c.data!.assumingMemoryBound(to:UInt8.self)
    var result = Data(capacity:width*height*3)
    // Templates use bottom-up BGR triples, without an alpha channel.
    for y in (0..<height).reversed() { for x in 0..<width { let i = (y*width+x)*4; result.append(pixels[i]); result.append(pixels[i+1]); result.append(pixels[i+2]) } }
    return result
  }
}

extension Data {
  mutating func putDouble(_ value: Double, _ offset: Int) {
    putU32(UInt32(truncatingIfNeeded:value.bitPattern),offset); putU32(UInt32(value.bitPattern >> 32),offset+4)
  }
}
