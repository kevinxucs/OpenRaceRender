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
    func usesSource(_ kind: ObjectKind) -> Bool { ![.group,.shape,.text,.image].contains(kind) }
    func sources(_ segments: [ObjectSegment], kind: ObjectKind) -> [Int] {
      segments.flatMap { segment in
        usesSource(kind) ? segment.inputIndex.map { [$0] } ?? [] : []
      } + segments.flatMap { segment in
        (segment.groupChildrenBefore ?? [:]).filter { included.contains($0.key) }
          .flatMap { sources($0.value,kind:kinds[$0.key] ?? .group) }
      }
    }
    return Set(objects.filter { included.contains($0.id) }.flatMap {
      (usesSource($0.kind) ? [$0.inputIndex] : []) + sources($0.segments ?? [],kind:$0.kind)
    }).intersection(Set(inputs.map(\.legacyIndex)))
  }
}
