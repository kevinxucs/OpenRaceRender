import Foundation

public struct GaugeSettings: Codable, Equatable, Sendable {
  public var sweep: Double = 270
  public var rotation: Double = 0
  public var counterClockwise = false
  public var showFace = true
  public var showNumber = true
  public var showLabels = true
  public var divisions: Int = 8
  public var decimals: Int = 0
  public var numberingScale: Double = 1
  public var tickInterval: Double?
  public var label = ""
  public var redline: Double?
  public var warningColor = "#FF616D"
  public var backgroundPath: String?
  public var backgroundImage: Data?
  public init() {}
  public func resolvedLabel(unit: String) -> String {
    label.replacingOccurrences(of: "%su%", with: unit == "mph" ? "MPH" : unit, options: .caseInsensitive)
  }
}
