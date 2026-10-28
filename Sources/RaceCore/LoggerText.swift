import Foundation
import CoreFoundation

struct LoggerTextSession {
  var name:String
  var text:String
  var epoch:Double?
  var count:Int
  var warnings:[String] = []
}

/// Explicit text dialects; closed binary formats are refused rather than interpreted as video.
enum LoggerText {
  static let unsupportedExtensions = ["gtr","gts","prr","sa","moff","sns","snslog","mlg","ms3","frd"]
  static func unsupported(_ ext:String) -> RaceError {
    .invalid("The .\(ext.uppercased()) logger format has no verified reader. Export a timestamped CSV/GPX in the logger’s software first. MegaSquirt binary logs can be converted to text .MSL in TunerStudio.")
  }
  static func quote(_ text:String) -> String {"\""+text.replacingOccurrences(of:"\"",with:"\"\"")+"\""}
  static func csv(_ headers:[String],_ rows:[[String]]) -> String {
    ([headers.map(quote).joined(separator:",")]+rows.map{$0.map(quote).joined(separator:",")}).joined(separator:"\n")
  }
  /// Split on explicit header repeats or a finite clock restarting at/before the first sample. Isolated out-of-order rows remain for the normal parser to diagnose. Blank lines do not split logs.
  static func split(_ text:String,timeColumn:String? = nil) -> [LoggerTextSession] {
    let lines = text.components(separatedBy:.newlines)
    var header:[String] = [],preamble:[String] = [],rows:[[String]] = [],sessions:[LoggerTextSession] = []
    var separator:Character = ",",clock = 0,last:Double?,firstTime:Double?
    func finish() {
      if !rows.isEmpty {
        let name = "Session \(sessions.count+1)"
        sessions.append(LoggerTextSession(name:name,text:(preamble+[csv(header,rows)]).joined(separator:"\n"),count:rows.count));rows = [];last = nil;firstTime = nil
      }
    }
    for line in lines {
      if line.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {continue}
      if header.isEmpty {
        separator = line.contains("\t") ? "\t" : (line.contains(";") && !line.contains(",") ? ";" : ",")
        let cells = Telemetry.parseRow(line.replacingOccurrences(of:"\u{FEFF}",with:""),delimiter:separator)
        let index = timeColumn.flatMap {name in cells.firstIndex(where:{$0.caseInsensitiveCompare(name) == .orderedSame})} ?? cells.firstIndex(where:Telemetry.isTimeHeader)
        if let index,cells.count >= 2 {header = cells;clock = index}
        else {preamble.append(line)}
        continue
      }
      let cells = Telemetry.parseRow(line,delimiter:separator)
      if cells == header {finish();continue}
      guard clock < cells.count,let time = Telemetry.parseTime(cells[clock]),time.isFinite else {continue}
      if let previous = last,let initial = firstTime,time < previous,time <= initial {finish()}
      rows.append(cells);last = max(last ?? time,time);if firstTime == nil {firstTime = time}
    }
    finish()
    return sessions.isEmpty ? [LoggerTextSession(name:"Session 1",text:text,count:0)] : sessions
  }
  static func msl(_ text:String) throws -> [LoggerTextSession] {
    let lines = text.components(separatedBy:.newlines)
    guard let index = lines.firstIndex(where:{line in
      let sep:Character = line.contains("\t") ? "\t" : ","
      return Telemetry.parseRow(line,delimiter:sep).contains(where:{$0.caseInsensitiveCompare("Time") == .orderedSame})
    }) else {throw RaceError.invalid("MSL text log needs a Time column. Convert binary MS3/MLG logs in TunerStudio first.")}
    let sep:Character = lines[index].contains("\t") ? "\t" : ","
    var headers = Telemetry.parseRow(lines[index],delimiter:sep)
    guard let clock = headers.firstIndex(where:{$0.caseInsensitiveCompare("Time") == .orderedSame}),headers.count >= 2 else {throw RaceError.invalid("Invalid MSL header.")}
    var first = index+1,units:[String] = []
    if first < lines.count {
      let next = Telemetry.parseRow(lines[first],delimiter:sep)
      if clock < next.count,Double(next[clock]) == nil,!next[clock].isEmpty {units = next;first += 1}
    }
    let timeUnit = units.indices.contains(clock) ? units[clock].lowercased().trimmingCharacters(in:.whitespaces) : "s"
    let timeScale:Double
    switch timeUnit {case "s","sec","secs","second","seconds","":timeScale = 1
    case "ms","millisecond","milliseconds":timeScale = 0.001
    default:throw RaceError.invalid("Unsupported MSL Time unit ‘\(timeUnit)’. Export seconds or milliseconds.")}
    var transforms:[Int:(Double)->Double] = [:]
    for i in headers.indices {
      let key = headers[i].lowercased().trimmingCharacters(in:.whitespaces)
      let unit = units.indices.contains(i) ? units[i].trimmingCharacters(in:.whitespaces) : ""
      switch key {
      case "time":headers[i] = "Time"
      case "rpm":headers[i] = "RPM"
      case "tps","throttle position":headers[i] = unit.isEmpty || unit == "%" ? "Throttle (%)" : "TPS (\(unit))"
      case "clt","ect","mat","iat":
        let role = ["clt","ect"].contains(key) ? "Coolant" : "Intake"
        if ["f","°f","degf"].contains(unit.lowercased()) {headers[i] = role+" temperature (C)";transforms[i] = {($0-32)*5/9}}
        else if ["c","°c","degc"].contains(unit.lowercased()) {headers[i] = role+" temperature (C)"}
        else {headers[i] += unit.isEmpty ? "" : " (\(unit))"}
      case "gps latitude":headers[i] = "Latitude"
      case "gps longitude":headers[i] = "Longitude"
      case "vss","vss1","vehicle speed","speed":
        if ["mph","km/h","kph","m/s"].contains(unit.lowercased()) {headers[i] = "Speed (\(unit.lowercased() == "kph" ? "km/h" : unit))"}
        else {headers[i] += unit.isEmpty ? "" : " (\(unit))"}
      default:if !unit.isEmpty,!headers[i].contains("(") {headers[i] += " (\(unit))"}
      }
    }
    var rows:[[String]] = []
    for line in lines.dropFirst(first) {
      var row = Telemetry.parseRow(line,delimiter:sep)
      guard clock < row.count,let time = Double(row[clock]),time.isFinite else {continue}
      row[clock] = String(time*timeScale)
      for (i,transform) in transforms where i < row.count {if let value = Double(row[i]) {row[i] = String(transform(value))}}
      rows.append(row)
    }
    guard rows.count >= 2 else {throw RaceError.invalid("MSL log contains fewer than two timestamped samples.")}
    return split(csv(headers,rows))
  }
  static func gutma(_ data:Data) throws -> [LoggerTextSession] {
    guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],let exchange = root["exchange"] as? [String:Any],
      exchange["exchange_type"] as? String == "flight_logging",let message = exchange["message"] as? [String:Any],
      let log = message["flight_logging"] as? [String:Any],let keys = log["flight_logging_keys"] as? [String],
      let samples = log["flight_logging_items"] as? [[Any]],keys.count >= 2,keys.count <= 256,samples.count <= 1_000_000,
      let clock = keys.firstIndex(of:"timestamp"),Set(keys).count == keys.count,
      let start = log["logging_start_dtg"] as? String else {throw RaceError.invalid("Unsupported JSON telemetry. Expected a GUTMA flight_logging document (as exported by supported Parrot tools).")}
    guard log["uom_system"] as? String == "Metric" else {throw RaceError.invalid("GUTMA telemetry must declare Metric units.")}
    let iso = ISO8601DateFormatter(),fractional = ISO8601DateFormatter();fractional.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
    guard let date = fractional.date(from:start) ?? iso.date(from:start) else {throw RaceError.invalid("GUTMA logging_start_dtg needs a UTC/timezone-qualified ISO timestamp.")}
    let labels = ["timestamp":"Time","gps_lat":"Latitude (deg)","gps_lon":"Longitude (deg)","gps_altitude":"Altitude (m)","speed":"Speed (m/s)","speed_vx":"Drone velocity X (m/s)","speed_vy":"Drone velocity Y (m/s)","speed_vz":"Drone velocity Z (m/s)","battery_voltage":"Battery voltage (V)"]
    let headers = keys.map{labels[$0] ?? $0}
    var rows:[[String]] = [];var last = -Double.infinity
    for sample in samples {
      guard sample.count == keys.count,let time = sample[clock] as? NSNumber,CFGetTypeID(time) != CFBooleanGetTypeID(),time.doubleValue.isFinite,time.doubleValue >= 0,time.doubleValue >= last else {throw RaceError.invalid("GUTMA rows need matching keys and increasing finite timestamps.")}
      last = time.doubleValue
      var row = sample.map {value -> String in
        guard let number = value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.isFinite else {return "nan"};return number.stringValue
      }
      for key in ["gps_lat","gps_lon"] {if let i = keys.firstIndex(of:key),let value = Double(row[i]),abs(value) > (key == "gps_lat" ? 90 : 180) {row[i] = "nan"}}
      rows.append(row)
    }
    guard rows.count >= 2,let first = Double(rows[0][clock]) else {throw RaceError.invalid("GUTMA log needs at least two timestamped samples.")}
    // Generic CSV establishes zero at its first row; shift the epoch by that same amount.
    return [LoggerTextSession(name:"Flight",text:csv(headers,rows),epoch:date.timeIntervalSince1970+first,count:rows.count)]
  }
}
