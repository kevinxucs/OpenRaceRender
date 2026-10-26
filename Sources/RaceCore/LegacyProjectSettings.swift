import Foundation

/// RRP3 records verified with disposable projects saved by RaceRender 3.7.3.
/// Unrecognized record sizes remain on the conservative recovery path.
enum LegacyProjectSettings {
  static func header(_ b: Data, project p: inout RaceProject, sourceStart: Int) {
    p.legacyImportVersion = 2
    guard sourceStart >= 2152, b.count >= 2152 else { return }
    p.notes = b.utf16(48, 2048)
    // Workspace selection is saved in the project; preview/export profiles are
    // separate application preferences. These two modes were verified in RR3.
    if b[2126] == 0 { p.width = 1440; p.height = 1080 }
    else if b[2126] == 2 { p.width = 1920; p.height = 1080 }
    else { p.warnings.append("The RRP uses workspace mode \(b[2126]); verify the canvas aspect ratio before rendering.") }
    p.speedUnit = b[2120] == 2 ? "km/h" : b[2120] == 3 ? "knots" : b[2120] == 4 ? "m/s" : "mph"
    let lengthInput = Int(b[2121])
    if lengthInput != 255, lengthInput < Int(b.u32(16)) { p.lengthInputIndex = lengthInput }
    let duration = b.f32(2096)
    if duration.isFinite, duration > 0, duration < 1_000_000 { p.explicitDuration = duration }
  }

  static func input(_ b: Data, at record: Int, settings: Data, input: inout MediaInput, warnings: inout [String]) {
    let type = b[record + 2176]
    input.isJoinRoot = type == 5 || type == 6 ? true : nil
    if input.isJoinRoot == true { input.kind = type == 6 ? "audio" : "video"; input.path = "" }
    let parent = Int(b[record + 2178])
    if parent != 255 { input.joinedTo = parent }
    var timing = InputTiming()
    let delay = b.f32(record + 2188), end = b.f32(record + 2196), rate = b.f32(record + 2204)
    if delay.isFinite, delay > 0 { timing.projectStart = delay }
    if end.isFinite, end > 0, end < input.duration { timing.trimEnd = end }
    if rate.isFinite, rate > 0, rate <= 100 { timing.rate = rate }
    if b[record + 2209] != 0 { timing.loop = true }
    if timing != InputTiming() { input.timing = timing }
    let track = Int(b.u32(record + 2200))
    if track > 1 { input.legacyTrackIndex = track; warnings.append("Input ‘\(input.name)’ selects data track \(track). Verify the selected session; this logger's multi-track selection may be unsupported.") }
    if type == 4 {
      input.dataSettings = data(settings, warnings: &warnings)
      return
    }
    guard settings.count >= 31 else { return }
    input.volume = Double(settings[0]) / 100
    var audio = AudioSettings(); audio.balance = Double(settings[1]) / 100 - 1
    audio.routing = settings[2] == 1 ? .swap : settings[2] == 2 ? .left : settings[2] == 3 ? .right : settings[2] == 4 ? .mono : .stereo
    if audio != AudioSettings() { input.audio = audio }
    guard type == 1 || input.kind == "video" else { return }
    var picture = input.picture ?? PictureSettings()
    picture.legacyColorInterpretation = true
    let dimensions = b.u32(record + 2180), width = Double(dimensions & 0xffff), height = Double(dimensions >> 16)
    if width > 0, height > 0 {
      picture.left = Double(settings.u32(4)) / width; picture.top = Double(settings.u32(8)) / height
      picture.right = Double(settings.u32(12)) / width; picture.bottom = Double(settings.u32(16)) / height
    }
    let rotation = settings.f32(20)
    if settings.count > 40, settings[40] & 16 != 0, rotation.isFinite { picture.rotation = rotation }
    picture.flipX = settings[24] == 1 || settings[24] == 3
    picture.flipY = settings[24] == 2 || settings[24] == 3
    picture.brightness = Double(settings[25]) / 100; picture.contrast = Double(settings[26]) / 100
    picture.saturation = Double(settings[27]) / 100; picture.sharpness = Double(settings[30]) / 100
    picture.hue = Double(Int16(bitPattern: UInt16(settings[28]) | UInt16(settings[29]) << 8))
    input.picture = picture
    if settings.count > 40, settings[40] & ~UInt8(63) != 0 {
      warnings.append("Input ‘\(input.name)’ has additional picture effects retained in the original RRP data. Check colorize, chroma key, and sphere settings before rendering.")
    }
  }

  static func data(_ b: Data, warnings: inout [String]) -> DataSettings? {
    guard b.count >= 2660 else { return nil }
    var s = DataSettings()
    let fields: [(String, Int)] = [("time",0),("lon",132),("lat",260),("altitude",388),("accuracy",516),("lap",648),("speed",776),("heading",908),("rpm",1040),("gear",1168),("gx",1296),("gy",1424)]
    for (alias, offset) in fields {
      let value = b.utf16(offset, 128)
      if !value.isEmpty, !value.hasPrefix("(") { s.assignments[alias] = value }
    }
    let timeScale = b.f32(128), conversion = b.f32(904)
    if timeScale.isFinite, timeScale > 0 { s.timeUnitsPerSecond = timeScale }
    if conversion.isFinite, conversion != 0 { s.speedMultiplier = conversion }
    s.headingAdjustment = b.f32(1036); s.reverseHeading = b[1593] != 0
    s.ignoreLapTriggers = Int(b[1594]); s.interpolate = b[1595] & 1 != 0
    s.gearAdjustment = Double(Int8(bitPattern: b[2656]))
    if b[1592] & 128 != 0 {
      let longitude = b.f64(1552), latitude = b.f64(1560), heading = b.f32(1584)
      if longitude.isFinite, latitude.isFinite, abs(longitude) <= 180, abs(latitude) <= 90, heading.isFinite {
        var line = FinishLine(latitude: latitude, longitude: longitude, heading: heading)
        let x = abs(b.f64(1568)) * cos(latitude * .pi / 180), y = abs(b.f64(1576))
        let width = hypot(x, y) * 222390
        if width.isFinite, width > 0, width < 10000 { line.width = width }
        line.headingTolerance = b.f32(1588)
        s.finishLine = line
      } else { warnings.append("The RRP start/finish point uses unsupported non-GPS coordinates; recorded laps remain active.") }
    }
    for i in 0..<4 {
      let offset = 1600 + i * 264, source = b.utf16(offset + 128, 128)
      guard !source.isEmpty, source != "(None)" else { continue }
      var f = CalculatedField(); f.name = b.utf16(offset, 128); f.source = source
      f.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 1))!
      let operand = b.f32(offset + 256)
      guard operand.isFinite else { continue }
      switch b[1596 + i] {
      case 0: f.add = operand
      case 1: f.add = -operand
      case 2: f.multiply = operand
      case 3: if operand == 0 { warnings.append("Calculated field ‘\(f.name)’ divides by zero and was omitted."); continue }; f.multiply = 1 / operand
      case 4: f.absolute = true
      case 5: f.multiply = 1.8; f.add = 32
      case 6: f.multiply = 1 / 1.8; f.add = -32 / 1.8
      case 7: f.multiply = 0.6213711922
      case 8: f.multiply = 1.609344
      case 9: f.multiply = 0.1450377377
      case 10: f.multiply = 6.8947572932
      default: warnings.append("Calculated field ‘\(f.name)’ uses an unsupported operation and was omitted."); continue
      }
      s.fields.append(f)
    }
    return s
  }

  static func image(_ b: Data, cursor: inout Int) throws -> Data? {
    guard cursor + 4 <= b.count else { throw RaceError.invalid("Truncated RRP image record.") }
    let value = b.u32(cursor)
    if value == 0 { cursor += 4; return nil }
    let length: Int
    if value & 0x80000000 != 0 { length = 4 + Int(value & 0x7fffffff) }
    else {
      let width = Int((value >> 16) & 0xffff), height = Int(b.u32(cursor + 4) & 0xffff)
      guard value & 0xffff == 8, width > 0, height > 0, width <= 4096, height <= 4096 else { throw RaceError.invalid("Unknown RRP image container.") }
      length = 8 + width * height * 4
    }
    guard length <= 64 * 1024 * 1024, cursor + length <= b.count else { throw RaceError.invalid("Truncated or oversized RRP artwork.") }
    let result = Data(b[cursor..<cursor + length]); cursor += length
    return result
  }

  static func timelines(_ b: Data, cursor: inout Int, recordSize: Int, project p: inout RaceProject) throws {
    let count = p.objects.count
    guard cursor + count * 4 <= b.count else { throw RaceError.invalid("Truncated RRP timeline counts.") }
    let counts = (0..<count).map { Int(b.u32(cursor + $0 * 4)) }; cursor += count * 4
    guard counts.allSatisfy({ $0 <= 10000 }), counts.reduce(0,+) <= 100000, recordSize == 208 else { throw RaceError.invalid("Unsupported RRP timeline records.") }
    for index in p.objects.indices {
      var previous = p.objects[index]
      for _ in 0..<counts[index] {
        guard cursor + 212 <= b.count else { throw RaceError.invalid("Truncated RRP timeline segment.") }
        let time = b.f32(cursor), flags = b.u32(cursor + 4), v = Data(b[cursor + 8..<cursor + 208])
        let size = Int(b.u32(cursor + 208)); cursor += 212
        guard time.isFinite, time >= 0, size <= 4 * 1024 * 1024, cursor + size <= b.count else { throw RaceError.invalid("Invalid RRP timeline segment.") }
        let payload = Data(b[cursor..<cursor+size]); cursor += size
        let artwork = try image(b, cursor: &cursor)
        var segment = ObjectSegment(time: time), value = previous
        if flags & 1 != 0 { value.inputIndex = v[149] == 255 ? -1 : Int(v[149]) }
        if flags & 2 != 0 { value.x = v.f32(128); value.y = v.f32(132) }
        if flags & 4 != 0 { value.width = v.f32(136); value.height = v.f32(140) }
        if flags & 8 != 0 { value.visible = v[144] != 0 }
        if flags & 16 != 0 { if value.picture == nil { value.picture = PictureSettings() }; value.picture?.maintainAspect = v[145] != 0 }
        if flags & 32 != 0 {
          if value.picture == nil { value.picture = PictureSettings() }
          value.picture?.flipX = v[146] == 1 || v[146] == 3; value.picture?.flipY = v[146] == 2 || v[146] == 3
        }
        if flags & 128 != 0 { value.opacity = 1 - Double(v[148]) / 100 }
        if flags & 256 != 0 { value.style = v.utf16(0, 128) }
        if flags & 1024 != 0 { if value.audio == nil { value.audio = AudioSettings() }; value.audio?.volume = Double(v[151]) / 100 }
        if flags & 2048 != 0 { if value.audio == nil { value.audio = AudioSettings() }; value.audio?.balance = Double(v[152]) / 100 - 1 }
        if flags & 4096 != 0, !payload.isEmpty { value.legacyPayload = payload; LegacyReader.inferDetails(&value) }
        if let artwork { value.embeddedImage = artwork; value.artwork = LegacyArtwork.png(artwork) }
        if flags & ~UInt32(0x1DBF) != 0 { p.warnings.append("Timeline segment at \(clockText(time)) for ‘\(value.name)’ includes unsupported color-channel or clipping changes.") }
        var holder = previous; holder.segments = nil; holder.editSegment(at: time, from: previous, to: value)
        if let decoded = holder.segments?.first { segment = decoded }
        p.objects[index].segments = (p.objects[index].segments ?? []) + [segment]
        previous = value
      }
    }
  }
}
