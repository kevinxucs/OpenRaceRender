import Foundation

public enum DataDerivationMode:String,Codable,CaseIterable,Sendable {
  case automatic, calculate, recordedOnly
  public var title:String {
    switch self { case .automatic:return "Automatic"; case .calculate:return "Calculate"; case .recordedOnly:return "Recorded only" }
  }
}
public struct FinishLine: Codable, Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var heading: Double
  public var width: Double = 40
  public var minimumLap: Double = 10
  public var headingTolerance: Double?
  public init(latitude: Double, longitude: Double, heading: Double) {
    self.latitude = latitude; self.longitude = longitude; self.heading = heading
  }
}
public struct CalculatedField: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var name = "Calculated"
  public var source = "speed"
  public var multiply: Double = 1
  public var add: Double = 0
  public var absolute: Bool?
  public init() {}
}
public struct DataSettings: Codable, Equatable, Sendable {
  public var assignments: [String: String] = [:]
  public var fields: [CalculatedField] = []
  public var finishLine: FinishLine?
  public var timeUnitsPerSecond: Double?
  public var speedMultiplier: Double?
  public var speedUnit: String?
  public var headingAdjustment: Double?
  public var reverseHeading: Bool?
  public var headingDerivation:DataDerivationMode?
  public var longitudinalDerivation:DataDerivationMode?
  public var lateralDerivation:DataDerivationMode?
  public var gearDerivation:DataDerivationMode?
  public var gearEstimation:GearEstimationSettings?
  public var gearAdjustment: Double?
  public var ignoreLapTriggers: Int?
  public var interpolate: Bool?
  public init() {}
}

extension Telemetry {
  /// Call before publishing the telemetry instance to the renderer.
  public func configure(_ settings: DataSettings) {
    restoreRecordedData()
    interpolationEnabled = settings.interpolate ?? true
    for (alias, header) in settings.assignments where !header.isEmpty {
      if let i = headers.firstIndex(of: header) { aliases[alias] = i }
    }
    if let units = settings.timeUnitsPerSecond, units.isFinite, units > 0, units != 1 {
      if let index = settings.assignments["time"].flatMap({ headers.firstIndex(of: $0) }), let first = columns[index].first {
        let candidate = columns[index].map { ($0 - first) / units }
        if candidate.allSatisfy(\.isFinite), zip(candidate, candidate.dropFirst()).allSatisfy({ $0 <= $1 }) { times = candidate }
      } else { times = times.map { $0 / units } }
      laps = laps.map { var lap = $0; lap.start /= units; lap.end /= units; return lap }
    }
    func transformed(_ alias: String, name: String, operation: (Double) -> Double) {
      guard let index = channelIndex(alias) else { return }
      headers.append(name); columns.append(columns[index].map(operation)); aliases[alias] = headers.count - 1
      provenance[headers.count-1] = provenance[index]
      if circularColumns.contains(index) { circularColumns.insert(headers.count-1) }
      if discreteColumns.contains(index) { discreteColumns.insert(headers.count-1) }
      if discreteColumns.contains(index) { discreteColumns.insert(headers.count - 1) }
    }
    if let multiplier = settings.speedMultiplier, multiplier.isFinite, settings.assignments["speed"] != nil {
      let unit = settings.speedUnit ?? "mph"
      let toMPS = unit == "mph" ? 1 / 2.2369362921 : unit == "km/h" ? 1 / 3.6 : unit == "knots" ? 0.514444 : 1
      transformed("speed", name: "Configured speed (m/s)") { $0 * multiplier * toMPS }
    }
    deriveMotion(settings)
    let headingAdjustment = settings.headingAdjustment.flatMap { $0.isFinite ? $0 : nil } ?? 0
    if settings.reverseHeading == true || headingAdjustment != 0 {
      transformed("heading", name: "Configured heading") { value in
        let adjusted = value * (settings.reverseHeading == true ? -1 : 1) + headingAdjustment
        return (adjusted.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
      }
    }
    deriveGear(settings)
    if let adjustment = settings.gearAdjustment, adjustment.isFinite, adjustment != 0 {
      transformed("gear", name: "Configured gear") { $0 + adjustment }
    }
    for field in settings.fields where !field.name.isEmpty {
      guard let i = channelIndex(field.source), field.multiply.isFinite, field.add.isFinite else { continue }
      headers.append(field.name); columns.append(columns[i].map { (field.absolute == true ? abs($0) : $0)*field.multiply+field.add })
      provenance[headers.count-1] = ChannelProvenance(kind:.calculated,details:"Calculated from \(field.source)")
      if discreteColumns.contains(i) { discreteColumns.insert(headers.count - 1) }
    }
    rebuildMapPoints()
    if let latitude = aliases["lat"], let longitude = aliases["lon"], let line = settings.finishLine {
      laps = detectLaps(line:line,lat:columns[latitude],lon:columns[longitude],ignore:settings.ignoreLapTriggers ?? 0)
    }
  }
  public func finishLine(at time: Double) -> FinishLine? {
    guard let lat = aliases["lat"], let lon = aliases["lon"], count >= 2, time >= 0, time <= duration else { return nil }
    let i = min(index(at: time), count-2), j = min(count-1,i+max(1,count/20000))
    guard columns[lat][i].isFinite, columns[lon][i].isFinite else { return nil }
    let north = columns[lat][j]-columns[lat][i]
    let east = (columns[lon][j]-columns[lon][i])*cos(columns[lat][i] * .pi/180)
    guard abs(north)+abs(east) > 1e-10 else { return nil }
    return FinishLine(latitude: columns[lat][i], longitude: columns[lon][i], heading: atan2(east,north)*180 / .pi)
  }
  private func detectLaps(line: FinishLine, lat: [Double], lon: [Double], ignore: Int = 0) -> [TelemetryLap] {
    let north = cos(line.heading * .pi/180), east = sin(line.heading * .pi/180)
    let factor = cos(line.latitude * .pi/180)
    var crossings: [Double] = []
    for i in 1..<count {
      let y0 = (lat[i-1]-line.latitude)*111195, x0 = (lon[i-1]-line.longitude)*111195*factor
      let y1 = (lat[i]-line.latitude)*111195, x1 = (lon[i]-line.longitude)*111195*factor
      let a = y0*north+x0*east, b = y1*north+x1*east
      guard a.isFinite, b.isFinite, a < 0, b >= 0, b > a else { continue }
      let fraction = -a/(b-a)
      let across = (x0+(x1-x0)*fraction)*north-(y0+(y1-y0)*fraction)*east
      let time = times[i-1]+(times[i]-times[i-1])*fraction
      guard abs(across) <= max(1,line.width)/2, time-(crossings.last ?? -1_000_000) >= max(1,line.minimumLap) else { continue }
      if let tolerance = line.headingTolerance, tolerance.isFinite {
        let heading = atan2(x1-x0, y1-y0) * 180 / .pi
        let difference = abs((heading - line.heading + 540).truncatingRemainder(dividingBy: 360) - 180)
        if difference > max(1, min(180, tolerance)) { continue }
      }
      crossings.append(time)
    }
    let ignored = min(crossings.count, max(0, ignore))
    if ignored > 0 { crossings.removeFirst(ignored) }
    let boundaries = [0.0]+crossings+[duration]
    return (0..<(boundaries.count-1)).map { i in
      TelemetryLap(number: i, start: boundaries[i], end: boundaries[i+1], complete: i > 0 && i < boundaries.count-2)
    }
  }
}
