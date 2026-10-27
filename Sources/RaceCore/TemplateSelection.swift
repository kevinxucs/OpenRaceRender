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
    func sources(_ segments: [ObjectSegment], kind: ObjectKind, id: UUID) -> [Int] {
      segments.flatMap { segment in
        segment.inputIndex.map { indexIfUsed($0,kind:kind,id:id) } ?? []
      } + segments.flatMap { segment in
        (segment.groupChildrenBefore ?? [:]).filter { included.contains($0.key) }
          .flatMap { sources($0.value,kind:kinds[$0.key] ?? .group,id:$0.key) }
      }
    }
    return Set(objects.filter { included.contains($0.id) }.flatMap {
      indexIfUsed($0.inputIndex,kind:$0.kind,id:$0.id) + sources($0.segments ?? [],kind:$0.kind,id:$0.id)
    }).intersection(Set(inputs.map(\.legacyIndex)))
  }
}
