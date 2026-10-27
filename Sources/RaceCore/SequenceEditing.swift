import Foundation

/// Private sequence edits keep a logical stream identity while physical clips can move freely.
public struct SequenceDraft: Equatable, Sendable {
  public private(set) var project:RaceProject
  public let original:RaceProject
  public let rootIndex:Int
  public private(set) var originalIDs:[UUID:UUID] = [:]
  public init(project:RaceProject, inputID:UUID) throws {
    original = project; self.project = project
    guard let chosen = project.inputs.first(where:{$0.id == inputID}),
      let index = project.inputs.firstIndex(where:{$0.legacyIndex == (chosen.joinedTo ?? chosen.legacyIndex)}),
      ["video","audio"].contains(project.inputs[index].kind) else { throw RaceError.invalid("Choose a video or audio stream.") }
    rootIndex = project.inputs[index].legacyIndex
    if project.inputs[index].isJoinRoot != true {
      let source = project.inputs[index]
      var root = MediaInput(name:source.name,path:"",kind:source.kind,legacyIndex:rootIndex)
      root.id = source.id; root.isJoinRoot = true
      var timing = InputTiming(); timing.projectStart = source.timing?.projectStart ?? 0; timing.loop = source.timing?.loop
      root.timing = timing == InputTiming() ? nil : timing
      var child = source; child.id = UUID(); child.legacyIndex = (project.inputs.map(\.legacyIndex).max() ?? -1)+1
      child.joinedTo = rootIndex; child.timing?.projectStart = 0; child.timing?.loop = nil
      originalIDs[child.id] = source.id
      self.project.inputs.replaceSubrange(index...index,with:[root,child])
    }
    self.project.refreshSequenceDurations()
  }
  public var clips:[MediaInput] { project.inputs.filter { $0.joinedTo == rootIndex } }
  public mutating func move(_ id:UUID, to position:Int) throws {
    var rows = clips
    guard let index = rows.firstIndex(where:{$0.id == id}), rows.indices.contains(position) else { throw RaceError.invalid("Choose a position within this sequence.") }
    let row = rows.remove(at:index); rows.insert(row,at:position); arrange(rows)
  }
  @discardableResult public mutating func addFiller(after id:UUID?, seconds:Double = 1) throws -> UUID {
    guard seconds.isFinite, seconds > 0 else { throw RaceError.invalid("A time filler needs a positive duration.") }
    var rows = clips
    guard let root = project.inputs.first(where:{$0.legacyIndex == rootIndex}) else { throw RaceError.invalid("Sequence unavailable.") }
    var filler = MediaInput(name:"Time filler",path:"",kind:root.kind,legacyIndex:(project.inputs.map(\.legacyIndex).max() ?? -1)+1)
    filler.joinedTo = rootIndex; filler.isTimeFiller = true; filler.duration = seconds; filler.volume = 0
    let position = id.flatMap { id in rows.firstIndex(where:{$0.id == id}) }.map { $0+1 } ?? rows.count
    rows.insert(filler,at:position); arrange(rows); return filler.id
  }
  public mutating func update(_ input:MediaInput) throws {
    guard let index = project.inputs.firstIndex(where:{$0.id == input.id && $0.joinedTo == rootIndex}),
      input.joinedTo == rootIndex, input.kind == project.inputs[index].kind,
      input.isTimeFiller == project.inputs[index].isTimeFiller else { throw RaceError.invalid("This clip no longer belongs to the sequence.") }
    project.inputs[index] = input; project.refreshSequenceDurations()
  }
  public mutating func removeFiller(_ id:UUID) {
    project.inputs.removeAll { $0.id == id && $0.isTimeFiller == true && $0.joinedTo == rootIndex }
    project.refreshSequenceDurations()
  }
  public func applying(to current:RaceProject) throws -> RaceProject {
    guard current == original else { throw RaceError.invalid("The project changed while this sequence was open. Reopen the sequence to keep those changes.") }
    for clip in clips {
      let t = clip.timing ?? InputTiming()
      guard clip.duration.isFinite, clip.duration > 0, clip.offset.isFinite, t.trimStart.isFinite, t.trimStart >= 0,
        (t.trimEnd ?? clip.duration).isFinite, t.rate.isFinite, t.rate >= 0.01, t.rate <= 100,
        min(clip.duration,t.trimEnd ?? clip.duration) > t.trimStart+max(0,clip.offset) else {
        throw RaceError.invalid("‘\(clip.name)’ needs a positive playable duration and valid trim/rate settings.")
      }
    }
    return project
  }
  private mutating func arrange(_ rows:[MediaInput]) {
    project.inputs.removeAll { $0.joinedTo == rootIndex }
    if let root = project.inputs.firstIndex(where:{$0.legacyIndex == rootIndex}) { project.inputs.insert(contentsOf:rows,at:root+1) }
    project.refreshSequenceDurations()
  }
}

extension RaceProject {
  public mutating func joinInputAfterPrevious(_ id:UUID) throws {
    guard let index = inputs.firstIndex(where:{$0.id == id}), index > 0,
      inputs[index].joinedTo == nil, inputs[index].isTimeFiller != true,
      ["video","audio"].contains(inputs[index].kind), inputs[index-1].kind == inputs[index].kind else {
      throw RaceError.invalid("Choose an independent media input after another compatible stream.")
    }
    let source = inputs[index], parent = inputs[index-1].joinedTo ?? inputs[index-1].legacyIndex
    guard parent != source.legacyIndex else { throw RaceError.invalid("A stream cannot join itself.") }
    if source.isJoinRoot == true {
      let t = source.timing ?? InputTiming()
      guard source.offset == 0, t.trimStart == 0, t.trimEnd == nil, t.rate == 1, t.projectStart == 0, t.loop != true else {
        throw RaceError.invalid("Reset the source stream's overall trim, rate, delay, offset and loop before merging streams. Individual clip settings will be retained.")
      }
    }
    let sources = Set(inputs.filter{$0.legacyIndex == source.legacyIndex || $0.joinedTo == source.legacyIndex}.map(\.legacyIndex))
    if source.isJoinRoot == true { inputs.removeAll{$0.id == id} }
    for i in inputs.indices where sources.contains(inputs[i].legacyIndex) {
      inputs[i].joinedTo = parent
      if source.isJoinRoot != true { inputs[i].timing?.projectStart = 0; inputs[i].timing?.loop = nil }
    }
    objects.removeAll { sources.contains($0.inputIndex) && [.video,.audio].contains($0.kind) }
    for i in objects.indices {
      objects[i].segments = objects[i].segments?.map { $0.remappingSources { sources.contains($0) ? parent : $0 } }
    }
    if let index = lengthInputIndex, sources.contains(index) { lengthInputIndex = parent }
    refreshSequenceDurations()
  }
  public mutating func refreshSequenceDurations() {
    for index in inputs.indices where inputs[index].isJoinRoot == true {
      let root = inputs[index].legacyIndex
      inputs[index].duration = inputs.filter { $0.joinedTo == root }.reduce(0) { sum, clip in
        let t = clip.timing ?? InputTiming(), rate = t.safeRate
        let length = max(0,min(clip.duration,t.trimEnd ?? clip.duration)-max(0,t.trimStart)-max(0,clip.offset))/rate
        return sum+max(0,t.projectStart)+max(0,-clip.offset/rate)+length
      }
    }
  }
  /// Root streams move as a block. Joined members move within their stream, retaining source identities.
  public mutating func moveInput(_ id:UUID, direction:Int) throws {
    guard [-1,1].contains(direction), let input = inputs.first(where:{$0.id == id}) else { throw RaceError.invalid("Choose an input and move direction.") }
    if input.joinedTo != nil {
      var draft = try SequenceDraft(project:self,inputID:id)
      guard let index = draft.clips.firstIndex(where:{$0.id == id}), draft.clips.indices.contains(index+direction) else { return }
      try draft.move(id,to:index+direction); self = try draft.applying(to:self)
    } else {
      let roots = inputs.filter { $0.joinedTo == nil }
      guard let index = roots.firstIndex(where:{$0.id == id}), roots.indices.contains(index+direction) else { return }
      var ordered = roots; ordered.swapAt(index,index+direction)
      let original = inputs
      inputs = ordered.flatMap { root in [root]+original.filter { $0.joinedTo == root.legacyIndex } }
    }
  }
}
