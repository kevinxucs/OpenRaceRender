import Foundation

public struct MapComparisonSettings:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable { case timeline,lapGhost }
  public var referenceInputIndex:Int = -1
  public var mode:Mode = .timeline
  public var primaryLapStart:Double?
  public var referenceLapStart:Double?
  public var showReferenceTrace = false
  public var referenceColor = "#FFB44D"
  public var showLabels = true
  public init() {}
  public func referenceTime(primary:Telemetry,reference:Telemetry,primaryTime:Double,timelineTime:Double?) -> Double? {
    if mode == .timeline { return timelineTime }
    let current = primaryLapStart.flatMap{start in primary.laps.first{abs($0.start-start) < 1e-6}} ?? (primaryLapStart == nil ? primary.lap(at:primaryTime) : nil)
    let other = referenceLapStart.flatMap{start in reference.laps.first{abs($0.start-start) < 1e-6}} ?? (referenceLapStart == nil ? reference.bestLap : nil)
    guard let current,let other,current.end > current.start,other.end > other.start,
      primaryTime >= current.start,primaryTime < current.end else { return nil }
    // A faster reference remains at the finish rather than restarting or stretching its lap.
    return min(other.end.nextDown,other.start+primaryTime-current.start)
  }
  public func includes(_ time:Double,in data:Telemetry,lapStart:Double?) -> Bool {
    guard let lapStart else { return time >= 0 && time <= data.duration }
    guard let lap = data.laps.first(where:{abs($0.start-lapStart) < 1e-6}) else { return false }
    return time >= lap.start && time < lap.end
  }
}

extension RaceProject {
  /// Same recorded file/settings; independent source clock. No copied displays.
  @discardableResult public mutating func duplicateDataInput(_ id:UUID) throws -> UUID {
    guard let source = inputs.first(where:{$0.id == id}),source.kind == "data",source.joinedTo == nil,source.isJoinRoot != true else { throw RaceError.invalid("Choose an independent data input to duplicate.") }
    var copy = source; copy.id = UUID(); copy.name += " copy"
    copy.legacyIndex = (inputs.map(\.legacyIndex).max() ?? -1)+1
    copy.legacyOffset = nil; copy.dataSession = source.dataSession ?? source.legacyTrackIndex; copy.legacyTrackIndex = nil
    inputs.append(copy); return copy.id
  }
  @discardableResult public mutating func alignDataLaps(primary:SourceSyncAnchor,reference:SourceSyncAnchor) throws -> Double {
    guard let a = inputs.first(where:{$0.id == primary.inputID}),let b = inputs.first(where:{$0.id == reference.inputID}),
      a.kind == "data",b.kind == "data",reference.sourceTime >= (b.timing?.trimStart ?? 0) else { throw RaceError.invalid("Select two independent data inputs and lap starts within their trims.") }
    return try alignSource(reference,to:primary)
  }
}

extension ObjectSegment {
  func portableMapComparison() -> Self {
    var copy = self; copy.timerSettings?.anchorTime = nil; copy.timerSettings?.epoch = nil
    copy.mapSettings?.lapStart = nil
    if copy.mapSettings?.trace == .lap { copy.mapSettings?.trace = .all }; copy.mapComparison?.primaryLapStart = nil; copy.mapComparison?.referenceLapStart = nil
    copy.groupChildrenBefore = copy.groupChildrenBefore?.mapValues{$0.map{$0.portableMapComparison()}}
    return copy
  }
}
