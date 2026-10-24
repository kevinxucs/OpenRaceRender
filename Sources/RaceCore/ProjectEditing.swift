import Foundation

public struct ExportDestination: Codable, Equatable, Sendable {
  public var path: String
  public var start: Double
  public var duration: Double
  public init(path: String, start: Double, duration: Double) {
    self.path = path; self.start = start; self.duration = duration
  }
}

extension RaceProject {
  /// Marks take precedence over the last custom export span. Never return an inverted range.
  public var defaultExportRange: ClosedRange<Double> {
    let start = rangeStart ?? (rangeEnd == nil ? lastExport?.start : nil) ?? 0
    let end = rangeEnd ?? (rangeStart == nil ? lastExport.map { $0.start + $0.duration } : nil) ?? duration
    let a = max(0, min(duration, start.isFinite ? start : 0))
    let b = max(0, min(duration, end.isFinite ? end : duration))
    return a <= b ? a...b : b...a
  }
  public mutating func markExportStart(at time: Double) {
    rangeStart = max(0, min(duration, time))
    if let end = rangeEnd, end < rangeStart! { rangeEnd = nil }
  }
  public mutating func markExportEnd(at time: Double) {
    rangeEnd = max(0, min(duration, time))
    if let start = rangeStart, start > rangeEnd! { rangeStart = nil }
  }
  public func validateExportRange(start: Double, duration length: Double) throws {
    guard start.isFinite, length.isFinite, start >= 0, length > 0, start < duration,
      start + length <= duration + 0.00001 else {
      throw RaceError.invalid("Choose a positive export range within the project (0–\(clockText(duration))).")
    }
  }
  public mutating func synchronize(inputIndex: Int, sourceTime: Double, projectTime: Double) throws {
    guard let i = inputs.firstIndex(where: { $0.legacyIndex == inputIndex }), inputs[i].joinedTo == nil,
      sourceTime.isFinite, projectTime.isFinite, projectTime >= 0 else {
      throw RaceError.invalid("Select an independent input and a valid event time.")
    }
    let timing = inputs[i].timing ?? InputTiming()
    guard sourceTime >= timing.trimStart, sourceTime <= min(inputs[i].duration, timing.trimEnd ?? inputs[i].duration),
      projectTime >= timing.projectStart else {
      throw RaceError.invalid("The event is outside the source trim range or before its project start. Adjust the trim or project delay first.")
    }
    inputs[i].offset = sourceTime - timing.trimStart - (projectTime - timing.projectStart) * timing.safeRate
  }
  /// Remap sources by type, including per-segment switches. Missing sources remain unassigned.
  public mutating func applyLayout(_ layout: RaceProject, replace: Bool, mapping: [Int: Int] = [:]) {
    if replace {
      let includesVideo = layout.objects.contains { $0.kind == .video }
      objects.removeAll { includesVideo || ![.video, .audio].contains($0.kind) }
    }
    for var object in layout.objects {
      func remap(_ index: Int) -> Int {
        let source = layout.inputs.first { $0.legacyIndex == index }
        let kind = source?.kind ?? (object.kind == .video ? "video" : object.kind == .audio ? "audio" : object.kind == .image ? "image" : "data")
        if let explicit = mapping[index] {
          return inputs.contains { $0.legacyIndex == explicit && $0.kind == kind && $0.joinedTo == nil } ? explicit : -1
        }
        return inputs.first { $0.kind == kind && $0.joinedTo == nil }?.legacyIndex ?? -1
      }
      object.inputIndex = remap(object.inputIndex)
      object.segments = object.segments?.map { segment in
        var segment = segment
        if let index = segment.inputIndex { segment.inputIndex = remap(index) }
        return segment
      }
      object.id = UUID(); object.legacyOffset = nil
      objects.append(object)
    }
    warnings += layout.warnings.filter { !warnings.contains($0) }
  }
  /// A layout carries artwork and source roles, never session paths, synchronization or export state.
  public func reusableLayout(selected: UUID? = nil) throws -> RaceProject {
    var p = self
    p.legacyData = nil; p.sourcePath = nil; p.warnings = []
    p.explicitDuration = nil; p.rangeStart = nil; p.rangeEnd = nil
    p.exportSettings = nil; p.lastExport = nil
    if let selected { p.objects = p.objects.filter { $0.id == selected } }
    guard !p.objects.isEmpty else { throw RaceError.invalid("Add a display before saving a template.") }
    let used = Set(p.objects.flatMap { [$0.inputIndex] + ($0.segments ?? []).compactMap(\.inputIndex) })
    p.inputs = p.inputs.filter { used.contains($0.legacyIndex) }
    for i in p.inputs.indices {
      p.inputs[i].path = ""; p.inputs[i].duration = 0; p.inputs[i].offset = 0
      p.inputs[i].timing = nil; p.inputs[i].joinedTo = nil; p.inputs[i].legacyOffset = nil
      p.inputs[i].dataSettings = nil; p.inputs[i].picture = nil; p.inputs[i].volume = 1
    }
    for i in p.objects.indices {
      p.objects[i].legacyOffset = nil
      if p.objects[i].kind == .image, p.objects[i].embeddedImage == nil, p.objects[i].artwork == nil, !p.objects[i].text.isEmpty {
        p.objects[i].embeddedImage = try Data(contentsOf: URL(fileURLWithPath: p.objects[i].text))
      }
      if p.objects[i].kind == .image { p.objects[i].text = "" }
      if let path = p.objects[i].gauge?.backgroundPath {
        p.objects[i].gauge?.backgroundImage = try Data(contentsOf: URL(fileURLWithPath: path))
        p.objects[i].gauge?.backgroundPath = nil
      }
    }
    return p
  }
}
