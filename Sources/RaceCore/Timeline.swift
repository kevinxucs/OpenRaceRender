import Foundation

public struct InputTiming: Codable, Equatable, Sendable {
  public var trimStart: Double = 0
  public var trimEnd: Double?
  public var projectStart: Double = 0
  public var rate: Double = 1
  public var loop: Bool?
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
  // Optional so native projects saved before sharpness support remain readable.
  public var sharpness: Double?
  public var hue: Double?
  public var legacyColorInterpretation: Bool?
  public init() {}

  // Keep the existing on-disk multipliers, but expose familiar signed controls.
  public static func adjustment(from factor: Double) -> Double {
    factor.isFinite ? max(-100, min(100, (factor - 1) * 100)) : 0
  }
  public static func factor(from adjustment: Double) -> Double {
    adjustment.isFinite ? 1 + max(-100, min(100, adjustment)) / 100 : 1
  }
  public var brightnessAdjustment: Double {
    get { Self.adjustment(from: brightness) }
    set { brightness = Self.factor(from: newValue) }
  }
  public var contrastAdjustment: Double {
    get { Self.adjustment(from: contrast) }
    set { contrast = Self.factor(from: newValue) }
  }
  public var saturationAdjustment: Double {
    get { Self.adjustment(from: saturation) }
    set { saturation = Self.factor(from: newValue) }
  }
  public var sharpnessAdjustment: Double {
    get { Self.adjustment(from: sharpness ?? 1) }
    set { sharpness = Self.factor(from: newValue) }
  }
  public var hueAdjustment: Double {
    get { (hue ?? 0).isFinite ? max(-180, min(180, hue ?? 0)) : 0 }
    set { hue = newValue.isFinite ? max(-180, min(180, newValue)) : 0 }
  }
}

/// Each nil property inherits its value from earlier segments, as in RaceRender.
public struct ObjectSegment: Identifiable, Codable, Equatable, Sendable {
  public enum ClearedProperty: String, Codable, Hashable, Sendable {
    case picture, gauge, graph, imageControl, typography, shape, hud, audio, legacyType, legacyCommon, legacyPayload
  }
  public var clearedProperties: Set<ClearedProperty>?
  public var legacyType: Int?
  public var legacyCommon: Data?
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
  public var picture: PictureSettings?
  public var gauge: GaugeSettings?
  public var graph: GraphSettings?
  public var imageControl: ImageControlSettings?
  public var typography: TextSettings?
  public var shape: ShapeSettings?
  public var hud: HUDSettings?
  public var audio: AudioSettings?
  public var legacyPayload: Data?
  public var style: String?
  public var minimum: Double?
  public var maximum: Double?
  public var artwork: Data?
  public var embeddedImage: Data?
  /// Undo a group event independently of a member's pre-existing event at the same time.
  public var groupChildrenBefore: [UUID: [ObjectSegment]]?
  public init(time: Double) { self.time = time }
  public func apply(to object: inout DisplayObject) {
    for property in clearedProperties ?? [] {
      switch property {
      case .picture: object.picture = nil; case .gauge: object.gauge = nil; case .graph: object.graph = nil
      case .imageControl: object.imageControl = nil; case .typography: object.typography = nil
      case .shape: object.shape = nil; case .hud: object.hud = nil; case .audio: object.audio = nil
      case .legacyType: object.legacyType = nil; case .legacyCommon: object.legacyCommon = nil
      case .legacyPayload: object.legacyPayload = nil
      }
    }
    if let legacyType { object.legacyType = legacyType }; if let legacyCommon { object.legacyCommon = legacyCommon }
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
    if let v = picture { object.picture = v }
    if let v = gauge { object.gauge = v }
    if let v = graph { object.graph = v }
    if let v = imageControl { object.imageControl = v }
    if let v = typography { object.typography = v }
    if let v = shape { object.shape = v }
    if let v = hud { object.hud = v }
    if let v = audio { object.audio = v }
    if let v = legacyPayload { object.legacyPayload = v }
    if let v = style { object.style = v }
    if let v = minimum { object.minimum = v }
    if let v = maximum { object.maximum = v }
    if let v = artwork { object.artwork = v }
    if let v = embeddedImage { object.embeddedImage = v }
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
    func parameter<T: Equatable>(_ property: ObjectSegment.ClearedProperty, _ path: WritableKeyPath<ObjectSegment,T?>, _ before: T?, _ after: T?) {
      guard before != after else { return }
      list[i][keyPath:path] = after
      var cleared = list[i].clearedProperties ?? []
      if after == nil { cleared.insert(property) } else { cleared.remove(property) }
      list[i].clearedProperties = cleared.isEmpty ? nil : cleared
    }
    parameter(.picture,\.picture,old.picture,value.picture)
    parameter(.gauge,\.gauge,old.gauge,value.gauge)
    parameter(.graph,\.graph,old.graph,value.graph)
    parameter(.imageControl,\.imageControl,old.imageControl,value.imageControl)
    parameter(.typography,\.typography,old.typography,value.typography)
    parameter(.shape,\.shape,old.shape,value.shape)
    parameter(.hud,\.hud,old.hud,value.hud)
    parameter(.audio,\.audio,old.audio,value.audio)
    parameter(.legacyType,\.legacyType,old.legacyType,value.legacyType)
    parameter(.legacyCommon,\.legacyCommon,old.legacyCommon,value.legacyCommon)
    parameter(.legacyPayload,\.legacyPayload,old.legacyPayload,value.legacyPayload)
    if old.style != value.style { list[i].style = value.style }
    if old.minimum != value.minimum { list[i].minimum = value.minimum }
    if old.maximum != value.maximum { list[i].maximum = value.maximum }
    if old.artwork != value.artwork { list[i].artwork = value.artwork }
    if old.embeddedImage != value.embeddedImage { list[i].embeddedImage = value.embeddedImage }
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
      let clips = (root.isJoinRoot == true ? [] : [root]) + inputs.filter { $0.joinedTo == root.legacyIndex }
      var cursor = 0.0
      for (position, input) in clips.enumerated() {
        let timing = input.timing ?? InputTiming()
        let rate = timing.safeRate
        let trim = max(0, timing.trimStart)
        let sourceStart = trim + max(0, input.offset)
        let sourceEnd = min(input.duration, timing.trimEnd ?? input.duration)
        let base = position == 0 ? 0 : cursor
        let delay = root.isJoinRoot == true || position == 0 ? max(0,timing.projectStart) : 0
        let start = base + delay + max(0, -input.offset / rate)
        let end = start + max(0, sourceEnd - sourceStart) / rate
        if root.isJoinRoot == true {
          let t = root.timing ?? InputTiming(), rootRate = t.safeRate
          let cutStart = max(0, t.trimStart + root.offset), cutEnd = t.trimEnd ?? root.duration
          let a = max(start, cutStart), b = min(end, cutEnd)
          if b > a {
            result.append(InputPlacement(input: input, rootIndex: root.legacyIndex,
              start: max(0, t.projectStart) + max(0, -root.offset / rootRate) + (a - cutStart) / rootRate,
              end: max(0, t.projectStart) + max(0, -root.offset / rootRate) + (b - cutStart) / rootRate,
              sourceStart: sourceStart + (a - start) * rate, rate: rate * rootRate))
          }
        } else {
          result.append(InputPlacement(input: input, rootIndex: root.legacyIndex,
            start: start, end: end, sourceStart: sourceStart, rate: rate))
        }
        cursor = end
      }
    }
    let bound = lengthInputIndex.flatMap { index in result.filter { $0.rootIndex == index }.map(\.end).max() }
    let requested = explicitDuration ?? bound ?? result.map(\.end).max() ?? 0
    let limit = requested.isFinite ? max(0, requested) : 0
    let firstPass = result
    for root in inputs where root.joinedTo == nil && root.timing?.loop == true {
      let clips = firstPass.filter { $0.rootIndex == root.legacyIndex }
      guard let start = clips.map(\.start).min(), let end = clips.map(\.end).max(), end > start else { continue }
      let length = end - start
      let repeats = Int(min(10000, max(0, ceil((limit - end) / length))))
      if repeats > 0 {
        for repeatIndex in 1...repeats {
          let shift = Double(repeatIndex) * length
          for clip in clips where clip.start + shift < limit {
            result.append(InputPlacement(input: clip.input, rootIndex: clip.rootIndex,
              start: clip.start + shift, end: min(limit, clip.end + shift), sourceStart: clip.sourceStart, rate: clip.rate))
          }
        }
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
