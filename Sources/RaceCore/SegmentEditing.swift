import Foundation

public enum SegmentField: String, CaseIterable, Sendable, Identifiable {
  case colorChannels, visibility, source, position, size, opacity, channel, text, color, range, picture,
    gauge, graph, mapComparison, mapSettings, timerSettings, imageControl, typography, shape, hud, audio, style, artwork
  public var id: String { rawValue }
  public var title: String {
    switch self { case .colorChannels:return "RGB channels"; case .source:return "Data/media source"; case .imageControl:return "Image control"
    case .mapComparison:return "Map comparison"; case .mapSettings:return "Map display"; case .timerSettings:return "Timer settings"; case .typography:return "Text typography"; case .hud:return "HUD parameters"; case .style:return "Style / legacy parameters"
    default:return rawValue.capitalized }
  }
  public static func available(for o: DisplayObject) -> [Self] {
    if o.kind == .group { return [.visibility,.position,.size,.opacity] }
    var fields: [Self] = [.colorChannels,.visibility,.source,.position,.size,.opacity,.channel,.text,.color,.range,.picture,.style,.artwork]
    if [.speed,.rpm,.gauge].contains(o.kind) { fields.append(.gauge) }
    if o.kind == .timer { fields.append(.timerSettings) }
    if o.kind == .map { fields += [.mapComparison,.mapSettings] }
    if o.kind == .graph { fields.append(.graph) }; if o.kind == .image { fields.append(.imageControl) }
    if o.kind == .text { fields.append(.typography) }; if o.kind == .shape { fields.append(.shape) }
    if o.hud != nil || (o.segments ?? []).contains(where: { $0.hud != nil || $0.clearedProperties?.contains(.hud) == true }) { fields.append(.hud) }; if [.video,.audio].contains(o.kind) { fields.append(.audio) }
    return fields
  }
}

extension ObjectSegment {
  public func overrides(_ field: SegmentField) -> Bool {
    let cleared: ObjectSegment.ClearedProperty?
    switch field {
    case .colorChannels:cleared = .colorChannels
    case .picture:cleared = .picture; case .gauge:cleared = .gauge; case .graph:cleared = .graph; case .mapComparison:cleared = .mapComparison; case .mapSettings:cleared = .mapSettings; case .timerSettings:cleared = .timerSettings
    case .imageControl:cleared = .imageControl; case .typography:cleared = .typography
    case .shape:cleared = .shape; case .hud:cleared = .hud; case .audio:cleared = .audio
    default:cleared = nil
    }
    if let cleared, clearedProperties?.contains(cleared) == true { return true }
    switch field {
    case .visibility:return visible != nil; case .source:return inputIndex != nil
    case .position:return x != nil || y != nil; case .size:return width != nil || height != nil
    case .opacity:return opacity != nil; case .channel:return channel != nil; case .text:return text != nil
    case .color:return color != nil; case .range:return minimum != nil || maximum != nil
    case .colorChannels:return colorChannels != nil
    case .picture:return picture != nil; case .gauge:return gauge != nil; case .graph:return graph != nil; case .mapComparison:return mapComparison != nil; case .mapSettings:return mapSettings != nil; case .timerSettings:return timerSettings != nil
    case .imageControl:return imageControl != nil; case .typography:return typography != nil
    case .shape:return shape != nil; case .hud:return hud != nil; case .audio:return audio != nil
    case .style:return style != nil || legacyPayload != nil || legacyType != nil || legacyCommon != nil || !(clearedProperties ?? []).isDisjoint(with:[.legacyType,.legacyCommon,.legacyPayload]); case .artwork:return artwork != nil || embeddedImage != nil
    }
  }
  public mutating func setOverride(_ field: SegmentField, enabled: Bool, value o: DisplayObject) {
    switch field {
    case .visibility:visible = enabled ? o.visible : nil
    case .source:inputIndex = enabled ? o.inputIndex : nil
    case .position:x = enabled ? o.x : nil; y = enabled ? o.y : nil
    case .size:width = enabled ? o.width : nil; height = enabled ? o.height : nil
    case .opacity:opacity = enabled ? o.opacity : nil
    case .channel:channel = enabled ? o.channel : nil
    case .text:text = enabled ? o.text : nil
    case .color:color = enabled ? o.color : nil
    case .range:minimum = enabled ? o.minimum : nil; maximum = enabled ? o.maximum : nil
    case .colorChannels:colorChannels = enabled ? o.colorChannels ?? RGBWriteMask() : nil
    case .picture:picture = enabled ? o.picture ?? PictureSettings() : nil
    case .gauge:gauge = enabled ? o.gauge ?? GaugeSettings() : nil
    case .graph:graph = enabled ? o.graph ?? GraphSettings() : nil
    case .mapComparison:mapComparison = enabled ? o.mapComparison ?? MapComparisonSettings() : nil
    case .mapSettings:mapSettings = enabled ? o.editableMapSettings : nil
    case .timerSettings:timerSettings = enabled ? o.timerSettings ?? TimerSettings() : nil
    case .imageControl:imageControl = enabled ? o.imageControl ?? ImageControlSettings() : nil
    case .typography:typography = enabled ? o.typography ?? TextSettings() : nil
    case .shape:shape = enabled ? o.shape ?? ShapeSettings() : nil
    case .hud:hud = enabled ? o.hud : nil
    case .audio:audio = enabled ? o.audio ?? AudioSettings() : nil
    case .style:
      style = enabled ? o.style : nil; legacyPayload = enabled ? o.legacyPayload : nil
      legacyType = enabled ? o.legacyType : nil; legacyCommon = enabled ? o.legacyCommon : nil
    case .artwork:artwork = enabled ? o.artwork ?? Data() : nil; embeddedImage = enabled ? o.embeddedImage : nil
    }
    let related: [ClearedProperty]
    switch field {
    case .colorChannels:related = [.colorChannels]
    case .picture:related = [.picture]; case .gauge:related = [.gauge]; case .graph:related = [.graph]; case .mapComparison:related = [.mapComparison]; case .mapSettings:related = [.mapSettings]; case .timerSettings:related = [.timerSettings]
    case .imageControl:related = [.imageControl]; case .typography:related = [.typography]
    case .shape:related = [.shape]; case .hud:related = [.hud]; case .audio:related = [.audio]
    case .style:related = [.legacyType,.legacyCommon,.legacyPayload]; default:related = []
    }
    var cleared = clearedProperties ?? []; cleared.subtract(related)
    if enabled, field == .style {
      if o.legacyType == nil { cleared.insert(.legacyType) }; if o.legacyCommon == nil { cleared.insert(.legacyCommon) }
      if o.legacyPayload == nil { cleared.insert(.legacyPayload) }
    }
    clearedProperties = cleared.isEmpty ? nil : cleared
  }
  public var changedFields: [SegmentField] { SegmentField.allCases.filter(overrides) }
}

extension RaceProject {
  /// Re-time a single event, or shift it and all following events on this object.
  /// The operation is transactional; collisions/invalid times leave the scene intact.
  public mutating func retimeSegment(_ objectID: UUID, at time: Double, to destination: Double, following: Bool = false) throws {
    guard let object = objects.first(where: { $0.id == objectID }),
      let selected = object.segments?.first(where: { abs($0.time-time) < 1e-6 }), destination.isFinite, destination >= 0, destination < 1_000_000 else {
      throw RaceError.invalid("Choose a segment and a starting time from 0 to less than 1,000,000 seconds.")
    }
    if abs(destination-selected.time) < 1e-9 { return }
    let moved = (object.segments ?? []).filter { $0.id == selected.id || (following && $0.time >= selected.time) }
    let ids = Set(moved.map(\.id)), delta = destination-selected.time
    let targets = moved.map { $0.time+delta }
    guard targets.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1_000_000 }),
      targets.allSatisfy({ target in !(object.segments ?? []).contains { !ids.contains($0.id) && abs($0.time-target) < 1e-6 } }) else {
      throw RaceError.invalid("This move creates an out-of-range time or overlaps another event. Choose a different starting time.")
    }
    for segment in moved { try validateGroupEventOwnership(objectID,segment:segment) }
    var copy = self
    // Restore saved independent child records before creating the moved group edits.
    for segment in moved.sorted(by: { $0.time > $1.time }) { copy.removeDisplaySegment(objectID,at:segment.time) }
    for segment in moved.sorted(by: { $0.time < $1.time }) {
      var moved = segment; moved.time += delta
      try copy.installSegment(moved,on:objectID)
    }
    self = copy
  }
  public mutating func setSegmentOverride(_ objectID: UUID, at time: Double, field: SegmentField, enabled: Bool) throws {
    guard let i = objects.firstIndex(where: { $0.id == objectID }),
      let j = objects[i].segments?.firstIndex(where: { abs($0.time-time) < 1e-6 }) else { throw RaceError.invalid("Choose a timeline segment.") }
    var copy = self
    let value = displayForEditing(objectID,at:time)!
    var segment = objects[i].segments![j]
    guard segment.overrides(field) != enabled else { return }
    segment.setOverride(field,enabled:enabled,value:value)
    if objects[i].kind == .group, [.position,.size].contains(field) {
      try validateGroupEventOwnership(objectID,segment:objects[i].segments![j])
      copy.removeDisplaySegment(objectID,at:time)
      try copy.installSegment(segment,on:objectID)
    } else { copy.objects[i].segments?[j] = segment }
    self = copy
  }
  public mutating func removeSegmentSafely(_ objectID: UUID, at time: Double) throws {
    guard let segment = objects.first(where: { $0.id == objectID })?.segments?.first(where: { abs($0.time-time)<1e-6 }) else { return }
    try validateGroupEventOwnership(objectID,segment:segment)
    removeDisplaySegment(objectID,at:time)
  }
  public mutating func inheritSegment(_ objectID: UUID, at time: Double) throws {
    guard let i = objects.firstIndex(where: { $0.id == objectID }),
      let old = objects[i].segments?.first(where: { abs($0.time-time) < 1e-6 }) else { return }
    try validateGroupEventOwnership(objectID,segment:old)
    removeDisplaySegment(objectID,at:time)
    var empty = ObjectSegment(time:time); empty.id = old.id
    objects[i].segments = ((objects[i].segments ?? [])+[empty]).sorted { $0.time < $1.time }
  }
  private func validateGroupEventOwnership(_ id: UUID, segment: ObjectSegment) throws {
    guard let object = objects.first(where: { $0.id == id }), object.kind == .group,
      let before = segment.groupChildrenBefore else { return }
    for member in objects where member.kind == .group && ancestors(of:member.id).contains(id) {
      if let event = member.segments?.first(where: { abs($0.time-segment.time) < 1e-6 }),
        event.groupChildrenBefore != nil, !(before[member.id] ?? []).contains(where: { $0.id == event.id }) {
        throw RaceError.invalid("Another nested group was edited at this same time. Move or remove its later event first to preserve those edits.")
      }
    }
  }
  private mutating func installSegment(_ segment: ObjectSegment, on id: UUID) throws {
    guard let i = objects.firstIndex(where: { $0.id == id }) else { return }
    if objects[i].kind == .group, segment.x != nil || segment.y != nil || segment.width != nil || segment.height != nil {
      guard var value = displayForEditing(id,at:segment.time) else { return }
      var fields = segment; fields.groupChildrenBefore = nil; fields.apply(to:&value)
      updateDisplay(value,at:segment.time)
      guard let j = objects[i].segments?.firstIndex(where: { abs($0.time-segment.time) < 1e-6 }) else { return }
      var installed = segment; installed.groupChildrenBefore = objects[i].segments?[j].groupChildrenBefore
      objects[i].segments?[j] = installed
    } else {
      var segment = segment; segment.groupChildrenBefore = nil
      objects[i].segments = ((objects[i].segments ?? [])+[segment]).sorted { $0.time < $1.time }
    }
  }
}
