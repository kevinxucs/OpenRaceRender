import Foundation

public enum RaceError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    if case .invalid(let s) = self { return s }
    return nil
  }
}

public enum ObjectKind: String, Codable, CaseIterable, Sendable {
  case video, audio, image, speed, rpm, gforce, gear, throttle, brake, lap, timer, delta, bestLap,
    bestTime, map, lights, temperature, text, bar, graph, shape, enhanced, group
  public var title: String {
    switch self {
    case .rpm: return "Tachometer"
    case .gforce: return "G-Force"
    case .bestLap: return "Best Lap"
    case .bestTime: return "Best Time"
    default: return rawValue.capitalized
    }
  }
  public var symbol: String {
    switch self {
    case .video: return "video"
    case .audio: return "speaker.wave.2"
    case .image: return "photo"
    case .map: return "point.topleft.down.to.point.bottomright.curvepath"
    case .speed, .rpm: return "gauge.with.dots.needle.67percent"
    case .timer, .bestTime, .delta: return "stopwatch"
    case .graph: return "waveform.path"
    case .text: return "textformat"
    case .group: return "square.stack.3d.up"
    default: return "chart.bar.xaxis"
    }
  }
}

public struct MediaInput: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var name: String
  public var path: String
  public var kind: String
  public var offset: Double = 0  // source time = project time + offset
  public var duration: Double = 0
  public var volume: Double = 1
  public var legacyIndex: Int = 0
  public var legacyOffset: Int?
  public var timing: InputTiming?
  public var picture: PictureSettings?
  public var joinedTo: Int?
  public var dataSettings: DataSettings?
  public init(name: String, path: String, kind: String, legacyIndex: Int = 0) {
    self.name = name
    self.path = path
    self.kind = kind
    self.legacyIndex = legacyIndex
  }
  public var exists: Bool {
    guard !path.isEmpty else { return false }
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
  }
}

public struct DisplayObject: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var name: String
  public var kind: ObjectKind
  public var style: String = ""
  public var inputIndex: Int = 0
  // RaceRender percentages; origin is lower left. Coordinates can extend beyond canvas.
  public var x: Double = 5
  public var y: Double = 5
  public var width: Double = 18
  public var height: Double = 18
  public var opacity: Double = 1
  public var visible: Bool = true
  public var channel: String = ""
  public var text: String = ""
  public var color: String = "#5EE0B5"
  public var minimum: Double = 0
  public var maximum: Double = 100
  public var start: Double = 0
  public var end: Double = 1_000_000
  public var parentIndex: Int = -1
  public var legacyIndex: Int?
  public var legacyOffset: Int?
  public var legacyType: Int?
  public var legacyActivation: Int?
  public var legacyCommon: Data?
  public var legacyPayload: Data?
  public var embeddedImage: Data?
  public var artwork: Data?
  public var segments: [ObjectSegment]?
  public var picture: PictureSettings?
  public var gauge: GaugeSettings?
  public init(name: String, kind: ObjectKind) {
    self.name = name
    self.kind = kind
  }
}

public struct RaceProject: Codable, Equatable, Sendable {
  public var formatVersion = 1
  public var name: String = "Untitled Session"
  public var width: Int = 1920
  public var height: Int = 1080
  public var fps: Double = 30
  public var speedUnit = "mph"
  public var inputs: [MediaInput] = []
  public var objects: [DisplayObject] = []
  public var warnings: [String] = []
  public var sourcePath: String?
  public var legacyData: Data?
  public var explicitDuration: Double?
  public var rangeStart: Double?
  public var rangeEnd: Double?
  public var exportSettings: ExportSettings?
  public var lastExport: ExportDestination?
  public init() {}
  public var duration: Double {
    if let value = explicitDuration, value.isFinite, value > 0 { return value }
    return max(1, placements.map(\.end).max() ?? 60)
  }
  public static func read(_ url: URL) throws -> RaceProject {
    let ext = url.pathExtension.lowercased()
    if ["rrp", "rrt", "rro"].contains(ext) { return try LegacyReader.read(url) }
    var p = try JSONDecoder().decode(RaceProject.self, from: Data(contentsOf: url))
    guard p.formatVersion == 1, p.width > 0, p.height > 0, p.width <= 16384, p.height <= 16384,
      p.fps.isFinite, p.fps > 0, p.fps <= 240
    else { throw RaceError.invalid("Unsupported or invalid OpenRaceRender project.") }
    let base = url.deletingLastPathComponent()
    for i in p.inputs.indices { p.inputs[i].path = resolvePath(p.inputs[i].path, base: base) }
    for i in p.objects.indices {
      if p.objects[i].kind == .image, !p.objects[i].text.isEmpty { p.objects[i].text = resolvePath(p.objects[i].text, base: base) }
      if let path = p.objects[i].gauge?.backgroundPath { p.objects[i].gauge?.backgroundPath = resolvePath(path, base: base) }
    }
    // Earlier native imports omitted the original camera's picture adjustments.
    if let legacy = p.legacyData,let original = try? LegacyReader.project(legacy,base:base) {
      for i in p.inputs.indices where p.inputs[i].picture == nil && p.inputs[i].kind == "video" {
        guard let offset = p.inputs[i].legacyOffset else { continue }
        p.inputs[i].picture = original.inputs.first { $0.legacyOffset == offset && $0.kind == "video" }?.picture
      }
      for i in p.inputs.indices where p.inputs[i].kind == "video" && p.inputs[i].picture != nil {
        guard let offset = p.inputs[i].legacyOffset,
          let picture = original.inputs.first(where: { $0.legacyOffset == offset && $0.kind == "video" })?.picture else { continue }
        if p.inputs[i].picture?.sharpness == nil { p.inputs[i].picture?.sharpness = picture.sharpness }
        if p.inputs[i].picture?.hue == nil { p.inputs[i].picture?.hue = picture.hue }
      }
    }
    for i in p.objects.indices where p.objects[i].picture == nil && [.video,.image].contains(p.objects[i].kind) {
      guard let common = p.objects[i].legacyCommon,common.count > 285 else { continue }
      var picture = PictureSettings();picture.maintainAspect = common[285] != 0;p.objects[i].picture = picture
    }
    // Older imports mistook legacy Auto (0) for hidden. The marker preserves later native hides.
    for i in p.objects.indices where p.objects[i].legacyActivation == nil {
      guard let common = p.objects[i].legacyCommon,common.count > 284 else { continue }
      p.objects[i].legacyActivation = Int(common[284])
      if common[284] == 0 { p.objects[i].visible = true }
      if p.objects[i].legacyType == 50,p.objects[i].channel.isEmpty,let payload = p.objects[i].legacyPayload {
        let channel = payload.utf16(0,128)
        p.objects[i].channel = channel.hasPrefix("(") && channel.hasSuffix(")") ? String(channel.dropFirst().dropLast()) : channel
      }
    }
    p.warnings = p.warnings.map { $0.replacingOccurrences(of:"persistent script state is not yet reproduced.",with:"persistent state is replayed from the display start.") }
    return p
  }
  public func save(_ url: URL) throws {
    var p = self
    let base = url.deletingLastPathComponent().path + "/"
    for i in p.inputs.indices where p.inputs[i].path.hasPrefix(base) {
      p.inputs[i].path = String(p.inputs[i].path.dropFirst(base.count))
    }
    for i in p.objects.indices {
      if p.objects[i].kind == .image, p.objects[i].text.hasPrefix(base) { p.objects[i].text = String(p.objects[i].text.dropFirst(base.count)) }
      if let path = p.objects[i].gauge?.backgroundPath, path.hasPrefix(base) { p.objects[i].gauge?.backgroundPath = String(path.dropFirst(base.count)) }
    }
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    try e.encode(p).write(to: url, options: .atomic)
  }
  public static func resolvePath(_ path: String, base: URL) -> String {
    if path.isEmpty { return "" }
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let absolute = normalized.hasPrefix("/")
    if absolute && FileManager.default.fileExists(atPath: normalized) { return normalized }
    let relative = base.appendingPathComponent(normalized).standardized.path
    if FileManager.default.fileExists(atPath: relative) { return relative }
    let sibling = base.appendingPathComponent((normalized as NSString).lastPathComponent).path
    return FileManager.default.fileExists(atPath: sibling) ? sibling : (absolute ? normalized : relative)
  }
  public func patchLegacy() throws -> Data {
    guard var b = legacyData, String(data: b.prefix(4), encoding: .ascii) == "RRP3" else {
      throw RaceError.invalid(
        "This project has no original RRP3 data. Save as an .orrp project instead.")
    }
    guard objects.count == Int(b.u32(32)), objects.allSatisfy({ $0.legacyOffset != nil }),
      Set(objects.compactMap(\.legacyOffset)).count == objects.count
    else {
      throw RaceError.invalid(
        "RRP export supports editing original objects. Added or deleted objects require .orrp format."
      )
    }
    guard inputs.count == Int(b.u32(16)), inputs.allSatisfy({ $0.legacyOffset != nil }) else {
      throw RaceError.invalid("Input changes require .orrp format.")
    }
    guard explicitDuration == nil, exportSettings == nil,
      inputs.allSatisfy({ $0.timing == nil && $0.joinedTo == nil && $0.dataSettings == nil }),
      objects.allSatisfy({ ($0.segments ?? []).isEmpty }) else {
      throw RaceError.invalid("Timeline, trim, joining and picture edits require .orrp format.")
    }
    let original = try LegacyReader.project(
      b, base: URL(fileURLWithPath: sourcePath ?? "/").deletingLastPathComponent())
    guard rangeStart == original.rangeStart, rangeEnd == original.rangeEnd else {
      throw RaceError.invalid("Changed output markers require .orrp format. Unchanged imported markers are preserved in RRP copies.")
    }
    guard objects.map(\.legacyOffset) == original.objects.map(\.legacyOffset) else {
      throw RaceError.invalid("Changing layer order requires .orrp format.")
    }
    for (o, old) in zip(objects, original.objects) {
      if !o.visible && old.visible {
        throw RaceError.invalid("Hiding a legacy display requires native .orrp format; the original activation bytes are preserved by compatible RRP export.")
      }
      guard o.kind == old.kind, o.style == old.style, o.channel == old.channel, o.text == old.text,
        o.color == old.color, o.minimum == old.minimum, o.maximum == old.maximum,
        o.start == old.start, o.end == old.end, o.gauge == old.gauge, o.artwork == old.artwork,o.picture == old.picture
      else {
        throw RaceError.invalid(
          "RRP copy export supports labels, visibility, opacity, geometry and synchronization. Save other edits in .orrp format."
        )
      }
    }
    for (input, old) in zip(inputs, original.inputs)
    where input.volume != old.volume || input.kind != old.kind || input.picture != old.picture {
      throw RaceError.invalid("Audio, picture or input-type changes require .orrp format.")
    }
    // Preserve opaque data, scripts and original ordering byte for byte.
    for (o,old) in zip(objects,original.objects) {
      let p = o.legacyOffset!
      b.putUTF16(o.name, p, 128)
      b.putFloat(o.x, p + 260)
      b.putFloat(o.y, p + 264)
      b.putFloat(o.width, p + 268)
      b.putFloat(o.height, p + 272)
      if o.visible != old.visible {
        b[p + 284] = 1
      }
      b[p + 293] = UInt8(max(0, min(100, o.opacity * 100)))
      b[p + 282] = o.inputIndex < 0 ? 255 : UInt8(clamping: o.inputIndex)
    }
    for input in inputs {
      let p = input.legacyOffset!
      b.putUTF16(input.name, p, 128)
      b.putUTF16(input.path, p + 128, 2048)
      b.putFloat(input.offset, p + 2192)
    }
    return b
  }
}

extension Data {
  func u32(_ p: Int) -> UInt32 {
    guard p >= 0, p + 4 <= count else { return 0 }
    return UInt32(self[p]) | UInt32(self[p + 1]) << 8 | UInt32(self[p + 2]) << 16 | UInt32(
      self[p + 3]) << 24
  }
  func f32(_ p: Int) -> Double { Double(Float(bitPattern: u32(p))) }
  func f64(_ p: Int) -> Double {
    Double(bitPattern: UInt64(u32(p)) | UInt64(u32(p + 4)) << 32)
  }
  func utf16(_ p: Int, _ size: Int) -> String {
    guard p >= 0, size >= 0, p + size <= count else { return "" }
    var words: [UInt16] = []
    for j in stride(from: p, to: p + size - 1, by: 2) {
      let c = UInt16(self[j]) | UInt16(self[j + 1]) << 8
      if c == 0 { break }
      words.append(c)
    }
    return String(decoding: words, as: UTF16.self)
  }
  mutating func putFloat(_ x: Double, _ p: Int) { putU32(Float(x).bitPattern, p) }
  mutating func putU32(_ x: UInt32, _ p: Int) {
    guard p >= 0, p + 4 <= count else { return }
    for i in 0..<4 { self[p + i] = UInt8(truncatingIfNeeded: x >> (8 * i)) }
  }
  mutating func putUTF16(_ s: String, _ p: Int, _ length: Int) {
    guard p >= 0, p + length <= count else { return }
    replaceSubrange(p..<p + length, with: Data(repeating: 0, count: length))
    for (i, c) in s.utf16.prefix(length / 2 - 1).enumerated() {
      self[p + 2 * i] = UInt8(truncatingIfNeeded: c)
      self[p + 2 * i + 1] = UInt8(truncatingIfNeeded: c >> 8)
    }
  }
}

public func clockText(_ seconds: Double) -> String {
  guard seconds.isFinite else { return "--:--.---" }
  let rounded = (max(0, seconds) * 1000).rounded()
  guard rounded < Double(Int.max) else { return "--:--.---" }
  let ms = Int(rounded)
  return String(format: "%02d:%02d.%03d", ms / 60000, (ms / 1000) % 60, ms % 1000)
}
