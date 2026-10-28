import Foundation

/// Self-identifying v5 NMEA blocks, not a decoder for unrelated MOFF binary indexes.
enum SonyGPSReader {
  static func sessions(_ bytes:Data,container:Bool) throws -> [LoggerTextSession] {
    guard bytes.count <= 64*1024*1024 else {throw RaceError.invalid("Sony GPS sidecars must be smaller than 64 MB.")}
    if container, !bytes.starts(with:Data("MOFF8".utf8)) {throw RaceError.invalid("Sony GPS import requires MOFF8 with identified v5 WGS-84 NMEA blocks.")}
    // Binary framing is not interpreted. Only bounded printable runs can supply text.
    var text = ""
    if container {
      guard let start = bytes.range(of:Data("@Sonygps/".utf8)) else {throw RaceError.invalid("This MOFF has no identified Sony GPS text block.")}
      var printable = Data()
      for byte in bytes[start.lowerBound...] {
        if byte == 10 || byte == 13 || byte == 9 || (32...126).contains(byte) {printable.append(byte)}
        else {
          if !printable.isEmpty {text += String(decoding:printable,as:UTF8.self)+"\n!binary-boundary\n";printable.removeAll(keepingCapacity:true)}
        }
      }
      text += String(decoding:printable,as:UTF8.self)
    } else {
      guard let decoded = String(data:bytes,encoding:.utf8) else {throw RaceError.invalid("Sony recording log must be UTF-8 text.")};text = decoded
    }
    var sessions:[LoggerTextSession] = [],recording:Double?,rows:[String] = [],hasOptions = false
    func finish() throws {
      guard let recording else {return}
      let records = try DatedRMCReader.read(rows.joined(separator:"\n")),stamps = records.keys.sorted()
      guard stamps.count >= 2,let first = stamps.first else {throw RaceError.invalid("A Sony recording block needs at least two dated RMC samples; binary/undated GPS variants are not supported.")}
      let output = stamps.map{[String(LoggerText.relativeTime($0,from:first))]+records[$0]!}
      var warnings = ["Sony v5 GPS import reads identified dated RMC text, not the binary image/video index. GGA-only altitude and other sentence channels are not imported. First GPS sample is time zero; synchronize against the video."]
      if hasOptions {warnings.append("Sony GPS option/trim metadata is not interpreted. All recorded RMC samples in this block remain available; verify video bounds manually.")}
      let delta = first-recording
      if abs(delta) > 0.001 {warnings.append(String(format:"Sony header recording time differs from the first GPS sample by %.3f seconds; no video timing offset was inferred.",delta))}
      sessions.append(LoggerTextSession(name:"Sony recording \(sessions.count+1)",text:LoggerText.csv(DatedRMCReader.headers,output),epoch:first,count:output.count,warnings:warnings))
      rows = [];hasOptions = false
    }
    for raw in text.components(separatedBy:.newlines) {
      let line = raw.replacingOccurrences(of:"\u{FEFF}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
      if line.hasPrefix("@Sonygps/") {
        try finish();recording = nil
        let fields = line.split(separator:"/",omittingEmptySubsequences:false)
        guard fields.count == 5,fields[1] == "ver5.0",fields[2] == "wgs-84",fields[4].isEmpty else {throw RaceError.invalid("Unsupported Sony GPS header; expected ver5.0/wgs-84/YYYYMMDDHHMMSS.fraction/.")}
        let stamp = String(fields[3]);guard stamp.count >= 14 else {throw RaceError.invalid("Truncated Sony recording timestamp.")}
        recording = try LoggerText.utcTimestamp(String(stamp.prefix(8)),String(stamp.dropFirst(8)))
      } else if recording != nil,line.hasPrefix("@Sonygpsoption/") {hasOptions = true}
      else if recording != nil,line.hasPrefix("$") {rows.append(line)}
      else if recording != nil,!line.isEmpty {try finish();recording = nil}
    }
    try finish()
    guard !sessions.isEmpty else {throw RaceError.invalid("No identified Sony v5 GPS recording blocks found; this MOFF may contain only a video index or an unsupported GPS layout.")}
    return sessions
  }
}
