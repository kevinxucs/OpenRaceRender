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
    if let cameraID = inputs[i].cameraVideoID {
      guard let placement = placements.first(where:{$0.input.id == cameraID && $0.contains(projectTime)}),sourceTime >= 0,sourceTime <= inputs[i].duration else {
        throw RaceError.invalid("Choose an event within this camera clip and the camera data range.")
      }
      inputs[i].offset = sourceTime-placement.sourceTime(at:projectTime)
      return
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
    stabilizeHierarchy()
    var layout = layout; layout.stabilizeHierarchy()
    let identities = Dictionary(uniqueKeysWithValues: layout.objects.map { ($0.id, UUID()) })
    if replace {
      let includesVideo = layout.objects.contains { $0.kind == .video }
      // Overlay-only templates keep the cameras/audio and their structural groups.
      // Removing those groups would orphan retained media and lose inherited gates.
      let retained = includesVideo ? Set<UUID>() : layoutObjectIDs(Set(objects.filter {
        [.video, .audio].contains($0.kind)
      }.map(\.id)))
      objects.removeAll { !retained.contains($0.id) }
    }
    for var object in layout.objects {
      func remap(_ index: Int) -> Int {
        let source = layout.inputs.first { $0.legacyIndex == index }
        let kind = source?.kind ?? (object.kind == .video ? "video" : object.kind == .audio ? "audio" : object.kind == .image && !object.imageUsesData ? "image" : "data")
        if let explicit = mapping[index] {
          return inputs.contains { $0.legacyIndex == explicit && $0.kind == kind && $0.joinedTo == nil } ? explicit : -1
        }
        return inputs.first { $0.kind == kind && $0.joinedTo == nil }?.legacyIndex ?? -1
      }
      object.inputIndex = remap(object.inputIndex)
      if let index = object.mapComparison?.referenceInputIndex { object.mapComparison?.referenceInputIndex = remap(index) }
      object.segments = object.segments?.map { segment in
        var segment = segment.remappingGroupSnapshots(identities)
        segment = segment.remappingSources(remap)
        return segment
      }
      object.id = identities[object.id]!
      object.parentID = object.parentID.flatMap { identities[$0] }
      object.legacyOffset = nil; object.legacyIndex = nil
      objects.append(object)
    }
    warnings += layout.warnings.filter { !warnings.contains($0) }
  }
  /// A layout carries artwork and source roles, never session paths, synchronization or export state.
  public func reusableLayout(selected: UUID? = nil) throws -> RaceProject {
    try reusableLayout(objectIDs: selected.map { descendants(of: [$0]) })
  }
  /// Include just these displays and the group containers needed to preserve their state.
  /// Ancestors do not bring along unselected siblings. Names affect only the exported copy.
  public func reusableLayout(objectIDs: Set<UUID>?, objectNames: [UUID: String] = [:], inputNames: [Int: String] = [:]) throws -> RaceProject {
    var p = self
    p.legacyData = nil; p.sourcePath = nil; p.warnings = []
    p.explicitDuration = nil; p.rangeStart = nil; p.rangeEnd = nil
    p.exportSettings = nil; p.lastExport = nil
    p.notes = nil; p.lengthInputIndex = nil; p.legacyImportVersion = nil
    p.stabilizeHierarchy()
    if let objectIDs {
      let ids = p.layoutObjectIDs(objectIDs)
      p.objects = p.objects.filter { ids.contains($0.id) }
    }
    guard !p.objects.isEmpty else { throw RaceError.invalid("Add a display before saving a template.") }
    for i in p.objects.indices {
      if let name = objectNames[p.objects[i].id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { p.objects[i].name = name }
    }
    let used = p.layoutInputIndices(Set(p.objects.map(\.id)))
    p.inputs = p.inputs.filter { used.contains($0.legacyIndex) }
    for i in p.inputs.indices {
      if let name = inputNames[p.inputs[i].legacyIndex]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { p.inputs[i].name = name }
      p.inputs[i].path = ""; p.inputs[i].duration = 0; p.inputs[i].offset = 0
      p.inputs[i].timing = nil; p.inputs[i].joinedTo = nil; p.inputs[i].legacyOffset = nil
      p.inputs[i].dataSession = nil; p.inputs[i].cameraVideoID = nil; p.inputs[i].dataSettings = nil; p.inputs[i].picture = nil; p.inputs[i].volume = 1
      p.inputs[i].audio = nil; p.inputs[i].isJoinRoot = nil; p.inputs[i].isTimeFiller = nil; p.inputs[i].legacyTrackIndex = nil
    }
    let kinds = Dictionary(p.objects.map { ($0.id,$0.kind) }, uniquingKeysWith: { first, _ in first })
    let originals = Dictionary(objects.map { ($0.id,$0) },uniquingKeysWith:{first,_ in first})
    func imagePicture(index: Int, path: String) -> PictureSettings? {
      inputs.first { $0.kind == "image" && !path.isEmpty && $0.path == path }?.picture
    }
    func portable(_ original: ObjectSegment, kind: ObjectKind, id: UUID) throws -> ObjectSegment {
      var segment = original.portableMapComparison()
      if let path = segment.gauge?.backgroundPath {
        segment.gauge?.backgroundImage = try Data(contentsOf:URL(fileURLWithPath:path)); segment.gauge?.backgroundPath = nil
      }
      if kind == .image, let path = segment.text, !path.isEmpty {
        segment.embeddedImage = try Data(contentsOf:URL(fileURLWithPath:path)); segment.text = ""
      }
      if kind == .image, let base = originals[id],
        original.artwork != nil || original.embeddedImage != nil || original.text != nil || original.inputIndex != nil,
        let picture = imagePicture(index:original.inputIndex ?? base.inputIndex,path:original.text ?? base.text) {
        var bytes = segment.artwork ?? segment.embeddedImage ?? base.artwork ?? base.embeddedImage
        if bytes == nil, !(original.text ?? base.text).isEmpty {
          bytes = try Data(contentsOf:URL(fileURLWithPath:original.text ?? base.text))
        }
        if let bytes, !bytes.isEmpty {
          segment.artwork = try PictureProcessor.png(bytes,settings:picture); segment.embeddedImage = nil
        }
      }
      if let snapshots = segment.groupChildrenBefore {
        segment.groupChildrenBefore = try Dictionary(uniqueKeysWithValues:snapshots.compactMap { id, records in
          guard let memberKind = kinds[id] else { return nil }
          return (id,try records.map { try portable($0,kind:memberKind,id:id) })
        })
      }
      return segment
    }
    for i in p.objects.indices {
      p.objects[i].timerSettings?.anchorTime = nil; p.objects[i].timerSettings?.epoch = nil
      p.objects[i].mapSettings?.lapStart = nil
      if p.objects[i].mapSettings?.trace == .lap { p.objects[i].mapSettings?.trace = .all }
      p.objects[i].mapComparison?.primaryLapStart = nil; p.objects[i].mapComparison?.referenceLapStart = nil
      p.objects[i].legacyOffset = nil
      if p.objects[i].kind == .image, p.objects[i].embeddedImage == nil, p.objects[i].artwork == nil, !p.objects[i].text.isEmpty {
        p.objects[i].embeddedImage = try Data(contentsOf: URL(fileURLWithPath: p.objects[i].text))
      }
      if p.objects[i].kind == .image {
        if let base = originals[p.objects[i].id], let picture = imagePicture(index:base.inputIndex,path:base.text),
          let bytes = p.objects[i].artwork ?? p.objects[i].embeddedImage, !bytes.isEmpty {
          p.objects[i].artwork = try PictureProcessor.png(bytes,settings:picture); p.objects[i].embeddedImage = nil
        }
        p.objects[i].text = ""
      }
      if let path = p.objects[i].gauge?.backgroundPath {
        p.objects[i].gauge?.backgroundImage = try Data(contentsOf: URL(fileURLWithPath: path))
        p.objects[i].gauge?.backgroundPath = nil
      }
      let kind = p.objects[i].kind
      p.objects[i].segments = try p.objects[i].segments?.map { try portable($0,kind:kind,id:p.objects[i].id) }
    }
    return p
  }
}
