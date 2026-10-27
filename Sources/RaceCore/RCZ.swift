import Foundation

/// Independent reader of RaceChrono's ZIP session and little-endian channel streams.
/// Each (device, stream) has its own clock; resampling retains their timestamp union.
enum RCZReader {
  struct Table {
    var title: String
    var firstSampleUnixTime: Double
    var times: [Double]
    var headers: [String]
    var columns: [[Double]]
    var aliases: [String: Int]
    var discreteColumns: Set<Int>
    var laps: [TelemetryLap]
    var warnings: [String]
  }
  private struct Key: Hashable { var type: Int; var device: Int; var stream: Int }
  private struct File {
    var name: String; var key: Key; var channel: Int; var encoding: Int
    init?(_ name: String) {
      let parts = (name as NSString).lastPathComponent.split(separator: "_").map(String.init)
      guard parts.count == 6, ["channel", "channel2"].contains(parts[0]),
        let type = Int(parts[1]), let device = Int(parts[2]), let stream = Int(parts[3]),
        let channel = Int(parts[4]), let encoding = Int(parts[5]),
        [type, device, stream, channel, encoding].allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }) else { return nil }
      self.name = name; key = Key(type: type, device: device, stream: stream)
      self.channel = channel; self.encoding = encoding
    }
  }
  private struct Clock { var times: [Int64]; var indices: [Int] }
  private struct Fragment {
    var files: [File]; var clocks: [Key: Clock]; var roles: [Int: Int]
    var gyroBiases: [Int: [Double]]
    var primaryGPS: Int?; var start: Int64; var end: Int64
  }
  private struct Run { var times: [Int64]; var values: [Double]; var start: Int64; var end: Int64 }
  private struct Track {
    var header: String; var alias: String?; var priority: Int; var discrete: Bool; var runs: [Run]
    func resample(_ timeline: [Int64]) -> [Double] {
      let runs = runs.sorted { $0.start < $1.start }
      var output = [Double](repeating: .nan, count: timeline.count), r = 0, i = 0
      for (row, time) in timeline.enumerated() {
        while r + 1 < runs.count && runs[r].end < time { r += 1; i = 0 }
        let run = runs[r]
        guard time >= run.start, time <= run.end, let first = run.times.first, time >= first else { continue }
        while i + 1 < run.times.count && run.times[i + 1] <= time { i += 1 }
        let value = run.values[i]
        guard value.isFinite else { continue }
        if !discrete, i + 1 < run.times.count, run.values[i + 1].isFinite, time > run.times[i] {
          let fraction = Double(time - run.times[i]) / Double(run.times[i + 1] - run.times[i])
          if alias == "heading" {
            output[row] = Telemetry.normalHeading(value+Telemetry.headingDelta(from:value,to:run.values[i+1])*fraction)
          } else { output[row] = value + (run.values[i + 1] - value) * fraction }
        } else { output[row] = value }
      }
      return output
    }
  }
  private struct Field {
    var label: String; var unit: String = ""; var alias: String?; var discrete = false
    var scale = 1.0; var raw = false
  }

  static func read(_ data: Data, title fallbackTitle: String) throws -> Table {
    let zip = try ZIPArchive(data)
    let names = zip.entries.keys.filter { !$0.hasPrefix("__MACOSX/") && !($0 as NSString).lastPathComponent.hasPrefix("._") }.sorted()
    let sessions = names.filter { ($0 as NSString).lastPathComponent == "session.json" }
    guard sessions.count == 1 else {
      throw RaceError.invalid(sessions.isEmpty
        ? "RCZ contains no recorded session. Vehicle and track profiles cannot be imported as telemetry."
        : "RCZ contains multiple sessions. Share or export one RaceChrono session as an RCZ file first.")
    }
    let sessionName = sessions[0], prefix = String(sessionName.dropLast("session.json".count))
    let session = try json(zip.read(sessionName))
    let channelFiles = names.filter { $0.hasPrefix(prefix) }.compactMap(File.init)
    let folders = Set(channelFiles.map { ($0.name as NSString).deletingLastPathComponent })
    var fragments: [Fragment] = [], allTimes = Set<Int64>(), warnings: [String] = []
    for folder in folders.sorted() {
      let files = channelFiles.filter { ($0.name as NSString).deletingLastPathComponent == folder }
      let fragmentName = folder.isEmpty ? "sessionfragment.json" : folder + "/sessionfragment.json"
      let metadata = zip.entries[fragmentName] == nil ? [:] : try json(zip.read(fragmentName))
      var roles: [Int: Int] = [:]
      var gyroBiases: [Int: [Double]] = [:]
      let items = (metadata["devices"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
      let selectors = (metadata["devices2"] as? [[String: Any]] ?? []).compactMap { $0["selector"] as? [String: Any] }
      for item in selectors + items {
        if let id = integer(item["id"]), let type = integer(item["type"]) { roles[id] = type }
      }
      for item in metadata["devices2"] as? [[String: Any]] ?? [] {
        if let selector = item["selector"] as? [String: Any], let id = integer(selector["id"]),
          let bias = item["gyroBias"] as? [NSNumber], bias.count == 3, bias.allSatisfy({ $0.doubleValue.isFinite }) {
          gyroBiases[id] = bias.map(\.doubleValue)
        }
      }
      var clocks: [Key: Clock] = [:]
      for file in files where file.channel == 1 && file.encoding == 1 {
        let bytes = try zip.read(file.name)
        guard bytes.count % 8 == 0, bytes.count / 8 <= 2_000_000 else { throw RaceError.invalid("Invalid RCZ timestamp stream length.") }
        var times: [Int64] = [], indices: [Int] = []
        try bytes.withUnsafeBytes { raw in
          for i in 0..<bytes.count / 8 {
            let t = Int64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: Int64.self))
            // Zero/Int64.max pad unfinished buffers in older recordings.
            guard t > 0, t < 8_640_000_000_000_000 else { continue }
            guard t >= (times.last ?? t) else { throw RaceError.invalid("RCZ timestamps are not chronological.") }
            if t == times.last { indices[indices.count - 1] = i }
            else { times.append(t); indices.append(i) }
          }
        }
        if !times.isEmpty {
          clocks[file.key] = Clock(times: times, indices: indices)
          if roles[file.key.device] == nil { roles[file.key.device] = file.key.type }
        }
      }
      guard let rawStart = clocks.values.compactMap({ $0.times.first }).min(),
        let rawEnd = clocks.values.compactMap({ $0.times.last }).max() else { continue }
      let declaredStart = integer(metadata["firstTimestamp"] ?? session["firstTimestamp"]).map(Int64.init) ?? rawStart
      let declaredEnd = integer(metadata["latestTimestamp"] ?? session["latestTimestamp"]).map(Int64.init) ?? rawEnd
      let start = max(rawStart, declaredStart), end = min(rawEnd, declaredEnd)
      guard start <= end else { continue }
      for clock in clocks.values { allTimes.formUnion(clock.times.filter { $0 >= start && $0 <= end }) }
      allTimes.insert(start); allTimes.insert(end)
      guard allTimes.count <= 2_000_000 else { throw RaceError.invalid("RCZ has too many timestamp samples.") }
      fragments.append(Fragment(files: files, clocks: clocks, roles: roles, gyroBiases: gyroBiases,
        primaryGPS: integer(metadata["primaryGpsDeviceIndex"]), start: start, end: end))
    }
    fragments.sort { $0.start < $1.start }
    guard let first = allTimes.min(), let last = allTimes.max(), !fragments.isEmpty else {
      throw RaceError.invalid("RCZ contains no readable timestamped channel streams.")
    }
    // Preserve pauses rather than interpolating the last point into the next resume.
    for (a, b) in Swift.zip(fragments, fragments.dropFirst()) where b.start - a.end > 2 {
      allTimes.insert(a.end + 1); allTimes.insert(b.start - 1)
    }
    var tracks: [Track] = [], trackIndices: [String: Int] = [:], rawIDs = Set<Int>(), skipped = 0
    var previousDistance: Double?
    for fragment in fragments {
      let distances = fragment.files.filter { $0.channel == 2 && fragment.clocks[$0.key] != nil }
      let distance = distances.sorted {
        func score(_ f: File) -> Int { (fragment.roles[f.key.device] == 1 ? 100 : 0) + (f.key.device == fragment.primaryGPS ? 100 : 0) + (f.key.stream == 0 ? 10 : 0) }
        if score($0) != score($1) { return score($0) > score($1) }
        return $0.name < $1.name
      }.first?.name
      // Prefer newer floating-point files if a legacy cached channel also exists.
      var seen = Set<String>()
      for file in fragment.files.sorted(by: { $0.encoding == $1.encoding ? $0.name < $1.name : $0.encoding > $1.encoding }) {
        guard file.channel != 1, let clock = fragment.clocks[file.key] else { continue }
        if file.channel == 2 && file.name != distance { continue }
        let identity = "\(file.key.type)/\(file.key.device)/\(file.key.stream)/\(file.channel)"
        guard seen.insert(identity).inserted else { continue }
        guard [0, 1, 3].contains(file.encoding) else { skipped += 1; continue }
        let bytes = try zip.read(file.name)
        let role = fragment.roles[file.key.device] ?? file.key.type
        var fields: [(Field, [Double])] = []
        if file.channel == 3 && file.encoding == 1 {
          let pairs = try numbers(bytes, encoding: 0)
          let lat = clock.indices.map { i in i * 2 < pairs.count && abs(pairs[i * 2] / 6_000_000) <= 90 ? pairs[i * 2] / 6_000_000 : .nan }
          let lon = clock.indices.map { i in i * 2 + 1 < pairs.count && abs(pairs[i * 2 + 1] / 6_000_000) <= 180 ? pairs[i * 2 + 1] / 6_000_000 : .nan }
          fields = [(Field(label: "Latitude", unit: "deg", alias: "lat"), lat), (Field(label: "Longitude", unit: "deg", alias: "lon"), lon)]
        } else {
          var field = Self.field(file.channel)
          let values = try numbers(bytes, encoding: file.encoding)
          if field.raw { rawIDs.insert(file.channel) }
          // Integer channels use thousandths of their SI quantity. Distances
          // are int64 millimetres; counts and packed GPS positions are exceptions.
          let integralScale = file.channel == 2 ? 0.001
            : (file.encoding == 0 && !field.raw && ![30002, 30003].contains(file.channel & 0x7fff) ? 0.001 : 1)
          var result = clock.indices.map { i in i < values.count ? values[i] * integralScale * field.scale : .nan }
          let base = file.channel & 0x7fff
          if (12...14).contains(base), let bias = fragment.gyroBiases[file.key.device]?[base - 12] {
            let correction = file.encoding == 0 ? (bias * 1000).rounded() / 1000 : bias
            result = result.map { $0 - correction }
          }
          if file.channel == 2 {
            let a = sample(result, times: clock.times, at: fragment.start) ?? result.first(where: \.isFinite)
            let b = sample(result, times: clock.times, at: fragment.end) ?? result.last(where: \.isFinite)
            let offset = a.flatMap { first in previousDistance.map { max(0, $0 - first) } } ?? 0
            if offset > 0 { result = result.map { $0 + offset } }
            previousDistance = b.map { $0 + offset } ?? previousDistance
            field.alias = "distance"
          }
          fields = [(field, result)]
        }
        for (field, values) in fields {
          guard values.contains(where: \.isFinite) else { continue }
          let unit = field.unit.isEmpty ? "" : " (\(field.unit))"
          let header = file.channel == 2 ? "Distance (m)" : field.label + unit + " *\(source(role)) \(file.key.device)"
          let priority = (role == 1 ? 100 : 0) + (file.key.device == fragment.primaryGPS ? 100 : 0)
            + (file.channel == 10025 ? 20 : 0) + (file.channel == 10024 ? 20 : 0)
          let run = Run(times: clock.times, values: values, start: fragment.start, end: fragment.end)
          if let index = trackIndices[header] { tracks[index].runs.append(run) }
          else {
            trackIndices[header] = tracks.count
            tracks.append(Track(header: header, alias: field.alias, priority: priority, discrete: field.discrete, runs: [run]))
          }
        }
      }
    }
    guard !tracks.isEmpty else { throw RaceError.invalid("RCZ contains no readable telemetry values.") }
    let laps = lapList(session["laps"] as? [[String: Any]] ?? [], start: first, end: last)
    for lap in laps {
      allTimes.insert(first + Int64((lap.start * 1000).rounded()))
      allTimes.insert(first + Int64((lap.end * 1000).rounded()))
    }
    guard tracks.count <= 256, allTimes.count <= 2_000_000,
      allTimes.count * (tracks.count + 2) <= 32_000_000 else { throw RaceError.invalid("RCZ telemetry exceeds the supported sample/channel limit.") }
    let timeline = allTimes.sorted(), times = timeline.map { Double($0 - first) / 1000 }
    var columns = [times], headers = ["Time"], aliases: [String: Int] = [:], priorities: [String: Int] = [:], discreteColumns = Set<Int>()
    for track in tracks.sorted(by: { $0.header < $1.header }) {
      let index = columns.count
      if let key = track.alias, track.priority > (priorities[key] ?? -1) { aliases[key] = index; priorities[key] = track.priority }
      if track.discrete { discreteColumns.insert(index) }
      headers.append(track.header); columns.append(track.resample(timeline))
    }
    if !laps.isEmpty {
      aliases["lap"] = columns.count; headers.append("Lap #")
      discreteColumns.insert(columns.count)
      var i = 0
      columns.append(times.map { t in
        while i + 1 < laps.count && laps[i + 1].start <= t { i += 1 }
        return t >= laps[i].start && t <= laps[i].end ? Double(laps[i].number) : .nan
      })
    }
    if skipped > 0 { warnings.append("Skipped \(skipped) RCZ channels with unsupported numeric encodings.") }
    if !rawIDs.isEmpty { warnings.append("Retained \(rawIDs.count) unrecognized RCZ channel identifiers as raw numeric values.") }
    let title = [session["title"] as? String, session["trackName"] as? String, fallbackTitle]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? fallbackTitle
    return Table(title: title, firstSampleUnixTime: Double(first) / 1000, times: times,
      headers: headers, columns: columns, aliases: aliases, discreteColumns: discreteColumns, laps: laps, warnings: warnings)
  }

  private static func json(_ data: Data) throws -> [String: Any] {
    guard data.count <= 4 * 1024 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RaceError.invalid("Invalid RCZ session metadata.")
    }
    return value
  }
  private static func sample(_ values: [Double], times: [Int64], at time: Int64) -> Double? {
    guard let first = times.first, time >= first else { return nil }
    var lo = 0, hi = times.count - 1
    while lo < hi { let mid = (lo + hi + 1) / 2; if times[mid] <= time { lo = mid } else { hi = mid - 1 } }
    guard values[lo].isFinite else { return nil }
    if lo + 1 < times.count, values[lo + 1].isFinite {
      return values[lo] + (values[lo + 1] - values[lo]) * Double(time - times[lo]) / Double(times[lo + 1] - times[lo])
    }
    return values[lo]
  }
  private static func integer(_ value: Any?) -> Int? {
    guard let n = value as? NSNumber, n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue < Double(Int.max), n.doubleValue.rounded() == n.doubleValue else { return nil }
    return n.intValue
  }
  private static func numbers(_ data: Data, encoding: Int) throws -> [Double] {
    let size = encoding == 0 ? 4 : 8
    guard data.count % size == 0 else { throw RaceError.invalid("Truncated RCZ numeric channel.") }
    return data.withUnsafeBytes { raw in
      (0..<data.count / size).map { i in
        if encoding == 0 {
          let n = Int32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: Int32.self))
          return n == .max ? .nan : Double(n)
        }
        let bits = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
        if encoding == 1 { let n = Int64(bitPattern: bits); return n == .max || n == .min ? .nan : Double(n) }
        let n = Double(bitPattern: bits); return n.isFinite ? n : .nan
      }
    }
  }
  private static func lapList(_ entries: [[String: Any]], start: Int64, end: Int64) -> [TelemetryLap] {
    var result: [TelemetryLap] = [], used = Set<Int>()
    for entry in entries.prefix(50_000) {
      guard let number = integer(entry["number"]), number > 0, number < 1_000_000,
        let a = entry["startTimestamp"] as? NSNumber, a.doubleValue.isFinite,
        a.doubleValue >= 0, a.doubleValue < 8.64e15 else { continue }
      let b = (entry["finishTimestamp"] as? NSNumber)?.doubleValue
      let finish = b.flatMap { $0.isFinite && $0 >= a.doubleValue && $0 < 8.64e15 ? $0 : nil }
      let lo = max(Double(start), a.doubleValue), hi = min(Double(end), finish ?? Double(end))
      guard lo < hi, used.insert(number).inserted else { continue }
      result.append(TelemetryLap(number: number, start: (lo - Double(start)) / 1000,
        end: (hi - Double(start)) / 1000,
        complete: a.doubleValue >= Double(start) && finish != nil && finish! <= Double(end) && entry["isInvalid"] as? Bool != true))
    }
    return result.sorted { $0.start < $1.start }
  }
  private static func source(_ type: Int) -> String {
    [1: "GPS", 2: "ACC", 3: "GYRO", 4: "DATA", 5: "OBD", 6: "HRM", 8: "MAGN", 12: "CANBUS"][type] ?? "DEVICE\(type)"
  }
  private static func field(_ id: Int) -> Field {
    let base = id & 0x7fff, position = (id >> 15) & 31, sensor = (id >> 20) & 63
    let definitions: [Int: Field] = [
      2: Field(label: "Distance", unit: "m", alias: "distance"),
      4: Field(label: "Speed", unit: "m/s", alias: "speed"),
      5: Field(label: "Altitude", unit: "m"), 6: Field(label: "Heading", unit: "deg", alias:"heading"),
      7: Field(label: "Lateral acceleration", unit: "g", alias: "gy", scale: 1 / 9.80665),
      8: Field(label: "Longitudinal acceleration", unit: "g", alias: "gx", scale: 1 / 9.80665),
      9: Field(label: "X acceleration", unit: "g", scale: 1 / 9.80665),
      10: Field(label: "Y acceleration", unit: "g", scale: 1 / 9.80665),
      11: Field(label: "Z acceleration", unit: "g", scale: 1 / 9.80665),
      12: Field(label: "X rotation rate", unit: "deg/s"), 13: Field(label: "Y rotation rate", unit: "deg/s"),
      14: Field(label: "Z rotation rate", unit: "deg/s"), 15: Field(label: "Device update rate", unit: "Hz"),
      28: Field(label: "X magnetic field", unit: "µT"), 29: Field(label: "Y magnetic field", unit: "µT"), 30: Field(label: "Z magnetic field", unit: "µT"),
      37: Field(label: "Lean angle", unit: "deg"), 38: Field(label: "Pitch", unit: "deg"),
      39: Field(label: "Yaw", unit: "deg"), 41: Field(label: "Heart rate", unit: "bpm"),
      43: Field(label: "Combined acceleration", unit: "g", scale: 1 / 9.80665),
      44: Field(label: "Latitude", unit: "deg", alias: "lat"), 45: Field(label: "Longitude", unit: "deg", alias: "lon"),
      46: Field(label: "Device battery level", unit: "%"), 47: Field(label: "Device battery voltage", unit: "V"),
      48: Field(label: "Roll", unit: "deg"), 49: Field(label: "Roll rate", unit: "deg/s"),
      50: Field(label: "Pitch rate", unit: "deg/s"), 51: Field(label: "Yaw rate", unit: "deg/s"),
      1001: Field(label: "Steering angle", unit: "deg"),
      1002: Field(label: "Brake position", unit: "%", alias: "brake"),
      1003: Field(label: "Clutch position", unit: "%"), 1004: Field(label: "Gear", alias: "gear", discrete: true),
      1007: Field(label: "Engine oil pressure", unit: "kPa"),
      1013: Field(label: "Tyre temperature", unit: "°C"), 1014: Field(label: "Tyre pressure", unit: "kPa"),
      1015: Field(label: "Wheel speed", unit: "m/s"), 1023: Field(label: "Air fuel ratio"),
      1033: Field(label: "Brake pressure", unit: "kPa"),
      10024: Field(label: "RPM", unit: "rpm", alias: "rpm"),
      10025: Field(label: "Throttle position", unit: "%", alias: "throttle"),
      10026: Field(label: "Coolant temperature", unit: "°C", alias: "coolant"),
      10029: Field(label: "Intake temperature", unit: "°C", alias: "intake"),
      10031: Field(label: "Air temperature", unit: "°C"), 10032: Field(label: "Engine load", unit: "%"),
      10058: Field(label: "Fuel level", unit: "%"), 10063: Field(label: "ECU voltage", unit: "V"),
      10066: Field(label: "Engine oil temperature", unit: "°C", alias: "oil"),
      10071: Field(label: "Accelerator position", unit: "%", alias: "throttle"),
      20002: Field(label: "RPM", unit: "rpm", alias: "rpm"), 20010: Field(label: "Digital 2"),
      30002: Field(label: "Satellites", discrete: true), 30003: Field(label: "GPS fix type", discrete: true),
      30004: Field(label: "Coordinate precision", unit: "DOP"), 30005: Field(label: "Altitude precision", unit: "DOP"),
      30007: Field(label: "GPS accuracy", unit: "m"),
    ]
    var value = definitions[base] ?? Field(label: "Raw RCZ channel \(id)", raw: true)
    if (20003...20007).contains(base) { value = Field(label: "Analog \(base - 20002)") }
    if (20011...20020).contains(base) { value = Field(label: "Analog \(base - 20005)") }
    if position != 0 { value.label += " " + ([1: "Front", 2: "Rear", 3: "RR", 4: "RL", 5: "FR", 6: "FL"][position] ?? "Position\(position)") }
    if sensor != 0 { value.label += " \(sensor)" }
    if position != 0 || sensor != 0 || id & 0xf8000000 != 0 { value.alias = nil }
    return value
  }
}
