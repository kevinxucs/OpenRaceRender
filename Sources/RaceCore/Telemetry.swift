import Foundation

public struct TelemetryLap: Identifiable, Sendable {
  public var id: Int { number }
  public var number: Int
  public var start: Double
  public var end: Double
  public var complete: Bool
  public var duration: Double { end - start }
}

public final class Telemetry: @unchecked Sendable {
  public internal(set) var headers: [String]
  public let times: [Double]
  public internal(set) var columns: [[Double]]
  public let title: String
  public internal(set) var laps: [TelemetryLap]
  public internal(set) var aliases: [String: Int]
  public internal(set) var mapPoints: [(Double, Double)]
  public var duration: Double { times.last ?? 0 }
  public var count: Int { times.count }
  public var bestLap: TelemetryLap? {
    laps.filter(\.complete).filter { $0.duration > 5 }.min { $0.duration < $1.duration }
  }

  public convenience init(url: URL) throws {
    let d = try Data(contentsOf: url)
    guard d.count <= 512 * 1024 * 1024 else {
      throw RaceError.invalid("Telemetry file is larger than 512 MB.")
    }
    if url.pathExtension.lowercased() == "fit" || (d.count >= 12 && String(data: d[8..<12], encoding: .ascii) == ".FIT") {
      try self.init(text: FITReader.csv(d), title: url.deletingPathExtension().lastPathComponent)
      return
    }
    guard
      let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16)
        ?? String(data: d, encoding: .isoLatin1)
    else { throw RaceError.invalid("Could not decode telemetry text.") }
    let normalized = try TelemetryFormats.csv(from: d, text: text, extension: url.pathExtension.lowercased())
    try self.init(text: normalized, title: url.deletingPathExtension().lastPathComponent)
  }
  public init(text: String, title initialTitle: String = "Telemetry") throws {
    var header: [String] = []
    var cols: [[Double]] = []
    var ts: [Double] = []
    var fileTitle = initialTitle
    var timeColumn = 0
    var firstTime: Double?
    var previous: [Double] = []
    var delimiter: Character = ","
    var lapColumn: Int?
    var candidates: [(Int, Double)] = []
    text.enumerateLines { line, stop in
      if line.isEmpty { return }
      if header.isEmpty {
        let sep: Character =
          line.contains("\t") ? "\t" : (line.contains(";") && !line.contains(",") ? ";" : ",")
        let cells = Self.parseRow(line, delimiter: sep)
        if cells.first?.lowercased() == "session title", cells.count > 1 { fileTitle = cells[1] }
        if let t = cells.firstIndex(where: { Self.isTimeHeader($0) }), cells.count >= 2 {
          delimiter = sep
          header = cells
          timeColumn = t
          cols = Array(repeating: [], count: cells.count)
          previous = Array(repeating: Double.nan, count: cells.count)
          lapColumn = cells.firstIndex {
            ["lap #", "lap", "lap number", "lapnumber"].contains($0.lowercased())
          }
        }
        return
      }
      let cells = Self.parseRow(line, delimiter: delimiter)
      guard timeColumn < cells.count, let absolute = Self.parseTime(cells[timeColumn]),
        absolute.isFinite
      else { return }
      if firstTime == nil { firstTime = absolute }
      let time = absolute - (firstTime ?? absolute)
      guard time >= 0, time >= (ts.last ?? 0) else { return }
      // Duplicate timestamps are merged, keeping the last sample for correct binary search.
      let duplicate = ts.last == time
      for j in header.indices {
        if j < cells.count, let v = Double(cells[j]), v.isFinite { previous[j] = v }
        if duplicate {
          cols[j][cols[j].count - 1] = previous[j]
        } else {
          cols[j].append(previous[j])
        }
      }
      if !duplicate { ts.append(time) }
      if let c = lapColumn, previous[c].isFinite {
        if previous[c] > 0 && previous[c] < 1_000_000 {
          let l = Int(previous[c])
          if candidates.last?.0 != l { candidates.append((l, time)) }
        }
      }
    }
    guard !header.isEmpty, !ts.isEmpty else {
      throw RaceError.invalid(
        "No time series found. CSV needs a Time, Time (s), Timestamp or Elapsed time column.")
    }
    headers = header
    times = ts
    columns = cols
    title = fileTitle
    var a: [String: Int] = [:]
    func choose(_ key: String, _ patterns: [String]) {
      for pattern in patterns {
        if let i = header.firstIndex(where: { $0.lowercased() == pattern }) {
          a[key] = i
          return
        }
      }
      for pattern in patterns {
        if let i = header.firstIndex(where: { $0.lowercased().hasPrefix(pattern) }) {
          a[key] = i
          return
        }
      }
    }
    choose("speed", ["speed (m/s)", "speed (km/h)", "speed (mph)", "mph", "kph", "speed"])
    choose("rpm", ["rpm (rpm) *obd", "rpm", "engine rpm"])
    choose("gear", ["gear *obd", "gear"])
    choose("throttle", ["throttle position (%) *obd", "throttle", "accelerator"])
    choose("brake", ["brake", "brake position"])
    choose(
      "gx",
      [
        "longitudinal acceleration (g) *calc", "x acceleration (g) *acc", "accel x",
        "longitudinal acceleration",
      ])
    choose(
      "gy",
      [
        "lateral acceleration (g) *calc", "y acceleration (g) *acc", "accel y",
        "lateral acceleration",
      ])
    choose("lat", ["latitude (deg)", "latitude", "lat"])
    choose("lon", ["longitude (deg)", "longitude", "lon"])
    choose("x", ["x-position (m)", "x-position", "x"])
    choose("y", ["y-position (m)", "y-position", "y"])
    choose("distance", ["distance (m)", "distance"])
    choose("lap", ["lap #", "lap", "lap number"])
    choose("coolant", ["coolant temperature (.c) *obd", "coolant temperature", "coolant"])
    choose("intake", ["intake temperature (.c) *obd", "intake temperature", "intake"])
    choose("oil", ["engine oil temperature", "oil temperature", "oil"])
    aliases = a
    var ls: [TelemetryLap] = []
    for i in candidates.indices {
      ls.append(
        TelemetryLap(
          number: candidates[i].0, start: candidates[i].1,
          end: i + 1 < candidates.count ? candidates[i + 1].1 : (ts.last ?? 0),
          complete: i + 1 < candidates.count && (i > 0 || candidates[i].1 > 1)))
    }
    laps = ls
    var points: [(Double, Double)] = []
    let sx = a["x"] ?? a["lon"]
    let sy = a["y"] ?? a["lat"]
    if let sx = sx, let sy = sy {
      let factor =
        a["x"] == nil ? cos((cols[sy].first(where: \.isFinite) ?? 0) * Double.pi / 180) : 1
      for i in stride(from: 0, to: ts.count, by: max(1, ts.count / 4000)) {
        let x = cols[sx][i] * factor
        let y = cols[sy][i]
        if x.isFinite && y.isFinite { points.append((x, y)) }
      }
    }
    mapPoints = points
  }

  public static func isTimeHeader(_ s: String) -> Bool {
    [
      "time", "time (s)", "timestamp", "timestamp (s)", "elapsed time", "elapsed time (s)",
      "seconds", "time(s)",
    ].contains(s.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}\" ")).lowercased())
  }
  public static func parseTime(_ s: String) -> Double? {
    if let d = Double(s) { return d }
    let p = s.split(separator: ":").compactMap { Double($0) }
    return p.count >= 2 ? p.reduce(0) { $0 * 60 + $1 } : nil
  }
  public static func parseRow(_ line: String, delimiter: Character = ",") -> [String] {
    if !line.contains("\"") {
      return line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }
    var result: [String] = []
    var cell = ""
    var quoted = false
    var skip = false
    let chars = Array(line)
    for i in chars.indices {
      if skip {
        skip = false
        continue
      }
      let c = chars[i]
      if c == "\"" {
        if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
          cell.append("\"")
          skip = true
        } else {
          quoted.toggle()
        }
      } else if c == delimiter && !quoted {
        result.append(cell)
        cell = ""
      } else {
        cell.append(c)
      }
    }
    result.append(cell)
    return result
  }
  public func index(at t: Double) -> Int {
    var l = 0
    var r = times.count
    while l < r {
      let m = (l + r) / 2
      if times[m] <= t { l = m + 1 } else { r = m }
    }
    return max(0, min(times.count - 1, l - 1))
  }
  public func channelIndex(_ name: String) -> Int? {
    guard !name.isEmpty else { return nil }
    if let i = aliases[name.lowercased()] { return i }
    if let i = headers.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
      return i
    }
    let simple = name.lowercased().replacingOccurrences(of: "(", with: "").replacingOccurrences(
      of: ")", with: "")
    let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
    return headers.firstIndex { normalize($0).hasPrefix(normalize(simple)) }
  }
  public func value(_ channel: String, at t: Double, interpolate: Bool = true) -> Double? {
    guard t >= 0, t <= duration + 0.1, let c = channelIndex(channel) else { return nil }
    let i = index(at: t)
    let v = columns[c][i]
    guard v.isFinite else { return nil }
    if interpolate && i + 1 < times.count, times[i + 1] > times[i], columns[c][i + 1].isFinite {
      return v + (columns[c][i + 1] - v)
        * max(0, min(1, (t - times[i]) / (times[i + 1] - times[i])))
    }
    return v
  }
  public func speed(at t: Double, unit: String, channel: String = "speed") -> Double? {
    let mps: Double
    if let v = value(channel, at: t), let c = channelIndex(channel) {
      let h = headers[c].lowercased()
      mps = h.contains("mph") ? v / 2.2369362921 : (h.contains("knot") ? v * 0.514444 : (h.contains("km") || h == "kph" ? v / 3.6 : v))
    } else if channel == "speed", let lat = aliases["lat"], let lon = aliases["lon"], times.count > 1 {
      let i = min(index(at: t), times.count - 2)
      let dt = times[i + 1] - times[i]
      guard t >= 0, t <= duration, dt > 0 else { return nil }
      mps = Self.distance(lat1: columns[lat][i], lon1: columns[lon][i], lat2: columns[lat][i+1], lon2: columns[lon][i+1]) / dt
    } else { return nil }
    guard mps.isFinite else { return nil }
    return mps * (unit == "mph" ? 2.2369362921 : (unit == "km/h" ? 3.6 : (unit == "knots" ? 1.94384449 : 1)))
  }
  public func lap(at t: Double) -> TelemetryLap? { laps.last { $0.start <= t && t <= $0.end } }
  public func delta(at t: Double) -> Double? {
    guard let lap = lap(at: t), let best = bestLap, let distance = value("distance", at: t),
      let start = value("distance", at: lap.start),
      let bestStart = value("distance", at: best.start), let dc = aliases["distance"]
    else { return nil }
    let target = distance - start + bestStart
    var lo = index(at: best.start)
    var hi = index(at: best.end)
    while lo < hi {
      let m = (lo + hi) / 2
      if columns[dc][m] < target { lo = m + 1 } else { hi = m }
    }
    return (t - lap.start) - (times[lo] - best.start)
  }
}
