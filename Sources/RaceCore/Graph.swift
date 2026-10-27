import AppKit

/// Plot coordinates use source telemetry time, so synchronization and rate changes
/// affect the cursor in exactly the same way as the other data displays.
public struct GraphSettings: Codable, Equatable, Sendable {
  public enum Axis: String, Codable, CaseIterable, Sendable { case time, distance, channel }
  public enum Mode: String, Codable, CaseIterable, Sendable {
    case moving, centered, fixed, fixedLine, fixedDot, fixedBoth, progress
    public var title: String {
      switch self {
      case .moving: return "Moving history"
      case .centered: return "Centered on current time"
      case .fixed: return "Fixed"
      case .fixedLine: return "Fixed + position line"
      case .fixedDot: return "Fixed + position dot"
      case .fixedBoth: return "Fixed + line and dot"
      case .progress: return "Progress"
      }
    }
    var legacyBits: UInt8 {
      switch self { case .moving: return 0; case .centered: return 12; case .fixed: return 8
      case .fixedLine: return 2; case .fixedDot: return 4; case .fixedBoth: return 6; case .progress: return 10 }
    }
  }
  public var axis: Axis = .time
  public var horizontalChannel = ""
  public var mode: Mode = .moving
  public var timeSpan: Double = 10
  public var timeStart: Double?
  public var timeEnd: Double?
  public var lap: Int?
  public var xMinimum: Double?
  public var xMaximum: Double?
  public var automaticMinimum = false
  public var automaticMaximum = false
  public var connect = true
  public var sortX = false
  public var vertical = false
  public var reverse = false
  public var fill = false
  public var background = true
  public var backgroundColor = "#0D1218"
  public var fillColor = "#5EE0B5"
  public var lineColor = "#5EE0B5"
  public var lineWidth: Double = 2
  public var lineGradient: String?
  public var fillGradient: String?
  public var axes = true
  public var numbers = true
  public var axisColor = "#546274"
  public var numberColor = "#FFFFFF"
  public var axisWidth: Double = 1
  public var interval: Double = 0
  public var numberSize: Double = 12
  public var flipSides = false
  public var trim = true
  public var trimColor = "#546274"
  public var trimWidth: Double = 1
  public var markerColor = "#FFFFFF"
  public var markerSize: Double = 3
  public var label = ""
  public var labelSize: Double = 18
  public var labelColor = "#FFFFFF"
  /// Thicknesses/font sizes scale from this design width.
  public var referenceWidth: Double = 600
  public init() {}
  public var resolvedHorizontalChannel: String { axis == .distance ? "distance" : horizontalChannel }
  public var safeSpan: Double { timeSpan.isFinite && timeSpan > 0 ? max(0.001, min(86400 * 365, timeSpan)) : 10 }

  static func legacy(_ o: DisplayObject) -> GraphSettings? {
    guard let d = o.legacyPayload, d.count >= 456 else { return nil }
    var g = GraphSettings()
    func color(_ i: Int) -> String { String(format: "#%06X", d.u32(i) & 0xffffff) }
    func enabled(_ i: Int) -> Bool { i + 4 <= d.count && d.u32(i) >> 24 != 255 }
    func bound(_ i: Int) -> Double? {
      guard i + 8 <= d.count else { return nil }
      let value = d.f64(i); return value.isFinite && abs(value) < 9e7 ? value : nil
    }
    g.automaticMinimum = bound(256) == nil; g.automaticMaximum = bound(264) == nil
    g.timeSpan = d.f32(272)
    g.mode = Mode.allCases.first { $0.legacyBits == d[429] & 14 } ?? .fixed
    g.reverse = d[429] & 1 != 0; g.vertical = d[429] & 64 != 0
    g.background = enabled(280); g.backgroundColor = color(280)
    g.lineColor = color(288)
    g.markerColor = color(276); g.markerSize = Double(d[428])
    g.numbers = false
    g.trim = enabled(284); g.trimColor = color(284); g.trimWidth = Double(d[430])
    g.lineWidth = Double(d[431]); g.axisColor = color(432); g.axes = enabled(432)
    g.interval = d.f32(436); g.axisWidth = Double(d[440])
    g.label = enabled(292) ? d.utf16(128,128) : ""
    g.labelColor = color(292); g.labelSize = d.f32(424)
    g.timeStart = d.f32(452) >= 0 ? d.f32(448) : nil
    g.timeEnd = d.f32(452) >= 0 ? d.f32(452) : nil
    g.referenceWidth = Double((o.legacyCommon?.u32(296) ?? 600) & 0xffff)
    if g.referenceWidth <= 0 { g.referenceWidth = 600 }
    if d.count >= 472 {
      g.lineGradient = enabled(444) ? color(444) : nil
      g.fill = enabled(456); g.fillColor = color(456)
      g.fillGradient = enabled(460) ? color(460) : nil
      g.numberColor = color(464); g.numbers = enabled(464); g.numberSize = d.f32(468)
    }
    if d.count >= 616 {
      let field = d.utf16(472,128)
      g.horizontalChannel = field.hasPrefix("(") && field.hasSuffix(")") ? String(field.dropFirst().dropLast()) : field
      if !field.isEmpty && field.lowercased() != "(time)" {
        g.axis = g.horizontalChannel.lowercased() == "distance" ? .distance : .channel
      }
      g.xMinimum = bound(600); g.xMaximum = bound(608)
    }
    if d.count >= 620 { g.connect = d[616] & 1 != 0; g.sortX = d[616] & 2 != 0 }
    return g
  }
}

public struct GraphPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var time: Double
  public var beginsPath: Bool
}
public struct GraphPlot: Sendable {
  public var points: [GraphPoint]
  public var xRange: ClosedRange<Double>
  public var yRange: ClosedRange<Double>
  public var cursor: GraphPoint?
  public var message: String?
  public var sampleRange: ClosedRange<Double>
}

/// Cache full fixed plots after extrema-preserving reduction. Moving plots only
/// read their source-time range. The small LRU is invalidated by data transforms.
final class GraphSampleCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [(String, [GraphPoint])] = []
  func samples(key: String, make: () -> [GraphPoint]) -> [GraphPoint] {
    lock.lock(); defer { lock.unlock() }
    if let i = entries.firstIndex(where: { $0.0 == key }) {
      let entry = entries.remove(at: i); entries.append(entry); return entry.1
    }
    let points = make(); entries.append((key,points))
    if entries.count > 4 { entries.removeFirst() }
    return points
  }
}

public enum GraphSampler {
  public static func plot(object o: DisplayObject, data d: Telemetry, time: Double, resolution: Int = 600) -> GraphPlot {
    let g = o.graph ?? GraphSettings()
    func range(_ lo: Double?, _ hi: Double?, fallback: ClosedRange<Double>) -> ClosedRange<Double> {
      let a = lo.flatMap { $0.isFinite ? $0 : nil } ?? fallback.lowerBound
      let b = hi.flatMap { $0.isFinite ? $0 : nil } ?? fallback.upperBound
      return b > a ? a...b : a...(a + max(1,abs(a)*0.01))
    }
    let yBounds = d.bounds(o.resolvedChannel)
    let yr = range(g.automaticMinimum ? yBounds?.0 : o.minimum,
      g.automaticMaximum ? yBounds?.1 : o.maximum, fallback: 0...100)
    let sourceRange: ClosedRange<Double>
    if let lap = g.lap, let l = d.laps.first(where: { $0.number == lap }) { sourceRange = l.start...max(l.start,l.end) }
    else {
      let start = g.timeStart.flatMap { $0.isFinite ? max(0,$0) : nil } ?? 0
      let end = g.timeEnd.flatMap { $0.isFinite ? $0 : nil } ?? d.duration
      sourceRange = start...max(start,end)
    }
    let tr: ClosedRange<Double>
    switch g.mode {
    case .moving: tr = (time-g.safeSpan)...time
    case .centered: tr = (time-g.safeSpan/2)...(time+g.safeSpan/2)
    default: tr = sourceRange
    }
    let xb = g.axis == .time ? (tr.lowerBound,tr.upperBound) : d.bounds(g.resolvedHorizontalChannel) ?? (0,100)
    let xr = range(g.xMinimum, g.xMaximum, fallback: range(xb.0,xb.1,fallback:0...1))
    var result = GraphPlot(points: [],xRange:xr,yRange:yr,cursor:nil,message:nil,sampleRange:tr)
    if let lap = g.lap, !d.laps.contains(where: { $0.number == lap }) { result.message = "Lap unavailable"; return result }
    guard let y = d.channelIndex(o.resolvedChannel) else { result.message = "Y channel unavailable"; return result }
    let x = g.axis == .time ? nil : d.channelIndex(g.resolvedHorizontalChannel)
    guard g.axis == .time || x != nil else { result.message = "X channel unavailable"; return result }
    let from = max(sourceRange.lowerBound,tr.lowerBound), to = min(sourceRange.upperBound,tr.upperBound)
    guard from <= to, to >= 0, from <= d.duration else { return result }
    let lo = max(0,d.index(at:from)), hi = min(d.count-1,d.index(at:to)+1)
    let limit = max(32,min(4096,resolution))
    let key = "\(d.renderRevision):\(y):\(x ?? -1):\(lo):\(hi):\(limit):\(g.sortX)"
    var points = d.graphCache.samples(key:key) {
      var points: [GraphPoint] = []
      let strideSize = max(1,(hi-lo+1)/limit)
      // Keep both extrema in source order for each bucket, retaining narrow peaks.
      for start in stride(from:lo,through:hi,by:strideSize) {
        let end = min(hi,start+strideSize-1)
        var indices = Set([start,end]); var minI = start, maxI = start
        var minV = Double.infinity, maxV = -Double.infinity
        var missing: Int?
        var minX = Double.infinity, maxX = -Double.infinity, minXI = start, maxXI = start
        for i in start...end {
          let v = d.columns[y][i]
          if !v.isFinite || (x != nil && !d.columns[x!][i].isFinite) {
            if missing == nil { missing = i; indices.insert(i) }; continue
          }
          if v < minV { minV = v; minI = i }; if v > maxV { maxV = v; maxI = i }
          if let x { let xv = d.columns[x][i]
            if xv < minX { minX = xv; minXI = i }; if xv > maxX { maxX = xv; maxXI = i }
          }
        }
        indices.insert(minI); indices.insert(maxI)
        if x != nil { indices.insert(minXI); indices.insert(maxXI) }
        for i in indices.sorted() {
          let xv = x.map { d.columns[$0][i] } ?? d.times[i], yv = d.columns[y][i]
          points.append(GraphPoint(x:xv,y:yv,time:d.times[i],beginsPath:false))
        }
      }
      if g.sortX { points.sort {
        if $0.x.isFinite != $1.x.isFinite { return $0.x.isFinite }
        return $0.x == $1.x || !$0.x.isFinite ? $0.time < $1.time : $0.x < $1.x
      } }
      return points
    }
    var gap = true
    points = points.compactMap { p in
      guard p.x.isFinite && p.y.isFinite else { gap = true; return nil }
      guard p.time >= from, p.time <= to, g.mode != .progress || p.time <= time else { gap = true; return nil }
      var p = p; p.beginsPath = gap; gap = false; return p
    }
    result.points = points
    if time >= from, time <= to,
      let yv = d.value(o.resolvedChannel,at:time), yv.isFinite,
      let xv = g.axis == .time ? time : d.value(g.resolvedHorizontalChannel,at:time), xv.isFinite {
      result.cursor = GraphPoint(x:xv,y:yv,time:time,beginsPath:true)
    }
    return result
  }
}
