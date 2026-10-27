import Foundation

extension RaceProject {
  /// Group containers are structural dependencies, but their other children are not.
  public func layoutObjectIDs(_ selected: Set<UUID>) -> Set<UUID> {
    let existing = selected.intersection(Set(objects.map(\.id)))
    return existing.union(existing.flatMap { ancestors(of: $0) })
  }

  /// Include source switches and saved group-event edits as well as current assignments.
  public func layoutInputIndices(_ selected: Set<UUID>) -> Set<Int> {
    let included = layoutObjectIDs(selected)
    let kinds = Dictionary(objects.map { ($0.id,$0.kind) }, uniquingKeysWith: { a, _ in a })
    var controlled = Set(objects.filter(\.imageUsesData).map(\.id))
    func inspect(_ segments: [ObjectSegment], id: UUID) {
      for segment in segments {
        if segment.imageControl?.usesData == true { controlled.insert(id) }
        for (child,records) in segment.groupChildrenBefore ?? [:] { inspect(records,id:child) }
      }
    }
    for object in objects { inspect(object.segments ?? [],id:object.id) }
    func usesSource(_ kind: ObjectKind, id: UUID) -> Bool {
      kind == .image ? controlled.contains(id) : ![.group,.shape,.text].contains(kind)
    }
    func indexIfUsed(_ index: Int, kind: ObjectKind, id: UUID) -> [Int] {
      guard usesSource(kind,id:id), kind != .image || inputs.contains(where: { $0.legacyIndex == index && $0.kind == "data" }) else { return [] }
      return [index]
    }
    func sources(_ segments:[ObjectSegment],kind:ObjectKind,id:UUID) -> [Int] {
      var result:[Int] = []
      for segment in segments {
        if let index = segment.inputIndex { result += indexIfUsed(index,kind:kind,id:id) }
        if let comparison = segment.mapComparison { result.append(comparison.referenceInputIndex) }
        for (child,records) in segment.groupChildrenBefore ?? [:] where included.contains(child) {
          result += sources(records,kind:kinds[child] ?? .group,id:child)
        }
      }
      return result
    }
    var used = Set<Int>()
    for object in objects where included.contains(object.id) {
      used.formUnion(indexIfUsed(object.inputIndex,kind:object.kind,id:object.id))
      if let comparison = object.mapComparison { used.insert(comparison.referenceInputIndex) }
      used.formUnion(sources(object.segments ?? [],kind:object.kind,id:object.id))
    }
    return used.intersection(Set(inputs.map(\.legacyIndex)))
  }
}
