import Foundation

/// Original, bounded readers for RaceRender's on-disk interchange formats.
/// No vendor executable, framework, artwork or templates are needed at runtime.
public enum LegacyReader {
  public static func read(_ url: URL) throws -> RaceProject {
    let b = try Data(contentsOf: url)
    guard b.count >= 56, b.count <= 128 * 1024 * 1024 else {
      throw RaceError.invalid("Invalid or oversized RaceRender file.")
    }
    let magic = String(data: b.prefix(4), encoding: .ascii) ?? ""
    var p: RaceProject
    switch magic {
    case "RRP3": p = try project(b, base: url.deletingLastPathComponent())
    case "rrt1", "rrt2": p = try template(b)
    case "rro1", "rro2", "rro3": p = try style(b)
    default:
      throw RaceError.invalid(
        "Unsupported RaceRender signature: \(magic). Supported: RRP3, rrt1/2, rro1/2/3.")
    }
    p.name = url.deletingPathExtension().lastPathComponent
    if magic.hasPrefix("rro"), !p.objects.isEmpty {
      p.objects[0].name = p.name
      p.objects[0].style = p.name
      p.objects[0].kind = kind(p.objects[0].legacyType ?? 0, name: p.name)
    }
    p.sourcePath = url.path
    return p
  }

  static func project(_ b: Data, base: URL) throws -> RaceProject {
    var p = RaceProject()
    p.legacyData = b
    let sourceCount = Int(b.u32(16))
    let objectCount = Int(b.u32(32))
    let sourceSize = Int(b.u32(20))
    let segmentSize = Int(b.u32(28))
    guard sourceCount <= 512, objectCount <= 10000, sourceSize >= 2216, sourceSize < 65536,
      segmentSize < 65536
    else { throw RaceError.invalid("Unsupported RRP3 record sizes or counts.") }
    var cursor = Int(b.u32(12))
    LegacyProjectSettings.header(b, project: &p, sourceStart: cursor)
    // RRP3's fixed project header stores the green/red output flags as seconds.
    // Native Control-click reset writes zero; there are no separate enable bits.
    if cursor >= 2152, b.count >= 2152 {
      let start = b.f32(2128), end = b.f32(2132)
      if start.isFinite, start > 0 { p.rangeStart = start }
      if end.isFinite, end > 0 { p.rangeEnd = end }
    }
    for i in 0..<sourceCount {
      guard cursor >= 56, cursor + sourceSize <= b.count else {
        throw RaceError.invalid("Truncated RRP3 input record.")
      }
      let name = b.utf16(cursor, 128)
      let path = b.utf16(cursor + 128, 2048)
      let type = b[cursor + 2176]
      let kind = type == 4 ? "data" : (type == 2 ? "audio" : "video")
      var input = MediaInput(
        name: name, path: RaceProject.resolvePath(path, base: base), kind: kind, legacyIndex: i)
      input.duration = b.f32(cursor + 2184)
      input.offset = b.f32(cursor + 2192)
      input.legacyOffset = cursor
      let dataSize = Int(b.u32(24))
      let settingsSize = [5,6].contains(type) ? 0 : type == 4 && dataSize >= 2660 && dataSize <= 65536 ? dataSize : segmentSize
      guard cursor + sourceSize + settingsSize <= b.count else { throw RaceError.invalid("Truncated RRP3 source settings.") }
      let sourceSettings = Data(b[cursor + sourceSize..<cursor + sourceSize + settingsSize])
      // RRP3 stores input picture controls in the following settings record.
      // Percentages are bytes; leave unknown fields and non-video settings opaque.
      if kind == "video", type == 1, settingsSize >= 28 {
        let settings = cursor + sourceSize
        var picture = PictureSettings()
        picture.legacyColorInterpretation = true
        picture.brightness = Double(b[settings + 25]) / 100
        picture.contrast = Double(b[settings + 26]) / 100
        picture.saturation = Double(b[settings + 27]) / 100
        if settingsSize >= 30 {
          picture.hue = Double(Int16(bitPattern: UInt16(b[settings + 28]) | UInt16(b[settings + 29]) << 8))
        }
        if settingsSize >= 31 { picture.sharpness = Double(b[settings + 30]) / 100 }
        input.picture = picture
      }
      if !input.duration.isFinite || input.duration < 0 { input.duration = 0 }
      if !input.offset.isFinite { input.offset = 0 }
      LegacyProjectSettings.input(b, at: cursor, settings: sourceSettings, input: &input, warnings: &p.warnings)
      input.dataSettings?.speedUnit = p.speedUnit
      p.inputs.append(input)
      cursor += sourceSize + settingsSize
    }
    for index in p.inputs.indices {
      if let parent = p.inputs[index].joinedTo,
        !p.inputs.contains(where: { $0.legacyIndex == parent && $0.isJoinRoot == true }) || parent == p.inputs[index].legacyIndex {
        p.inputs[index].joinedTo = nil
      }
    }
    // Modern RRP3 uses one contiguous object table, followed by an array of
    // per-object segment counts and variable-size segment records.
    if b.u32(36) == 344, b.u32(44) == 208, b.u32(12) >= 2152 {
      for index in 0..<objectCount {
        guard cursor + 348 <= b.count, validCommon(b, at: cursor) else { throw RaceError.invalid("Invalid RRP3 display record \(index).") }
        var object = decodeCommon(b, at: cursor, legacyIndex: index)
        object.legacyOffset = cursor
        let length = Int(b.u32(cursor + 344)); cursor += 348
        guard length <= 4 * 1024 * 1024, cursor + length <= b.count else { throw RaceError.invalid("Truncated RRP3 display parameters.") }
        object.legacyPayload = Data(b[cursor..<cursor + length]); cursor += length
        object.embeddedImage = try LegacyProjectSettings.image(b, cursor: &cursor)
        object.artwork = object.embeddedImage.flatMap { LegacyArtwork.png($0) }
        inferDetails(&object)
        p.objects.append(object)
      }
      try LegacyProjectSettings.timelines(b, cursor: &cursor, recordSize: 208, project: &p)
      p.warnings.append("RRP import: \(p.inputs.count) inputs, \(p.inputs.filter { $0.isJoinRoot == true }.count) joined streams, \(p.objects.reduce(0) { $0 + ($1.segments?.count ?? 0) }) timeline segments. Source timing, project length, notes, units and recognized data/picture/audio settings were imported.")
      addWarnings(&p)
      return p
    }
    // Scan structurally rather than assuming optional data-channel/timeline block lengths.
    var i = max(56, cursor - segmentSize)
    while i + 344 <= b.count && p.objects.count < objectCount {
      if validCommon(b, at: i, strict: true) {
        var o = decodeCommon(b, at: i, legacyIndex: p.objects.count)
        o.legacyOffset = i
        let n = Int(b.u32(i + 344))
        if n <= 4 * 1024 * 1024, i + 348 + n <= b.count {
          o.legacyPayload = Data(b[i + 348..<i + 348 + n])
          inferDetails(&o)
          let end = i+348+n
          if end < b.count, let image = LegacyArtwork.png(Data(b[end..<b.count])) {
            o.artwork = image
          }
        }
        p.objects.append(o)
        i += 348 + (o.legacyPayload?.count ?? 0)
      } else {
        i += 2
      }
    }
    if p.objects.count != objectCount {
      p.warnings.append(
        "Recovered \(p.objects.count) of \(objectCount) objects. Additional timeline variants may be unsupported."
      )
    }
    if p.objects.isEmpty && objectCount > 0 {
      throw RaceError.invalid("No supported display records found in RRP3 project.")
    }
    addWarnings(&p)
    return p
  }

  static func validCommon(_ b: Data, at p: Int, short: Bool = false, strict: Bool = false) -> Bool {
    guard p >= 0, p + (short ? 296 : 344) <= b.count else { return false }
    let name = b.utf16(p, 128)
    guard !name.isEmpty, name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xfffe })
    else { return false }
    let parent = Int32(bitPattern: b.u32(p + 256))
    let type = Int(b[p + 280])
    guard parent >= -1 && parent < 10000, (0...100).contains(type) else { return false }
    let values = [260, 264, 268, 272].map { b.f32(p + $0) }
    return values.allSatisfy { $0.isFinite && abs($0) < 10000 } && values[2] >= 0.001
      && values[3] >= 0.001 && (!strict || b[p + 281] >= 1) && b[p + 281] <= 4
  }

  static func decodeCommon(_ b: Data, at p: Int, legacyIndex: Int) -> DisplayObject {
    let name = b.utf16(p, 128)
    let style = b.utf16(p + 128, 128)
    let type = Int(b[p + 280])
    var o = DisplayObject(name: name, kind: kind(type, name: name + " " + style))
    o.style = style
    o.x = b.f32(p + 260)
    o.y = b.f32(p + 264)
    o.width = b.f32(p + 268)
    o.height = b.f32(p + 272)
    o.parentIndex = Int(Int32(bitPattern: b.u32(p + 256)))
    o.inputIndex = Int(b[p + 282])
    o.legacyActivation = Int(b[p + 284])
    o.visible = b[p + 284] <= 1
    o.opacity = max(0, 1 - Double(b[p + 294]) / 100)
    o.legacyType = type
    o.legacyIndex = legacyIndex
    o.legacyCommon = Data(b[p..<min(p + 344, b.count)])
    if [.video,.image].contains(o.kind) {
      var picture = PictureSettings(); picture.maintainAspect = b[p + 285] != 0
      picture.flipX = b[p + 286] == 1 || b[p + 286] == 3; picture.flipY = b[p + 286] == 2 || b[p + 286] == 3
      o.picture = picture
    }
    let start = b.f32(p + 276)
    if start.isFinite, start > 0 { o.start = start }
    if [.video, .audio].contains(o.kind) {
      var audio = AudioSettings(); audio.volume = Double(b[p + 292]) / 100; audio.balance = Double(b[p + 293]) / 100 - 1
      if audio != AudioSettings() { o.audio = audio }
    }
    o.maximum = o.kind == .rpm || o.kind == .lights ? 8000 : (o.kind == .speed ? 160 : 100)
    return o
  }

  static func kind(_ type: Int, name: String) -> ObjectKind {
    if type == 35 { return .graph }
    if type == 10 { return .video }; if type == 11 { return .audio }
    if type == 12 { return .shape }; if type == 13 { return .text }; if type == 14 { return .image }
    let s = name.lowercased()
    if s.contains("delta") { return .delta }
    if s.contains("best") && s.contains("time") { return .bestTime }
    if s.contains("best") && s.contains("lap") { return .bestLap }
    if s.contains("shift") || s.contains("lights") { return .lights }
    if s.contains("gear") { return .gear }
    if s.contains("throttle") { return .throttle }
    if s.contains("brake") { return .brake }
    if s.contains("temperature") || s.contains("thermometer") { return .temperature }
    if s.contains("tach") || s.contains("rpm") { return .rpm }
    if s.contains("speed") { return .speed }
    if s.contains("g-force") || s.contains("g force") { return .gforce }
    switch type {
    case 10: return .video
    case 11: return .audio
    case 12: return .shape
    case 30: return .gauge
    case 31: return .bar
    case 35: return .graph
    case 32: return .enhanced
    case 50: return .enhanced
    case 70: return .map
    case 74: return .gforce
    case 76: return .lap
    case 77: return .timer
    case 0: return .group
    case 13, 20: return .text
    case 21: return .shape
    default: return .enhanced
    }
  }

  static func inferDetails(_ o: inout DisplayObject) {
    guard let d = o.legacyPayload else { return }
    if o.legacyType == 30, [.speed, .rpm, .gauge].contains(o.kind), d.count >= 344 {
      // Common gauge payload: two UTF-16 labels, four doubles, then packed angles.
      let minimum = d.f64(256), maximum = d.f64(264)
      if minimum.isFinite, maximum.isFinite, maximum > minimum, abs(minimum) < 1e10, maximum < 1e10 {
        o.minimum = minimum; o.maximum = maximum
      }
      let channel = d.utf16(0,128)
      if !channel.isEmpty, !channel.lowercased().contains("automatic") { o.channel = channel }
      var g = GaugeSettings()
      g.label = d.utf16(128,128)
      let interval = d.f64(272)
      if interval.isFinite, interval > 0, interval <= o.maximum-o.minimum { g.tickInterval = interval }
      if d.count >= 634 {
        g.numberingScale = d[633] & 24 == 8 ? 1000 : d[633] & 24 == 16 ? 100 : d[633] & 24 == 24 ? 10 : 1
        g.decimals = d[619] & 4 != 0 ? 2 : 0
      }
      if d.count >= 624 {
        // Legacy color records use an all-ones transparency byte to disable a layer.
        g.showNumber = d.u32(336) >> 24 != 255
        g.showLabels = d.u32(332) >> 24 != 255
        g.showFace = d.u32(300) >> 24 != 255
      }
      let sweep = Int(d[296]) | Int(d[297]) << 8
      let rotation = Int(Int16(bitPattern: UInt16(d[298]) | UInt16(d[299]) << 8))
      if (1...360).contains(sweep) { g.sweep = Double(sweep) }
      if abs(rotation) <= 360 { g.rotation = Double(rotation) }
      if d.count >= 620 { g.counterClockwise = d[619] & 1 != 0 }
      o.color = String(format: "#%06X", d.u32(308) & 0x00ff_ffff)
      o.gauge = g
      if d.count >= 696, ([UInt8(0x10),0x30].contains(d[619] & 0x70) ||
        (d.f64(648) > o.minimum && d.f64(648) < o.maximum && (d[656] != 0 || d[657] != 0))) {
        let design = o.editableGaugeDesign
        o.gauge?.design = design
      }
    }
    if [31,35,50].contains(o.legacyType ?? -1),
      d.count >= 128
    {
      let channel = d.utf16(0,128)
      o.channel = channel.hasPrefix("(") && channel.hasSuffix(")") ? String(channel.dropFirst().dropLast()) : channel
      if o.hasStyleRange {
        if let minimum = o.styleMinimum { o.minimum = minimum }
        if let maximum = o.styleMaximum { o.maximum = maximum }
      }
    }
    if o.legacyType == 14 {
      o.imageControl = ImageControlSettings.legacy(o)
      if d.count >= 128 { o.channel = d.utf16(0,128) }
    }
    if o.legacyType == 35 {
      o.kind = .graph; o.graph = GraphSettings.legacy(o)
      if d.count >= 272 {
        if d.f64(256).isFinite && abs(d.f64(256)) < 9e7 { o.minimum = d.f64(256) }
        if d.f64(264).isFinite && abs(d.f64(264)) < 9e7 { o.maximum = d.f64(264) }
      }
    }
    if o.kind == .temperature && o.channel.isEmpty { o.channel = o.name }
    // Retain all bytes, but never execute arbitrary imported code.
    if o.legacyType == 13, d.count >= 656 {
      o.text = d.utf16(4, 512)
      o.color = String(format: "#%06X", d.u32(0) & 0xffffff)
      var t = TextSettings()
      t.font = d.utf16(516, 128); t.size = d.f32(644); t.referenceHeight = 480
      t.bold = d[648] & 1 != 0; t.italic = d[648] & 2 != 0
      t.underline = d[648] & 4 != 0; t.strikethrough = d[648] & 8 != 0
      t.alignment = d[649] == 1 ? .center : d[649] == 2 ? .right : .left
      t.fitToBox = d[650] != 0; t.outline = d[651] != 0
      t.outlineColor = String(format: "#%06X", d.u32(652) & 0xffffff)
      o.typography = t
    } else if o.kind == .text, d.count >= 256 { o.text = d.utf16(0, 256) }
    if o.legacyType == 12, d.count >= 20 {
      var shape = ShapeSettings()
      shape.kind = d[8] == 3 ? .ellipse : d[8] == 1 ? .roundedRectangle : d[8] == 2 ? .rounderRectangle : .rectangle
      shape.fill = d.u32(4) >> 24 != 255; shape.stroke = d.u32(0) >> 24 != 255
      shape.strokeColor = String(format: "#%06X", d.u32(0) & 0xffffff)
      o.color = String(format: "#%06X", d.u32(4) & 0xffffff)
      shape.gradient = d.u32(12) >> 24 != 255
      shape.gradientColor = String(format: "#%06X", d.u32(12) & 0xffffff)
      shape.strokeWidth = Double(d[9]); shape.referenceHeight = 480
      o.shape = shape
    }
  }

  /// Recover the known early-generator error in native copies of 67,168-byte
  /// Enhanced payloads. This exact signature came from the affected template
  /// key/length pair; never guess at arbitrary missing or localized channels.
  static func repairOldChannelDecode(_ o: inout DisplayObject) {
    guard o.legacyType == 50, var payload = o.legacyPayload, payload.count == 67168,
      payload[5] == 0x16, payload[7] == 0x3c, payload[9] == 0xa0 else { return }
    let old = payload.utf16(0,128)
    for (i, mask) in [UInt8(0x34),0x16,0x6e,0x3c,0x1a,0xa0].enumerated() { payload[4+i] ^= mask }
    let repaired = payload.utf16(0,128)
    guard !repaired.isEmpty, repaired.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { return }
    func unwrapped(_ name: String) -> String {
      name.hasPrefix("(") && name.hasSuffix(")") ? String(name.dropFirst().dropLast()) : name
    }
    // Explicit native overrides, including Automatic and segment overrides, win.
    if o.channel == old || o.channel == unwrapped(old) { o.channel = unwrapped(repaired) }
    for i in (o.segments ?? []).indices {
      if let channel = o.segments?[i].channel, channel == old || channel == unwrapped(old) {
        o.segments?[i].channel = unwrapped(repaired)
      }
    }
    o.legacyPayload = payload
  }

  static func addWarnings(_ p: inout RaceProject) {
    if p.objects.contains(where: { $0.legacyType == 50 }) {
      p.warnings.append(
        "Enhanced styles use a bounded drawing interpreter with deterministic persistent-state replay. Unsupported language features fall back to a native display."
      )
    }
    p.warnings.append(
      "Imported visuals retain saved style settings, supported drawing scripts, typography and decoded artwork. Font metrics, sharpness response and unsupported specialized effects may differ; specific import limitations are listed separately. RaceRender's application-wide preview/export preferences are not stored in an RRP project."
    )
    if p.inputs.contains(where: { !$0.path.isEmpty && !$0.exists }) {
      p.warnings.append("Some input files are missing. Use Relink in the input inspector.")
    }
  }

  static func template(_ b: Data) throws -> RaceProject {
    var p = RaceProject()
    let version2 = b[3] == 50
    if version2, b.count > 64825, b.u32(64817) == 136 {
      if b[12] == 0 { p.width = 1440; p.height = 1080 }
      else if b[12] != 2 { p.warnings.append("The template uses workspace mode \(b[12]); verify the canvas aspect ratio.") }
    }
    var cursor = 64812
    if b.count > 64825, b.u32(64817) == 136 { cursor = 64813 }
    guard cursor + 12 < b.count else { throw RaceError.invalid("Truncated template preview.") }
    let seed = b.u32(cursor)
    let inputSize = Int(b.u32(cursor + 4))
    let commonSize = Int(b.u32(cursor + 8))
    guard inputSize >= 136, inputSize <= 4096, commonSize >= 168, commonSize <= 4096 else {
      throw RaceError.invalid("Unsupported template record sizes.")
    }
    let key = LegacyCodec.templateKey(seed)
    cursor += 12
    while cursor + inputSize <= b.count && b[cursor] != 255 {
      let d = LegacyCodec.transform(Data(b[cursor..<cursor + inputSize]), key: key)
      guard p.inputs.count < 256 else { throw RaceError.invalid("Too many template inputs.") }
      let type = d[1]
      p.inputs.append(
        MediaInput(
          name: d.utf16(8, 128), path: "", kind: type == 4 ? "data" : type == 2 ? "audio" : "video",
          legacyIndex: Int(d[0])))
      cursor += inputSize
    }
    guard cursor < b.count && b[cursor] == 255 else {
      throw RaceError.invalid("Missing template object delimiter.")
    }
    cursor += 1
    while cursor + 4 <= b.count {
      let idx = Int(b.u32(cursor))
      if idx == Int(UInt32.max) { break }
      guard idx < 10000, cursor + 4 + 128 + commonSize + 12 <= b.count else {
        throw RaceError.invalid("Malformed template object.")
      }
      var label = LegacyCodec.transform(Data(b[cursor + 4..<cursor + 132]), key: key)
      let labelText = label.utf16(0, 128)
      if labelText.unicodeScalars.contains(where: { $0.value < 32 || $0.value >= 0xfffe }) {
        label.putUTF16("Imported Display", 0, 128)
      }
      let meta = LegacyCodec.transform(Data(b[cursor + 132..<cursor + 132 + commonSize]), key: key)
      var combined = label + meta
      if combined.count < 344 { combined.append(Data(repeating: 0, count: 344 - combined.count)) }
      guard validCommon(combined, at: 0, short: !version2) else {
        throw RaceError.invalid("Invalid template display record at byte \(cursor).")
      }
      var o = decodeCommon(combined, at: 0, legacyIndex: idx)
      if !version2 {
        o.visible = true
        o.opacity = 1
      }
      cursor += 132 + commonSize
      let length = Int(b.u32(cursor))
      cursor += 12  // size + 8-byte fingerprint
      guard length <= 4 * 1024 * 1024, cursor + length + (length > 0 ? 8 : 0) <= b.count else {
        throw RaceError.invalid("Invalid template payload length.")
      }
      o.legacyPayload = LegacyCodec.transform(Data(b[cursor..<cursor + length]), key: key)
      inferDetails(&o)
      cursor += length + (length > 0 ? 8 : 0)
      if commonSize >= 200 {
        guard cursor + 4 <= b.count else {
          throw RaceError.invalid("Truncated template image record.")
        }
        let marker = b.u32(cursor)
        cursor += 4
        if marker != 0 {
          // Current containers carry their exact encoded size. Prefer this over
          // scanning for the next name (which fails for Unicode display names).
          var imageCursor = cursor - 4
          if let image = try? LegacyProjectSettings.image(b,cursor:&imageCursor) {
            o.embeddedImage = image; o.artwork = LegacyArtwork.png(image)
            cursor = imageCursor; p.objects.append(o); continue
          }
          // Embedded bitmap containers vary by version. Recover the next bounded record.
          let imageStart = cursor - 4
          let nameMask = LegacyCodec.transform(Data(repeating: 0, count: 128), key: key)
          var next: Int?
          if cursor + 132 + commonSize <= b.count {
            for j in cursor..<(b.count - 132 - commonSize) where b.u32(j) < 10000 {
              guard (b[j + 5] ^ nameMask[1]) == 0, (b[j + 7] ^ nameMask[3]) == 0,
                (b[j + 9] ^ nameMask[5]) == 0
              else { continue }
              let name = LegacyCodec.transform(Data(b[j + 4..<j + 132]), key: key)
              let s = name.utf16(0, 128)
              guard !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 256 })
              else { continue }
              let m = LegacyCodec.transform(Data(b[j + 132..<j + 132 + commonSize]), key: key)
              if validCommon(name + m, at: 0) {
                next = j
                break
              }
            }
          }
          if let n = next {
            o.embeddedImage = Data(b[imageStart..<n])
            cursor = n
          } else {
            let rawImage = Data(b[imageStart..<b.count])
      o.embeddedImage = rawImage == Data(repeating:0,count:4) ? nil : rawImage
            cursor = b.count
          }
          o.artwork = o.embeddedImage.flatMap { LegacyArtwork.png($0) }
          if o.artwork == nil { p.warnings.append("Embedded legacy image for \(o.name) could not be decoded.") }
        }
      }
      p.objects.append(o)
    }
    p.objects.sort { ($0.legacyIndex ?? 0) < ($1.legacyIndex ?? 0) }
    guard !p.objects.isEmpty else {
      throw RaceError.invalid("Template contains no readable display objects.")
    }
    addWarnings(&p)
    return p
  }

  static func style(_ b: Data) throws -> RaceProject {
    let cursor: Int
    if (36...84).contains(Int(b.u32(16))), 20 + Int(b.u32(16)) + 12 <= b.count {
      // Video-position presets omit the thumbnail entirely.
      cursor = 16
    } else if b[3] == 51 {
      let packed = b.u32(16)
      guard packed & 0x8000_0000 != 0 else {
        throw RaceError.invalid("Unsupported RRO3 thumbnail container.")
      }
      cursor = 20 + Int(packed & 0x7fff_ffff)
    } else {
      cursor = 43216
    }
    guard cursor + 4 < b.count else { throw RaceError.invalid("Truncated RRO preview.") }
    let length = Int(b.u32(cursor))
    let key = LegacyCodec.templateKey(b.u32(4), salt: "RaceRender LLC")
    guard length >= 36, length <= 84, cursor + 4 + length + 12 <= b.count else {
      throw RaceError.invalid("Unsupported RRO header size.")
    }
    let meta = LegacyCodec.transform(Data(b[cursor + 4..<cursor + 4 + length]), key: key)
    var common = Data(repeating: 0, count: 344)
    common.putUTF16("Imported Style", 0, 128)
    common.putU32(UInt32.max, 256)
    common.replaceSubrange(260..<260 + length, with: meta)
    for offset in [260, 264] where !common.f32(offset).isFinite || abs(common.f32(offset)) > 1000 {
      common.putFloat(5, offset)
    }
    guard validCommon(common, at: 0) else { throw RaceError.invalid("Invalid RRO display header.") }
    var o = decodeCommon(common, at: 0, legacyIndex: 0)
    o.visible = true
    o.opacity = 1
    let n = Int(b.u32(cursor + 4 + length))
    let start = cursor + 4 + length + 12
    guard n <= 4 * 1024 * 1024, start + n <= b.count else {
      throw RaceError.invalid("Invalid RRO payload.")
    }
    o.legacyPayload = LegacyCodec.transform(Data(b[start..<start + n]), key: key)
    let imageStart = start+n+(n > 0 ? 8 : 0)
    if imageStart < b.count {
      let rawImage = Data(b[imageStart..<b.count])
      o.embeddedImage = rawImage == Data(repeating:0,count:4) ? nil : rawImage
      o.artwork = o.embeddedImage.flatMap { LegacyArtwork.png($0) }
    }
    inferDetails(&o)
    var p = RaceProject()
    p.objects = [o]
    addWarnings(&p)
    return p
  }
}

/// Symmetric byte transform used by rrt1/rrt2, independently implemented for file interoperability.
/// All arithmetic is explicit unsigned wrapping arithmetic, independent of host word size.
public enum LegacyCodec {
  public static func templateKey(_ seed: UInt32, salt saltString: String = "WP RaceRender LLC")
    -> [UInt8]
  {
    let salt = Array(saltString.utf8)
    let n = UInt32(salt.count + 32)
    var out = (0..<32).map { UInt8(truncatingIfNeeded: seed) &+ (salt[$0 % salt.count] ^ 0xaa) }
    var state = Int32(bitPattern: seed)
    var acc = seed &* n
    for i in 0..<32 {
      let t = state < 0 ? UInt32(0x7fff_ffff) &- UInt32(bitPattern: state) : UInt32(state)
      state = Int32(Int16(truncatingIfNeeded: t &* 18000 &+ (t >> 16)))
      out[i] = out[i] &+ UInt8(truncatingIfNeeded: t &* 80 &+ (t >> 16) &+ acc)
      acc = acc &+ n
    }
    return out
  }
  public static func transform(_ b: Data, key: [UInt8]) -> Data {
    guard !key.isEmpty, !b.isEmpty else { return b }
    let n = UInt32(b.count)
    let k = UInt32(key.count)
    let s = key.reduce(UInt32(0)) { $0 + UInt32($1) }
    let mod = max(1, s % (k + 3))
    var state = Int32(s)
    var out = Data(count: b.count)
    for i in 0..<b.count {
      let j = UInt32(i)
      let z = n &+ k &+ j &* (s + 1)
      let q = z / 255
      let den = n &+ k &+ 1 &+ j &* (s + 1) &- q &* 255
      var r: UInt32 = 0
      // A zero remainder in the byte position skips the generator entirely.
      // Advancing it when den == 1 corrupts subsequent bytes until it converges.
      if den != 1 {
        let t = state < 0 ? UInt32(0x7fff_ffff) &- UInt32(bitPattern: state) : UInt32(state)
        let low = (t & 65535) &* 18000 &+ (t >> 16)
        let a = (n &+ k &+ 1 &+ j &* (s + 1) &+ t &- q &* 255) & 65535
        let value = ((t &- a &* 0x6f97_0000 &+ den) & 0xffff_0000) &+ low
        state = Int32(Int16(truncatingIfNeeded: value))
        r = den == 0 ? 0 : value % den
      }
      let v =
        (n &+ k &+ j &* ((s + 1) & 255)) ^ r
        ^ (n &+ k &+ s &+ UInt32(key[i % key.count]) &+ j &* (s + 1) &+ j % mod)
      out[i] = b[i] ^ UInt8(truncatingIfNeeded: v)
    }
    return out
  }
}
