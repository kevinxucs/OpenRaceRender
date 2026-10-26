import Foundation

public struct AudioSettings: Codable, Equatable, Sendable {
  public enum Routing: String, Codable, CaseIterable, Sendable { case stereo, swap, left, right, mono }
  public var volume: Double = 1
  public var balance: Double = 0
  public var routing: Routing = .stereo
  public init() {}
}
