import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum TelemetryFormats {
  static func csv(from data: Data, text: String, extension ext: String) throws -> String {
    if ["gpx", "tcx"].contains(ext) || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?xml") {
      let reader = GPSTrackReader()
      let parser = XMLParser(data: data)
      parser.shouldProcessNamespaces = true
      parser.shouldResolveExternalEntities = false
      parser.delegate = reader
      guard parser.parse(), !reader.rows.isEmpty else {
        throw RaceError.invalid("No timestamped GPX/TCX track points found.")
      }
      return reader.csv
    }
    if ext == "vbo" || text.lowercased().contains("[column names]") { return try vbo(text) }
    if ext == "nmea" || text.contains("$GPRMC") || text.contains("$GNRMC") || text.contains("$GPGGA") || text.contains("$GNGGA") || text.contains("$GPGLL") {
      return try nmea(text)
    }
    if ext == "fit" { throw RaceError.invalid("FIT binary telemetry is not supported yet. Export GPX, TCX or CSV from your logger.") }
    return text
  }
  static func vbo(_ text: String) throws -> String {
    var section = "", headers: [String] = [], rows: [[String]] = []
    for raw in text.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("[") { section = line.lowercased(); continue }
      if line.isEmpty { continue }
      if section == "[column names]" { headers += line.split(whereSeparator: \.isWhitespace).map(String.init) }
      if section == "[data]" { rows.append(line.split(whereSeparator: \.isWhitespace).map(String.init)) }
    }
    guard let ti = headers.firstIndex(of: "time"), !rows.isEmpty else { throw RaceError.invalid("VBO needs [column names], time and [data] sections.") }
    for i in headers.indices {
      if headers[i] == "velocity" { headers[i] = "Speed (km/h)" }
      if ["lat", "latitude"].contains(headers[i]) { headers[i] = "Latitude" }
      if ["long", "longitude"].contains(headers[i]) { headers[i] = "Longitude" }
    }
    var previous = 0.0, day = 0.0
    for r in rows.indices {
      guard rows[r].count >= headers.count, let number = Double(rows[r][ti]) else { continue }
      let time = floor(number / 10000) * 3600 + floor(number.truncatingRemainder(dividingBy: 10000) / 100) * 60 + number.truncatingRemainder(dividingBy: 100)
      if time + day < previous - 43200 { day += 86400 }
      previous = time + day
      rows[r][ti] = String(previous)
      for i in headers.indices where ["Latitude", "Longitude"].contains(headers[i]) {
        if let value = Double(rows[r][i]) { rows[r][i] = String((headers[i] == "Longitude" ? -value : value) / 60) }
      }
    }
    return ([headers.joined(separator: ",")] + rows.map { $0.joined(separator: ",") }).joined(separator: "\n")
  }
  static func nmea(_ text: String) throws -> String {
    var samples: [Double: [String: Double]] = [:], day = 0.0, previous = 0.0
    func coordinate(_ value: String, _ direction: String) -> Double? {
      guard let v = Double(value) else { return nil }
      return (floor(v / 100) + v.truncatingRemainder(dividingBy: 100) / 60) * (["S", "W"].contains(direction) ? -1 : 1)
    }
    for raw in text.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard line.hasPrefix("$") else { continue }
      let parts = line.dropFirst().split(separator: "*", omittingEmptySubsequences: false)
      if parts.count > 1 {
        guard let expected = UInt8(parts[1].prefix(2), radix: 16), parts[0].utf8.reduce(UInt8(0), ^) == expected else { continue }
      }
      let c = parts[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard c.count > 6 else { continue }
      let type = String(c[0].suffix(3))
      let field = type == "GLL" ? 5 : 1
      guard c.indices.contains(field), let clock = Double(c[field]) else { continue }
      let seconds = floor(clock / 10000) * 3600 + floor(clock.truncatingRemainder(dividingBy: 10000) / 100) * 60 + clock.truncatingRemainder(dividingBy: 100)
      if seconds + day < previous - 43200 { day += 86400 }
      let t = seconds + day
      previous = t
      var row = samples[t] ?? [:]
      if type == "RMC", c.count >= 9, c[2] == "A" {
        row["Latitude"] = coordinate(c[3], c[4]); row["Longitude"] = coordinate(c[5], c[6])
        if let knots = Double(c[7]) { row["Speed (m/s)"] = knots * 0.514444 }
        row["Heading"] = Double(c[8])
      } else if type == "GGA", c.count >= 10, (Int(c[6]) ?? 0) > 0 {
        row["Latitude"] = coordinate(c[2], c[3]); row["Longitude"] = coordinate(c[4], c[5]); row["Altitude"] = Double(c[9])
      } else if type == "GLL", c.count >= 7, c[6] == "A" {
        row["Latitude"] = coordinate(c[1], c[2]); row["Longitude"] = coordinate(c[3], c[4])
      } else { continue }
      samples[t] = row
    }
    guard !samples.isEmpty else { throw RaceError.invalid("No valid timestamped NMEA fixes found.") }
    let headers = ["Time", "Latitude", "Longitude", "Speed (m/s)", "Heading", "Altitude"]
    return ([headers.joined(separator: ",")] + samples.keys.sorted().map { t in
      ([String(t)] + headers.dropFirst().map { samples[t]?[$0].map { String($0) } ?? "" }).joined(separator: ",")
    }).joined(separator: "\n")
  }
}

private final class GPSTrackReader: NSObject, XMLParserDelegate {
  var rows: [[String: Double]] = []
  var point: [String: Double]?
  var content = ""
  let iso = ISO8601DateFormatter()
  let fractional = ISO8601DateFormatter()
  override init() { super.init(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
    content = ""
    if name.lowercased() == "trkpt" {
      point = [:]; point?["Latitude"] = attributes["lat"].flatMap(Double.init); point?["Longitude"] = attributes["lon"].flatMap(Double.init)
    } else if name.lowercased() == "trackpoint" { point = [:] }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { content += string }
  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
    switch name.lowercased() {
    case "time": point?["Time"] = (fractional.date(from: value) ?? iso.date(from: value))?.timeIntervalSince1970
    case "latitudedegrees": point?["Latitude"] = Double(value)
    case "longitudedegrees": point?["Longitude"] = Double(value)
    case "ele", "altitudemeters": point?["Altitude"] = Double(value)
    case "speed": point?["Speed (m/s)"] = Double(value)
    case "distancemeters": point?["Distance (m)"] = Double(value)
    case "cad", "cadence": point?["Cadence"] = Double(value)
    case "hr", "value": point?["Heart Rate"] = Double(value)
    case "watts": point?["Power"] = Double(value)
    case "trkpt", "trackpoint":
      if let p = point, p["Time"] != nil { rows.append(p) }
      point = nil
    default: break
    }
    content = ""
  }
  var csv: String {
    let headers = ["Time"] + Set(rows.flatMap(\.keys)).subtracting(["Time"]).sorted()
    return ([headers.joined(separator: ",")] + rows.map { row in headers.map { row[$0].map { String($0) } ?? "" }.joined(separator: ",") }).joined(separator: "\n")
  }
}

public struct SyncEvent: Identifiable, Sendable {
  public var id: String { "\(name)-\(time)" }
  public let name: String
  public let time: Double
}

extension Telemetry {
  public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let rad = Double.pi / 180
    let a = pow(sin((lat2-lat1)*rad/2), 2) + cos(lat1*rad)*cos(lat2*rad)*pow(sin((lon2-lon1)*rad/2), 2)
    return 6371000 * 2 * atan2(sqrt(max(0, min(1, a))), sqrt(max(0, 1-a)))
  }
  public var syncEvents: [SyncEvent] {
    var result = laps.prefix(20).map { SyncEvent(name: "Lap \($0.number) start", time: $0.start) }
    var wasStopped = false, wasMoving = false, foundStart = false, foundStop = false
    var gears: Set<Int> = []
    for i in stride(from: 0, to: times.count, by: max(1, times.count / 20000)) {
      let t = times[i]
      if let v = speed(at: t, unit: "m/s") {
        if v < 0.5 { wasStopped = true }
        if v > 2 { wasMoving = true }
        if wasStopped && v > 2 && !foundStart { result.append(SyncEvent(name: "Start moving after a stop", time: t)); foundStart = true }
        if wasMoving && v < 0.5 && !foundStop { result.append(SyncEvent(name: "First stop after moving", time: t)); foundStop = true }
      }
      if let gear = value("gear", at: t, interpolate: false), gear >= 2, gear <= 12 {
        let g = Int(gear)
        if gears.insert(g).inserted { result.append(SyncEvent(name: "First shift into gear \(g)", time: t)) }
      }
    }
    return result.sorted { $0.time < $1.time }
  }
}
