import Foundation

public struct SourceSyncAnchor: Equatable, Sendable {
  public var inputID: UUID
  public var sourceTime: Double
  public init(_ id:UUID, at time:Double) { inputID = id; sourceTime = time }
}

extension RaceProject {
  /// Use the first active occurrence when a reference stream loops.
  public func projectTime(for anchor:SourceSyncAnchor) throws -> Double {
    guard anchor.sourceTime.isFinite, inputs.contains(where:{$0.id == anchor.inputID && $0.isTimeFiller != true}),
      let placement = placements.first(where:{
        $0.input.id == anchor.inputID && anchor.sourceTime >= $0.sourceStart &&
        anchor.sourceTime < $0.sourceTime(at:$0.end)
      }) else { throw RaceError.invalid("Choose a reference frame within its active source trim and synchronization bounds.") }
    return placement.projectTime(for:anchor.sourceTime)
  }
  /// Align physical-source events, preserving reference timing, target trim/delay and export marks.
  @discardableResult public mutating func alignSource(_ target:SourceSyncAnchor, to reference:SourceSyncAnchor,
    rate:Double? = nil) throws -> Double {
    guard target.inputID != reference.inputID,
      let index = inputs.firstIndex(where:{$0.id == target.inputID}),
      inputs[index].joinedTo == nil, inputs[index].isJoinRoot != true,
      ["video","audio","data"].contains(inputs[index].kind),
      target.sourceTime.isFinite, target.sourceTime < inputs[index].duration,
      target.sourceTime < (inputs[index].timing?.trimEnd ?? inputs[index].duration) else {
      throw RaceError.invalid("Choose a different independent target input and a frame before its end. Joined targets must be synchronized through their stream timing.")
    }
    if inputs[index].cameraVideoID != nil,rate != nil {throw RaceError.invalid("Embedded data follows its camera’s playback rate. Adjust the camera rate or synchronize with an offset only.")}
    if let rate, !rate.isFinite || rate < 0.01 || rate > 100 { throw RaceError.invalid("Playback rate must be between 0.01 and 100.") }
    let time = try projectTime(for:reference)
    guard !placements.contains(where:{$0.input.id == reference.inputID && $0.rootIndex == inputs[index].legacyIndex}) else {
      throw RaceError.invalid("The reference and target must belong to different streams; changing this target would also move the reference.")
    }
    var updated = self
    if let rate, rate != (updated.inputs[index].timing?.safeRate ?? 1) {
      var timing = updated.inputs[index].timing ?? InputTiming(); timing.rate = rate; updated.inputs[index].timing = timing
    }
    try updated.synchronize(inputIndex:updated.inputs[index].legacyIndex,sourceTime:target.sourceTime,projectTime:time)
    self = updated
    return time
  }
}
