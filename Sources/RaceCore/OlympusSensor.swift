import Foundation

/// Identified Olympus OL* sensor sentences. Camera axes are intentionally not vehicle G.
enum OlympusSensorReader {
  static func timestamp(_ date:String,_ clock:String) throws -> Double {
    var calendar = Calendar(identifier:.gregorian);calendar.timeZone = TimeZone(secondsFromGMT:0)!
    let clockParts = clock.split(separator:".",omittingEmptySubsequences:false)
    func digits(_ value:Substring) -> Bool {!value.isEmpty && value.utf8.allSatisfy{(48...57).contains($0)}}
    guard date.count == 8,digits(date[...]),clockParts.count <= 2,clockParts[0].count == 6,
      clockParts.allSatisfy(digits),let seconds = Double(clock.dropFirst(4)),seconds >= 0,seconds < 60 else {
      throw RaceError.invalid("Olympus sensor timestamps require YYYYMMDD,HHMMSS[.fraction].")
    }
    let year = Int(date.prefix(4))!,month = Int(date.dropFirst(4).prefix(2))!,day = Int(date.suffix(2))!
    let hour = Int(clock.prefix(2))!,minute = Int(clock.dropFirst(2).prefix(2))!
    guard (1...9999).contains(year),(1...12).contains(month),(1...31).contains(day),(0...23).contains(hour),(0...59).contains(minute),
      let value = calendar.date(from:DateComponents(year:year,month:month,day:day,hour:hour,minute:minute,second:Int(seconds))),
      calendar.component(.month,from:value) == month,calendar.component(.day,from:value) == day else {
      throw RaceError.invalid("Invalid Olympus sensor calendar date/time.")
    }
    return value.timeIntervalSince1970+seconds-Double(Int(seconds))
  }
  static func sessions(_ text:String) throws -> [LoggerTextSession] {
    var rows:[[String]] = [],time:Double?,first:Double?,values = [String](repeating:"nan",count:10)
    var seen = Set<String>(),offsets = Set<Double>(),unknown = Set<String>(),invalid = 0
    func finishRow() {if let time,let first {rows.append([String(time-first)]+values)}}
    for raw in text.components(separatedBy:.newlines) {
      let line = raw.replacingOccurrences(of:"\u{FEFF}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {continue}
      guard line.hasPrefix("$") else {throw RaceError.invalid("Unsupported Olympus sensor text: expected $OLTIM/$OL… sentences.")}
      let body = String(line.dropFirst().prefix{ $0 != "*" })
      if let star = line.firstIndex(of:"*") {
        let checksum = line[line.index(after:star)...]
        guard checksum.count == 2,let expected = UInt8(checksum,radix:16),body.utf8.reduce(UInt8(0),^) == expected else {
          throw RaceError.invalid("Olympus sensor sentence checksum mismatch.")
        }
      }
      let fields = body.split(separator:",",omittingEmptySubsequences:false).map{String($0).trimmingCharacters(in:.whitespaces)}
      let tag = fields[0]
      func require(_ count:Int) throws {guard fields.count == count else {throw RaceError.invalid("Malformed Olympus \(tag) sentence.")}}
      if tag == "OLTIM" {
        guard rows.count < 1_000_000 else {throw RaceError.invalid("Olympus sensor log exceeds one million samples.")}
        try require(3);let next = try timestamp(fields[1],fields[2])
        guard time == nil || next > time! else {throw RaceError.invalid("Olympus sensor timestamps must increase; duplicate/reset clocks require separate logs.")}
        finishRow();time = next;if first == nil {first = next}
        values = [String](repeating:"nan",count:10);seen = [];continue
      }
      if tag == "OLSNSGPSTIM" {
        try require(5);offsets.insert(try timestamp(fields[3],fields[4])-timestamp(fields[1],fields[2]));continue
      }
      guard ["OLCMP","OLPRE","OLTMP","OLACC"].contains(tag) else {unknown.insert(tag);continue}
      guard time != nil,seen.insert(tag).inserted else {throw RaceError.invalid("Olympus sensor readings need one matching timestamp packet; duplicate or untimed \(tag) readings cannot be placed reliably.")}
      try require(tag == "OLCMP" ? 2 : 4)
      func number(_ index:Int) -> Double? {Double(fields[index]).flatMap{$0.isFinite ? $0 : nil}}
      func value(_ index:Int) -> String {if let n = number(index) {return String(n)};invalid += 1;return "nan"}
      switch tag {
      case "OLCMP":values[0] = value(1)
      case "OLPRE":values[1] = value(1);values[2] = value(2);values[3] = value(3)
      case "OLTMP":
        if let n = number(1),let unit = number(2),unit == 0 || unit == 1 {values[4] = String(unit == 0 ? n : (n-32)*5/9)}
        else {invalid += 1}
        values[5] = value(2);values[6] = value(3)
      default:values[7] = value(1);values[8] = value(2);values[9] = value(3)
      }
    }
    finishRow()
    guard rows.count >= 2,let first else {throw RaceError.invalid("Olympus sensor log needs at least two $OLTIM packets.")}
    var warnings = ["Olympus camera compass and raw acceleration axes are not automatically assigned to vehicle heading/G. Verify camera mounting and scale before manual assignment.","Olympus sensor import does not merge a GPSLOG companion; add GPS separately and synchronize explicitly."]
    var epoch:Double? = first
    if offsets.count == 1 {epoch = first+offsets.first!}
    else if offsets.count > 1 {epoch = nil;warnings.append("Olympus camera/GPS clock offsets change within the log; no UTC anchor was inferred. Sample timing retains the camera clock.")}
    else {warnings.append("Olympus timestamps use the reported camera UTC clock, without GPS clock correction; verify the camera clock before time-of-day synchronization.")}
    if invalid > 0 {warnings.append("\(invalid) Olympus sensor fields have invalid values or unknown temperature units; missing values were retained.")}
    if !unknown.isEmpty {warnings.append("Unknown Olympus sensor sentence types were omitted: "+unknown.sorted().joined(separator:", "))}
    let headers = ["Time","Camera compass (deg)","Atmospheric pressure (hPa)","Sensor altitude (m)","Sensor altitude (ft)","Ambient temperature (C)","Temperature unit flag","Temperature status (raw)","Camera acceleration X (raw)","Camera acceleration Y (raw)","Camera acceleration Z (raw)"]
    var document = LoggerTextSession(name:"Olympus sensors",text:LoggerText.csv(headers,rows),epoch:epoch,count:rows.count,warnings:warnings)
    document.gpsClockCorrected = offsets.count == 1
    return [document]
  }
}
