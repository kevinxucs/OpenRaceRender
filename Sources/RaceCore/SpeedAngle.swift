import Foundation

/// R4 v4 text layout from the vendor's SA Log Format appendix. Paired motion
/// fields retain their values without inventing timing or an acceleration scale.
enum SpeedAngleReader {
  static func sessions(_ text:String) throws -> [LoggerTextSession] {
    var result:[LoggerTextSession] = [],version:String?,name = "",unit:String?,date = ""
    var sectorCount:Int?,timer = false,trace = false,declared:Int?
    var finishTimes:[Double] = [],finishSamples:[Double] = [],rows:[[String]] = []
    var invalid = 0
    func attribute(_ line:String,_ key:String) -> String? {
      guard let range = line.range(of:"#"+key+"=",options:.caseInsensitive) else {return nil}
      return String(line[range.upperBound...].prefix{!$0.isWhitespace && $0 != ">"}).trimmingCharacters(in:CharacterSet(charactersIn:"\"'"))
    }
    func finish() throws {
      guard !rows.isEmpty else {throw RaceError.invalid("SpeedAngle trace contains no samples.")}
      let duration = Double(rows.count-1)/10
      var warnings = ["SpeedAngle acceleration readings retain their raw scale; configure a verified conversion before assigning them to physical G channels. Paired motion readings remain separate channels."]
      if !date.isEmpty {warnings.append("SpeedAngle header date/time has no timezone; no UTC anchor was inferred.")}
      if let declared,declared != rows.count,declared != rows.count-1 {warnings.append("SpeedAngle point count differs from its trace; all rows were retained at the documented 10 Hz rate.")}
      if invalid > 0 {warnings.append("\(invalid) SpeedAngle trace rows have invalid GPS fixes; GPS/speed remain missing while motion fields and sample timing are retained.")}
      var starts = finishSamples
      if finishTimes.count == finishSamples.count,zip(finishTimes,finishSamples).allSatisfy({$0 >= $1 && $0 < $1+0.100001}) {starts = finishTimes}
      else if !finishTimes.isEmpty {warnings.append("SpeedAngle timer/trace finish markers disagree; sample-level finish markers were used.")}
      starts = Array(Set(starts.filter{$0 > 0 && $0 <= duration})).sorted()
      var index = 0
      for i in rows.indices {
        while index < starts.count,starts[index] <= Double(i)/10 {index += 1}
        rows[i].append(String(index))
      }
      let speed = unit == "MILE/H" || unit == "MPH" ? "Speed (mph)" : "Speed (km/h)"
      let headers = ["Time","Latitude (deg)","Longitude (deg)",speed,"Lean angle (deg)","SA second lean angle (deg)","SA acceleration (raw)","SA second acceleration (raw)","SA previous turn angle (deg)","GPS satellites","SA signal valid","SA sector marker","SA finish marker","Lap #"]
      let preamble = name.isEmpty ? "" : LoggerText.csv(["Location name",name],[])+"\n"
      var document = LoggerTextSession(name:name.isEmpty ? "SpeedAngle \(result.count+1)" : name,text:preamble+LoggerText.csv(headers,rows),count:rows.count,warnings:warnings)
      document.lapStarts = starts;result.append(document)
      rows = [];finishSamples = [];finishTimes = [];invalid = 0;declared = nil
    }
    for raw in text.components(separatedBy:.newlines) {
      let line = raw.replacingOccurrences(of:"\u{FEFF}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix(";") {continue}
      if trace {
        if line.lowercased() == "</trace>" {try finish();trace = false;continue}
        guard !line.hasPrefix("<"),!line.hasPrefix("#") else {throw RaceError.invalid("SpeedAngle trace ended without </trace>.")}
        let fields = Telemetry.parseRow(line,delimiter:",")
        guard fields.count == 11 else {throw RaceError.invalid("SpeedAngle v4 trace rows require 11 fields; malformed rows cannot be skipped without changing synchronization.")}
        let numbers = fields.prefix(10).map{Double($0.trimmingCharacters(in:.whitespaces)).flatMap{$0.isFinite ? $0 : nil}}
        let time = Double(rows.count)/10,marker = fields[10].trimmingCharacters(in:.whitespaces).uppercased()
        guard marker == "F" || Int(marker).map({$0 >= 0 && $0 <= 255}) == true else {throw RaceError.invalid("Invalid SpeedAngle finish/sector marker.")}
        let valid = numbers[9] == 1 && numbers[0].map{abs($0) <= 90} == true && numbers[1].map{abs($0) <= 180} == true
        if !valid {invalid += 1}
        if marker == "F" {finishSamples.append(time)}
        func value(_ index:Int) -> String {numbers[index].map{String($0)} ?? "nan"}
        rows.append([String(time),valid ? value(0) : "nan",valid ? value(1) : "nan",valid ? value(6) : "nan",value(2),value(3),value(4),value(5),numbers[7] == -255 ? "nan" : value(7),value(8),value(9),marker == "F" ? "0" : marker,marker == "F" ? "1" : "0"])
        continue
      }
      if line.hasPrefix("#V=") {
        version = String(line.dropFirst(3)).trimmingCharacters(in:CharacterSet(charactersIn:"= "))
        unit = nil;name = "";date = "";sectorCount = nil;finishTimes = []
      } else if line.hasPrefix("#S=") {name = String(line.dropFirst(3)).trimmingCharacters(in:CharacterSet(charactersIn:"= "))}
      else if line.hasPrefix("#D=") {date = String(line.dropFirst(3)).trimmingCharacters(in:CharacterSet(charactersIn:"= "))}
      else if line.lowercased().hasPrefix("<trackplan") {sectorCount = attribute(line,"sectors").flatMap(Int.init)}
      else if line.lowercased().hasPrefix("<timer") {unit = attribute(line,"unit")?.uppercased();timer = true}
      else if line.lowercased() == "</timer>" {timer = false}
      else if timer,line.hasPrefix("#"),let comma = line.firstIndex(of:","),let sectorCount,
        Int(line[line.index(after:line.startIndex)..<comma]) == sectorCount,
        let time = Telemetry.parseTime(String(line[line.index(after:comma)...])),time.isFinite,time >= 0 {finishTimes.append(time)}
      else if line.lowercased().hasPrefix("<trace") {
        guard version?.hasPrefix("4.") == true,let unit,["KM/H","KMH","MILE/H","MPH"].contains(unit) else {throw RaceError.invalid("SpeedAngle support requires an R4 v4 trace and explicit KM/h or MILE/h speed units.")}
        declared = attribute(line,"pt").flatMap(Int.init);trace = true
      }
    }
    guard !trace,!result.isEmpty else {throw RaceError.invalid("No complete SpeedAngle v4 trace section found.")}
    return result
  }
}
