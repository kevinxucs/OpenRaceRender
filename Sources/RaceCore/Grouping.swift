import Foundation
import CoreGraphics

extension RaceProject {
  public func parentID(of object: DisplayObject) -> UUID? {
    if let id = object.parentID { return objects.first { $0.id == id && $0.kind == .group }?.id }
    guard object.parentIndex >= 0 else { return nil }
    return objects.first { ($0.legacyIndex ?? objects.firstIndex(of: $0)) == object.parentIndex && $0.kind == .group }?.id
  }

  /// Break dependency on source-file indexes before insertion, deletion or template application.
  public mutating func stabilizeHierarchy() {
    let parents = objects.map { parentID(of: $0) }
    for i in objects.indices { objects[i].parentID = parents[i]; objects[i].parentIndex = -1 }
  }

  public func ancestors(of id: UUID) -> [UUID] {
    var result: [UUID] = [], visited: Set<UUID> = [id]
    var current = objects.first { $0.id == id }
    while let object = current, let parent = parentID(of: object), visited.insert(parent).inserted {
      result.append(parent); current = objects.first { $0.id == parent }
    }
    return result
  }
  public func descendants(of ids: Set<UUID>) -> Set<UUID> {
    Set(objects.filter { ids.contains($0.id) || !ids.isDisjoint(with: ancestors(of: $0.id)) }.map(\.id))
  }
  public func selectionRoots(_ ids: Set<UUID>) -> Set<UUID> {
    Set(objects.filter { ids.contains($0.id) && ids.isDisjoint(with: ancestors(of: $0.id)) }.map(\.id))
  }
  public var timelineBoundaries: [Double] {
    Set([0.0] + objects.flatMap { [$0.start, $0.end] + ($0.segments ?? []).map(\.time) }).sorted()
  }

  /// RR3 writes group geometry changes into its children. Their coordinates remain canvas
  /// percentages, including timeline records; applying another parent transform would double them.
  /// Group state still gates the entire subtree, including video and audio.
  public func resolvedObjects(at time: Double) -> [DisplayObject] {
    let local = objects.map { $0.resolved(at: time) }
    let lookup = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let legacy = Dictionary(objects.enumerated().filter { $0.element.kind == .group }
      .map { ($0.element.legacyIndex ?? $0.offset, $0.element.id) }, uniquingKeysWith: { a, _ in a })
    let parents = Dictionary(objects.compactMap { object -> (UUID,UUID)? in
      let parent = object.parentID ?? legacy[object.parentIndex]
      return parent.map { (object.id,$0) }
    }, uniquingKeysWith: { a, _ in a })
    return local.map { object in
      var object = object
      var next = parents[object.id], visited: Set<UUID> = [object.id]
      while let id = next, visited.insert(id).inserted, let parent = lookup[id], parent.kind == .group {
        object.visible = object.visible && parent.visible
        object.start = max(object.start, parent.start); object.end = min(object.end, parent.end)
        object.opacity *= parent.opacity
        next = parents[id]
      }
      return object
    }
  }
  public func selectionBounds(_ ids: Set<UUID>, at time: Double? = nil) -> CGRect? {
    let members = descendants(of: selectionRoots(ids))
    let boxes = objects.filter { members.contains($0.id) && $0.kind != .group }.map { object -> CGRect in
      let o = time.map { object.resolved(at: $0) } ?? object
      return CGRect(x: o.x, y: o.y, width: o.width, height: o.height)
    }
    return boxes.reduce(nil as CGRect?) { accumulated, box in accumulated.map { $0.union(box) } ?? box }
  }
  public func displayForEditing(_ id: UUID, at time: Double? = nil) -> DisplayObject? {
    guard var object = objects.first(where: { $0.id == id }) else { return nil }
    if let time { object = object.resolved(at: time) }
    if object.kind == .group, let bounds = selectionBounds([id], at: time) {
      object.x = bounds.minX; object.y = bounds.minY; object.width = bounds.width; object.height = bounds.height
    }
    return object
  }
  /// One edit operation used by inspector, canvas, alignment and keyboard nudges.
  /// Base geometry edits transform child base values and their explicit future geometry.
  /// Segment edits add child overrides at that instant, preserving later authored overrides.
  public mutating func updateDisplay(_ value: DisplayObject, at time: Double? = nil) {
    var value = value
    guard let i = objects.firstIndex(where: { $0.id == value.id }),
      let old = displayForEditing(value.id, at: time) else { return }
    var savedChildren: [UUID: [ObjectSegment]]?
    if old.kind == .group {
      let changed = old.x != value.x || old.y != value.y || old.width != value.width || old.height != value.height
      if changed {
        let ids = descendants(of: [old.id]).subtracting([old.id])
        if let time {
          savedChildren = objects[i].segments?.first { abs($0.time-time) < 0.000001 }?.groupChildrenBefore
            ?? Dictionary(uniqueKeysWithValues: objects.filter { ids.contains($0.id) }.map {
              ($0.id, ($0.segments ?? []).filter { abs($0.time-time) < 0.000001 })
            })
        }
        let from = CGRect(x: old.x, y: old.y, width: old.width, height: old.height)
        let to = CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
        transformDisplays(ids, from: from, to: to, at: time)
        if time == nil { value.segments = value.segments?.map { $0.transformingGeometry(from:from,to:to) } }
      }
    }
    if let time {
      let base = objects[i].resolved(at: time)
      // Compare group geometry with its computed bounds, not its legacy placeholder frame.
      objects[i].editSegment(at: time, from: old.kind == .group ? old : base, to: value)
      if let savedChildren, let j = objects[i].segments?.firstIndex(where: { abs($0.time-time) < 0.000001 }) {
        objects[i].segments?[j].groupChildrenBefore = savedChildren
      }
      objects[i].name = value.name
    } else { objects[i] = value }
  }
  public mutating func removeDisplaySegment(_ id: UUID, at time: Double) {
    guard let i = objects.firstIndex(where: { $0.id == id }) else { return }
    if objects[i].kind == .group {
      let event = objects[i].segments?.first { abs($0.time-time) < 0.000001 }
      let before = event?.groupChildrenBefore
      let changesGeometry = event?.x != nil || event?.y != nil || event?.width != nil || event?.height != nil
      let members = descendants(of: [id]).subtracting([id])
      for j in objects.indices where members.contains(objects[j].id) {
        if let before {
          guard let saved = before[objects[j].id] else { continue }
          objects[j].segments?.removeAll { abs($0.time-time) < 0.000001 }
          objects[j].segments = ((objects[j].segments ?? []) + saved).sorted { $0.time < $1.time }
        } else if changesGeometry {
          // Imported geometry has no ownership snapshot. Remove its baked geometry,
          // retaining independent text/source/appearance edits at the same instant.
          objects[j].segments = objects[j].segments?.compactMap { segment in
            guard abs(segment.time-time) < 0.000001 else { return segment }
            var segment = segment; segment.x = nil; segment.y = nil; segment.width = nil; segment.height = nil
            return segment.changedFields.isEmpty && segment.groupChildrenBefore == nil ? nil : segment
          }
        }
      }
    }
    objects[i].segments?.removeAll { abs($0.time-time) < 0.000001 }
  }

  public mutating func transformDisplays(_ ids: Set<UUID>, from: CGRect, to: CGRect, at time: Double? = nil) {
    guard from.width > 0, from.height > 0, to.width > 0, to.height > 0,
      [to.minX, to.minY, to.width, to.height].allSatisfy(\.isFinite) else { return }
    let roots = selectionRoots(ids), affected = descendants(of: roots)
    let sx = to.width / from.width, sy = to.height / from.height
    func transform(_ o: inout DisplayObject) {
      o.x = to.minX + (o.x - from.minX) * sx; o.y = to.minY + (o.y - from.minY) * sy
      o.width *= sx; o.height *= sy
    }
    for i in objects.indices where affected.contains(objects[i].id) {
      if let time {
        let old = objects[i].resolved(at: time); var value = old; transform(&value)
        objects[i].editSegment(at: time, from: old, to: value)
      } else {
        transform(&objects[i])
        objects[i].segments = objects[i].segments?.map { $0.transformingGeometry(from:from,to:to) }
      }
    }
  }
  @discardableResult public mutating func groupDisplays(_ ids: Set<UUID>) throws -> UUID {
    stabilizeHierarchy()
    let roots = selectionRoots(ids)
    let members = objects.filter { roots.contains($0.id) }
    guard members.count >= 2 else { throw RaceError.invalid("Select at least two displays to group.") }
    let parent = members[0].parentID
    guard members.allSatisfy({ $0.parentID == parent }) else {
      throw RaceError.invalid("Select displays in the same group, or ungroup them first.")
    }
    let groups = members.filter { $0.kind == .group }
    if groups.count == 1, let existing = groups.first {
      for i in objects.indices where roots.contains(objects[i].id) && objects[i].id != existing.id { objects[i].parentID = existing.id }
      return existing.id
    }
    var group = DisplayObject(name: "Group", kind: .group)
    group.parentID = parent; group.inputIndex = -1
    if let bounds = selectionBounds(roots) { group.x = bounds.minX; group.y = bounds.minY; group.width = bounds.width; group.height = bounds.height }
    for i in objects.indices where roots.contains(objects[i].id) { objects[i].parentID = group.id }
    let insertion = (objects.lastIndex { roots.contains($0.id) } ?? objects.count-1)+1
    objects.insert(group, at: insertion)
    return group.id
  }
  /// Bake inherited visibility/opacity/time gates before removing the group.
  @discardableResult public mutating func ungroupDisplays(_ ids: Set<UUID>) -> Set<UUID> {
    stabilizeHierarchy()
    let groups = Set(objects.filter { ids.contains($0.id) && $0.kind == .group }.map(\.id))
    let old = self
    let boundaries = timelineBoundaries.filter { $0.isFinite && $0 >= 0 && $0 < 1_000_000 }
    var released = Set<UUID>()
    for i in objects.indices where objects[i].parentID.map(groups.contains) == true && !groups.contains(objects[i].id) {
      let id = objects[i].id
      // Only bake removed ancestors; retained ancestors continue to supply their own state.
      let removed = old.ancestors(of: id).filter(groups.contains)
      for time in boundaries {
        var value = old.objects.first { $0.id == id }!.resolved(at: time)
        for parent in old.objects where removed.contains(parent.id) {
          let state = parent.resolved(at: time)
          value.visible = value.visible && state.visible && time >= state.start && time < state.end
          value.opacity *= state.opacity
        }
        if time == 0 { objects[i].visible = value.visible; objects[i].opacity = value.opacity }
        else {
          let before = objects[i].resolved(at: time)
          objects[i].editSegment(at: time, from: before, to: value)
        }
      }
      var parent = objects[i].parentID
      while let p = parent, groups.contains(p) { parent = old.objects.first { $0.id == p }?.parentID }
      objects[i].parentID = parent; released.insert(id)
    }
    objects.removeAll { groups.contains($0.id) }
    return released
  }
  public mutating func deleteDisplays(_ ids: Set<UUID>) {
    stabilizeHierarchy(); let removed = descendants(of: ids); objects.removeAll { removed.contains($0.id) }
  }
  @discardableResult public mutating func duplicateDisplays(_ ids: Set<UUID>) -> Set<UUID> {
    stabilizeHierarchy()
    let roots = selectionRoots(ids), included = descendants(of: roots)
    let copies = objects.filter { included.contains($0.id) }
    let mapping = Dictionary(uniqueKeysWithValues: copies.map { ($0.id, UUID()) })
    var added: [DisplayObject] = []
    for var o in copies {
      o.id = mapping[o.id]!; o.parentID = o.parentID.map { mapping[$0] ?? $0 }
      o.segments = o.segments?.map { $0.remappingGroupSnapshots(mapping, offset:2) }
      o.legacyOffset = nil; o.legacyIndex = nil
      if roots.contains(copies[added.count].id) { o.name += " Copy" }
      o.x += 2; o.y += 2
      for j in (o.segments ?? []).indices {
        if let x = o.segments?[j].x { o.segments?[j].x = x+2 }
        if let y = o.segments?[j].y { o.segments?[j].y = y+2 }
      }
      added.append(o)
    }
    objects += added
    return Set(roots.compactMap { mapping[$0] })
  }
  public mutating func moveDisplays(_ ids: Set<UUID>, direction: Int) {
    stabilizeHierarchy()
    let included = descendants(of: selectionRoots(ids))
    guard !included.isEmpty, direction != 0 else { return }
    let selectedRoots = objects.filter { selectionRoots(ids).contains($0.id) }
    for root in (direction > 0 ? Array(selectedRoots.reversed()) : selectedRoots) {
      let siblings = objects.filter { $0.parentID == root.parentID }
      guard let position = siblings.firstIndex(where: { $0.id == root.id }) else { continue }
      let neighbor = position + (direction > 0 ? 1 : -1)
      guard siblings.indices.contains(neighbor), !included.contains(siblings[neighbor].id) else { continue }
      let movingIDs = descendants(of: [root.id]), neighborIDs = descendants(of: [siblings[neighbor].id])
      let block = objects.filter { movingIDs.contains($0.id) }
      objects.removeAll { movingIDs.contains($0.id) }
      let insertion = direction > 0 ? (objects.lastIndex { neighborIDs.contains($0.id) } ?? objects.count-1)+1
        : objects.firstIndex { neighborIDs.contains($0.id) } ?? 0
      objects.insert(contentsOf: block, at: insertion)
    }
  }
}

extension ObjectSegment {
  func transformingGeometry(from: CGRect, to: CGRect) -> ObjectSegment {
    guard from.width > 0, from.height > 0 else { return self }
    var result = self; let sx = to.width/from.width, sy = to.height/from.height
    if let x { result.x = to.minX+(x-from.minX)*sx }; if let y { result.y = to.minY+(y-from.minY)*sy }
    if let width { result.width = width*sx }; if let height { result.height = height*sy }
    result.groupChildrenBefore = groupChildrenBefore?.mapValues { $0.map { $0.transformingGeometry(from:from,to:to) } }
    return result
  }
  public func remappingSources(_ remap: (Int) -> Int) -> ObjectSegment {
    var result = self
    if let index = inputIndex { result.inputIndex = remap(index) }
    if let index = mapComparison?.referenceInputIndex { result.mapComparison?.referenceInputIndex = remap(index) }
    result.groupChildrenBefore = groupChildrenBefore?.mapValues { $0.map { $0.remappingSources(remap) } }
    return result
  }
  func remappingGroupSnapshots(_ mapping: [UUID:UUID], offset: Double = 0) -> ObjectSegment {
    var result = self
    if let snapshots = groupChildrenBefore {
      result.groupChildrenBefore = Dictionary(uniqueKeysWithValues: snapshots.compactMap { id, segments in
        guard let newID = mapping[id] else { return nil }
        return (newID, segments.map { segment in
          var s = segment.remappingGroupSnapshots(mapping, offset:offset)
          if let x = s.x { s.x = x+offset }; if let y = s.y { s.y = y+offset }
          return s
        })
      })
    }
    return result
  }
}
