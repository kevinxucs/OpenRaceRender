import Foundation

/// Dated GP/GN RMC records; void fixes retain their sampling clock.
enum DatedRMCReader {
  static let headers = ["Time","Latitude (deg)","Longitude (deg)","Speed (m/s)","GPS heading (deg)"]
  static func read(_ text:String) throws -> [Double:[String]] {
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
        guard parts.count == 2,parts[1].count == 2,let checksum = UInt8(parts[1],radix:16),parts[0].utf8.reduce(UInt8(0),^) == checksum else {throw RaceError.invalid("GPS RMC checksum mismatch.")}
      }
      let fields = parts[0].split(separator:",",omittingEmptySubsequences:false).map(String.init)
      guard fields.count >= 10,fields[9].count == 6,fields[9].utf8.allSatisfy({(48...57).contains($0)}),["A","V"].contains(fields[2]) else {throw RaceError.invalid("GPS requires dated, complete active/void RMC sentences.")}
      let date = fields[9],year = "20"+date.suffix(2),month = date.dropFirst(2).prefix(2),day = date.prefix(2)
      let time = try LoggerText.utcTimestamp(year+month+day,fields[1])
      guard time >= previous,records.count < 1_000_000 else {throw RaceError.invalid("GPS RMC clock resets or exceeds one million samples.")}
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
    return records
  }
}
