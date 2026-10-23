import Foundation

public struct FinishLine: Codable, Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var heading: Double
  public var width: Double = 40
  public var minimumLap: Double = 10
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
  public init() {}
}
public struct DataSettings: Codable, Equatable, Sendable {
  public var assignments: [String: String] = [:]
  public var fields: [CalculatedField] = []
  public var finishLine: FinishLine?
  public init() {}
}

extension Telemetry {
  /// Call before publishing the telemetry instance to the renderer.
  public func configure(_ settings: DataSettings) {
    for (alias, header) in settings.assignments where !header.isEmpty {
      if let i = headers.firstIndex(of: header) { aliases[alias] = i }
    }
    for field in settings.fields where !field.name.isEmpty {
      guard let i = channelIndex(field.source), field.multiply.isFinite, field.add.isFinite else { continue }
      headers.append(field.name); columns.append(columns[i].map { $0*field.multiply+field.add })
    }
    if let latitude = aliases["lat"], let longitude = aliases["lon"] {
      let lat = columns[latitude], lon = columns[longitude]
      let factor = cos((lat.first(where: \.isFinite) ?? 0) * .pi / 180)
      mapPoints = stride(from: 0, to: count, by: max(1,count/4000)).compactMap {
        lat[$0].isFinite && lon[$0].isFinite ? (lon[$0]*factor, lat[$0]) : nil
      }
      if let line = settings.finishLine { laps = detectLaps(line: line, lat: lat, lon: lon) }
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
  private func detectLaps(line: FinishLine, lat: [Double], lon: [Double]) -> [TelemetryLap] {
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
      crossings.append(time)
    }
    let boundaries = [0.0]+crossings+[duration]
    return (0..<(boundaries.count-1)).map { i in
      TelemetryLap(number: i, start: boundaries[i], end: boundaries[i+1], complete: i > 0 && i < boundaries.count-2)
    }
  }
}
