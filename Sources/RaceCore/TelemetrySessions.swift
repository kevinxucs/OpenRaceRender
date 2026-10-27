import Foundation

public struct TelemetrySessionInfo:Identifiable,Equatable,Sendable {
  public var id:Int
  public var name:String
  public var samples:Int
}

extension Telemetry {
  public static var unsupportedLoggerExtensions:[String] {LoggerText.unsupportedExtensions}
  public static func loggerConversionMessage(for ext:String) -> String {LoggerText.unsupported(ext).localizedDescription}
  public static func sessions(in url:URL,timeColumn:String? = nil) throws -> [TelemetrySessionInfo] {
    if CameraTelemetry.extensions.contains(url.pathExtension.lowercased()) {return [TelemetrySessionInfo(id:1,name:"Camera",samples:0)]}
    let data = try boundedData(url)
    if url.pathExtension.lowercased() == "rcz" {return try RCZReader.sessionNames(data).enumerated().map{TelemetrySessionInfo(id:$0.offset+1,name:$0.element,samples:0)}}
    return try textSessions(data,url:url,timeColumn:timeColumn).enumerated().map{TelemetrySessionInfo(id:$0.offset+1,name:$0.element.name,samples:$0.element.count)}
  }
  static func boundedData(_ url:URL) throws -> Data {
    let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
    guard size <= 512*1024*1024 else {throw RaceError.invalid("Telemetry file is larger than 512 MB.")}
    return try Data(contentsOf:url)
  }
  static func textSessions(_ data:Data,url:URL,timeColumn:String?) throws -> [LoggerTextSession] {
    let ext = url.pathExtension.lowercased()
    if LoggerText.unsupportedExtensions.contains(ext) {throw LoggerText.unsupported(ext)}
    if ext == "json" {return try LoggerText.gutma(data)}
    if ext == "fit" || (data.count >= 12 && String(data:data[8..<12],encoding:.ascii) == ".FIT") {
      var base = 0,result:[LoggerTextSession] = []
      while base < data.count {
        guard data.count-base >= 12 else {throw RaceError.invalid("Truncated FIT session.")}
        let size = Int(data[base])+Int(data.u32(base+4))+2
        guard size >= 14,size <= data.count-base else {throw RaceError.invalid("Invalid FIT session length.")}
        let csv = try FITReader.csv(Data(data[base..<base+size]));var session = LoggerText.split(csv)[0]
        session.name = "Activity \(result.count+1)";result.append(session);base += size
      }
      return result
    }
    guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) ?? String(data:data,encoding:.isoLatin1) else {throw RaceError.invalid("Could not decode telemetry text.")}
    if ext == "msl" {return try LoggerText.msl(text)}
    if ["gpx","tcx"].contains(ext) || text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("<?xml") {return try TelemetryFormats.xmlSessions(data)}
    let normalized = try TelemetryFormats.csv(from:data,text:text,extension:ext)
    return LoggerText.split(normalized,timeColumn:timeColumn)
  }
}
