import Foundation

public struct InputTiming: Codable, Equatable, Sendable {
  public var trimStart: Double = 0
  public var trimEnd: Double?
  public var projectStart: Double = 0
  public var rate: Double = 1
  public init() {}
  public var safeRate: Double { rate.isFinite ? max(0.01, min(100, rate)) : 1 }
}

/// Normalized crop fractions. Zero values preserve the original picture.
public struct PictureSettings: Codable, Equatable, Sendable {
  public var left: Double = 0
  public var right: Double = 0
  public var top: Double = 0
  public var bottom: Double = 0
  public var flipX = false
  public var flipY = false
  public var rotation: Double = 0
  public var maintainAspect = true
  public var brightness: Double = 1
  public var contrast: Double = 1
  public var saturation: Double = 1
  public var legacyColorInterpretation: Bool?
  public init() {}
}

/// Each nil property inherits its value from earlier segments, as in RaceRender.
public struct ObjectSegment: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var time: Double
  public var visible: Bool?
  public var inputIndex: Int?
  public var x: Double?
  public var y: Double?
  public var width: Double?
  public var height: Double?
  public var opacity: Double?
  public var text: String?
  public var color: String?
  public var channel: String?
  public init(time: Double) { self.time = time }
  public func apply(to object: inout DisplayObject) {
    if let v = visible { object.visible = v }
    if let v = inputIndex { object.inputIndex = v }
    if let v = x { object.x = v }
    if let v = y { object.y = v }
    if let v = width { object.width = v }
    if let v = height { object.height = v }
    if let v = opacity { object.opacity = v }
    if let v = text { object.text = v }
    if let v = color { object.color = v }
    if let v = channel { object.channel = v }
  }
}

extension DisplayObject {
  public func resolved(at time: Double) -> DisplayObject {
    var result = self
    for segment in (segments ?? []).sorted(by: { $0.time < $1.time }) where segment.time <= time {
      segment.apply(to: &result)
    }
    return result
  }
  /// Record only changed fields, preserving independent inheritance for all other properties.
  public mutating func editSegment(at time: Double, from old: DisplayObject, to value: DisplayObject) {
    var list = segments ?? []
    let i = list.firstIndex { abs($0.time - time) < 0.000001 } ?? list.count
    if i == list.count { list.append(ObjectSegment(time: time)) }
    if old.visible != value.visible { list[i].visible = value.visible }
    if old.inputIndex != value.inputIndex { list[i].inputIndex = value.inputIndex }
    if old.x != value.x { list[i].x = value.x }
    if old.y != value.y { list[i].y = value.y }
    if old.width != value.width { list[i].width = value.width }
    if old.height != value.height { list[i].height = value.height }
    if old.opacity != value.opacity { list[i].opacity = value.opacity }
    if old.text != value.text { list[i].text = value.text }
    if old.color != value.color { list[i].color = value.color }
    if old.channel != value.channel { list[i].channel = value.channel }
    segments = list.sorted { $0.time < $1.time }
  }
}

public struct InputPlacement: Sendable {
  public let input: MediaInput
  public let rootIndex: Int
  public let start: Double
  public let end: Double
  public let sourceStart: Double
  public let rate: Double
  public func sourceTime(at time: Double) -> Double { sourceStart + (time - start) * rate }
  public func projectTime(for source: Double) -> Double { start + (source - sourceStart) / rate }
  public func contains(_ time: Double) -> Bool { time >= start && time < end }
}

extension RaceProject {
  public var placements: [InputPlacement] {
    var result: [InputPlacement] = []
    // A joined stream has one root, followed by its children in input-list order.
    for root in inputs where root.joinedTo == nil {
      let clips = [root] + inputs.filter { $0.joinedTo == root.legacyIndex }
      var cursor = 0.0
      for (position, input) in clips.enumerated() {
        let timing = input.timing ?? InputTiming()
        let rate = timing.safeRate
        let trim = max(0, timing.trimStart)
        let sourceStart = trim + max(0, input.offset)
        let sourceEnd = min(input.duration, timing.trimEnd ?? input.duration)
        let start = (position == 0 ? max(0, timing.projectStart) : cursor) + max(0, -input.offset / rate)
        let end = start + max(0, sourceEnd - sourceStart) / rate
        result.append(InputPlacement(input: input, rootIndex: root.legacyIndex,
          start: start, end: end, sourceStart: sourceStart, rate: rate))
        cursor = end
      }
    }
    return result
  }
  public func media(for index: Int, at time: Double) -> InputPlacement? {
    placements.first { $0.rootIndex == index && $0.contains(time) }
  }
  public func sourceTime(for index: Int, at time: Double) -> Double? {
    media(for: index, at: time)?.sourceTime(at: time)
  }
  public func lapRange(_ laps: [TelemetryLap], inputIndex: Int, first: Int, last: Int) -> ClosedRange<Double>? {
    guard let placement = placements.first(where: { $0.input.legacyIndex == inputIndex }),
      let a = laps.first(where: { $0.number == first }),
      let b = laps.first(where: { $0.number == last }), a.start < b.end else { return nil }
    let start = max(0, placement.projectTime(for: a.start))
    let end = min(duration, placement.projectTime(for: b.end))
    return end > start ? start...end : nil
  }
}
