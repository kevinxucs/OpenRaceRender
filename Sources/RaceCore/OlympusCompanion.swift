import Foundation

/// Same-basename GPSLOG pairing. Failure leaves the independently usable sensors intact.
enum OlympusCompanion {
  static func candidates(for source:URL) throws -> [URL] {
    let fm = FileManager.default,parent = source.deletingLastPathComponent()
    var directories = [parent]
    if parent.lastPathComponent.caseInsensitiveCompare("SNSLOG") == .orderedSame {
      directories += try fm.contentsOfDirectory(at:parent.deletingLastPathComponent(),includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles).filter {
        $0.lastPathComponent.caseInsensitiveCompare("GPSLOG") == .orderedSame && (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true
      }
    }
    let name = source.deletingPathExtension().lastPathComponent
    return try directories.flatMap {directory in
      try fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isRegularFileKey],options:.skipsHiddenFiles).filter {
        $0.pathExtension.lowercased() == "log" && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true
      }
    }
  }
  static func attach(_ sensors:LoggerTextSession,to source:URL) -> LoggerTextSession {
    var result = sensors
    do {
      let files = try candidates(for:source)
      guard !files.isEmpty else {return result}
      guard files.count == 1 else {throw RaceError.invalid("More than one same-name GPSLOG companion exists; no GPS file was chosen.")}
      guard sensors.gpsClockCorrected,let epoch = sensors.epoch else {
        throw RaceError.invalid("Companion GPS requires one consistent $OLSNSGPSTIM camera/GPS clock correction.")
      }
      let bytes = try Telemetry.boundedData(files[0])
      guard let text = String(data:bytes,encoding:.utf8) ?? String(data:bytes,encoding:.isoLatin1) else {throw RaceError.invalid("Could not decode the GPSLOG companion.")}
      result = try merge(sensors,gps:text,sensorEpoch:epoch)
      result.warnings.removeAll{$0.contains("does not merge a GPSLOG companion")}
      result.warnings.append("Merged the matching GPSLOG companion using recorded UTC and the SNS camera/GPS correction. Time zero is the earliest combined sample; verify video synchronization. Keep both files together when moving this source.")
    } catch {result.warnings.append("Olympus GPS companion was not merged: "+error.localizedDescription)}
    return result
  }
  static func merge(_ sensors:LoggerTextSession,gps text:String,sensorEpoch:Double) throws -> LoggerTextSession {
    var records:[Double:[String]] = [:],previous = -Double.infinity
    func coordinate(_ value:String,_ direction:String,latitude:Bool) -> String {
      guard let n = Double(value),n.isFinite,n >= 0,[latitude ? "N" : "E",latitude ? "S" : "W"].contains(direction),
        n.truncatingRemainder(dividingBy:100) < 60 else {return "nan"}
      let degrees = floor(n/100)+n.truncatingRemainder(dividingBy:100)/60
      guard degrees <= (latitude ? 90 : 180) else {return "nan"}
      return String(degrees * (["S","W"].contains(direction) ? -1 : 1))
    }
    for raw in text.components(separatedBy:.newlines) {
      let line = raw.trimmingCharacters(in:.whitespacesAndNewlines)
      guard line.hasPrefix("$GPRMC,") || line.hasPrefix("$GNRMC,") else {continue}
      let parts = line.dropFirst().split(separator:"*",omittingEmptySubsequences:false)
      if parts.count > 1 {
        guard parts.count == 2,parts[1].count == 2,let checksum = UInt8(parts[1],radix:16),parts[0].utf8.reduce(UInt8(0),^) == checksum else {throw RaceError.invalid("GPSLOG RMC checksum mismatch.")}
      }
      let fields = parts[0].split(separator:",",omittingEmptySubsequences:false).map(String.init)
      guard fields.count >= 10,fields[9].count == 6,fields[9].utf8.allSatisfy({(48...57).contains($0)}),["A","V"].contains(fields[2]) else {throw RaceError.invalid("GPSLOG requires dated, complete active/void RMC sentences.")}
      let date = fields[9],year = "20"+date.suffix(2),month = date.dropFirst(2).prefix(2),day = date.prefix(2)
      let time = try OlympusSensorReader.timestamp(year+month+day,fields[1])
      guard time >= previous,records.count < 1_000_000 else {throw RaceError.invalid("GPSLOG RMC clock resets or exceeds one million samples.")}
      previous = time
      var row = [String](repeating:"nan",count:4)
      if fields[2] == "A" {
        row[0] = coordinate(fields[3],fields[4],latitude:true);row[1] = coordinate(fields[5],fields[6],latitude:false)
        if row[0] != "nan",row[1] != "nan" {
          if let speed = Double(fields[7]),speed.isFinite,speed >= 0 {row[2] = String(speed*0.514444)}
          if let heading = Double(fields[8]),heading.isFinite,(0...360).contains(heading) {row[3] = String(heading)}
        } else {row = [String](repeating:"nan",count:4)}
      }
      records[time] = row
    }
    let stamps = records.keys.sorted()
    guard stamps.count >= 2,let gpsEpoch = stamps.first,let last = stamps.last else {throw RaceError.invalid("GPSLOG has fewer than two dated RMC samples. GGA-only logs cannot establish a calendar date.")}
    let sensor = try Telemetry(text:sensors.text)
    guard sensor.count+stamps.count <= 1_000_000 else {throw RaceError.invalid("Combined Olympus data exceeds one million samples.")}
    guard max(sensorEpoch,gpsEpoch) < min(sensorEpoch+sensor.duration,last) else {throw RaceError.invalid("GPSLOG and sensors have no overlapping UTC interval. RMC dates must be in 2000–2099.")}
    let gpsHeaders = ["Time","Latitude (deg)","Longitude (deg)","Speed (m/s)","GPS heading (deg)"]
    let gpsRows = stamps.map{[String($0-gpsEpoch)]+records[$0]!}
    let gps = try Telemetry(text:LoggerText.csv(gpsHeaders,gpsRows))
    let epoch = min(sensorEpoch,gpsEpoch),sensorStart = sensorEpoch-epoch,gpsStart = gpsEpoch-epoch
    let intervals = zip(gps.times,gps.times.dropFirst()).map{$1-$0}.sorted()
    let gapLimit = max(2,intervals[intervals.count/2]*5)
    var times:[Double] = []
    for time in (sensor.times.map{$0+sensorStart}+gps.times.map{$0+gpsStart}).sorted() {
      if times.last.map({time-$0 > 0.000001}) ?? true {times.append(time)}
    }
    let sensorHeaders = sensor.recordedHeaders.filter{$0 != "Time"}
    func values(_ table:Telemetry,_ headers:[String],at time:Double,gap:Double? = nil) -> [String] {
      guard time >= -0.000001,time <= table.duration+0.000001 else {return headers.map{_ in "nan"}}
      let t = min(table.duration,max(0,time))
      if let gap {
        // Preserve missing-fix intervals and avoid bridging long receiver outages.
        var lo = 0,hi = table.times.count
        while lo < hi {let mid = (lo+hi)/2;if table.times[mid] < t {lo = mid+1} else {hi = mid}}
        if lo > 0,lo < table.times.count,abs(table.times[lo]-t) > 0.000001,abs(table.times[lo-1]-t) > 0.000001,table.times[lo]-table.times[lo-1] > gap {return headers.map{_ in "nan"}}
      }
      return headers.map{table.value($0,at:t).map{String($0)} ?? "nan"}
    }
    let rows = times.map{[String($0)]+values(sensor,sensorHeaders,at:$0-sensorStart)+values(gps,Array(gpsHeaders.dropFirst()),at:$0-gpsStart,gap:gapLimit)}
    var result = sensors;result.text = LoggerText.csv(["Time"]+sensorHeaders+gpsHeaders.dropFirst(),rows)
    result.epoch = epoch;result.count = rows.count;return result
  }
}
