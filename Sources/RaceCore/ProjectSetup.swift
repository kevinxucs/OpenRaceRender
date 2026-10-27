import Foundation

extension RaceProject {
  public static let speedUnits = ["mph", "km/h", "m/s", "knots"]
  public var lengthInputs: [MediaInput] {
    inputs.filter { $0.joinedTo == nil && ["video", "audio", "data"].contains($0.kind) }
  }
  /// Choose an independent stream. Its trims, joins, rate and delay continue to determine length.
  public mutating func matchLength(to index: Int?) throws {
    if let index {
      guard lengthInputs.contains(where:{ $0.legacyIndex == index }),
        placements.contains(where:{ $0.rootIndex == index && $0.end > $0.start }) else {
        throw RaceError.invalid("Choose an independent video, audio or data stream with a positive duration.")
      }
    }
    lengthInputIndex = index; explicitDuration = nil
  }
  public mutating func setManualLength(_ seconds: Double) throws {
    guard seconds.isFinite, seconds > 0 else { throw RaceError.invalid("Enter a positive project length in seconds.") }
    explicitDuration = seconds; lengthInputIndex = nil
  }
  public var lengthSummary: String {
    if explicitDuration != nil { return "Manual length" }
    if let index = lengthInputIndex {
      return lengthInputs.first(where:{ $0.legacyIndex == index }).map { "Matches " + $0.name } ?? "Length source unavailable"
    }
    return "Longest input"
  }
}
