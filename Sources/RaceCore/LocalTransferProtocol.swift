import Foundation

struct TransferHTTPHead {
  var method:String;var route:String;var name:String?;var length:Int64
  static let delimiter = Data([13,10,13,10])
  static func parse(_ bytes:Data,token:String) throws -> Self {
    guard bytes.count <= 16_384,let text = String(data:bytes,encoding:.utf8) else {throw RaceError.invalid("Invalid HTTP header.")}
    let lines = text.components(separatedBy:"\r\n"),request = lines[0].split(separator:" ")
    guard request.count == 3,["HTTP/1.1","HTTP/1.0"].contains(String(request[2])),request[1].hasPrefix("/"),!request[1].hasPrefix("//"),
      let url = URLComponents(string:"http://localhost"+request[1]) else {throw RaceError.invalid("Invalid HTTP request.")}
    let tokens = url.queryItems?.filter{$0.name == "token"} ?? []
    guard tokens.count == 1,tokens[0].value == token else {throw RaceError.invalid("Invalid pairing link.")}
    var headers:[String:String] = [:]
    for line in lines.dropFirst() where !line.isEmpty {
      guard let colon = line.firstIndex(of:":") else {throw RaceError.invalid("Invalid HTTP field.")}
      let key = line[..<colon].lowercased(),value = line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
      guard headers[key] == nil else {throw RaceError.invalid("Duplicate HTTP field.")};headers[key] = value
    }
    guard headers["transfer-encoding"] == nil else {throw RaceError.invalid("Chunked HTTP uploads are unsupported. Send a file with Content-Length.")}
    let method = String(request[0]),route = url.path
    let length:Int64
    if let size = headers["content-length"] {
      guard !size.isEmpty,size.allSatisfy(\.isNumber),let value = Int64(size),value >= 0 else {throw RaceError.invalid("Invalid Content-Length.")};length = value
    } else {length = 0}
    guard length <= TransferStore.maximumFileBytes else {throw RaceError.invalid("File exceeds the 64 GiB upload limit.")}
    if method == "PUT",route == "/upload" {
      let names = url.queryItems?.filter{$0.name == "name"} ?? []
      guard names.count == 1,let name = names[0].value,length > 0 else {throw RaceError.invalid("Upload requires a filename and a positive Content-Length.")}
      try TransferStore.validate(name)
      return Self(method:method,route:route,name:name,length:length)
    }
    guard (method == "GET" && route == "/") || (method == "POST" && route == "/finish"),length == 0 else {throw RaceError.invalid("Unknown transfer request.")}
    return Self(method:method,route:route,length:0)
  }
}

/// Queue-confined, private staging. A completed transfer publishes a fresh folder atomically.
final class TransferStore {
  static let maximumFileBytes:Int64 = 64*1024*1024*1024
  static let maximumSessionBytes:Int64 = 128*1024*1024*1024
  static let extensions = Set(Telemetry.supportedExtensions+["mp4","mov","m4v","360","mp3","wav","m4a","aac","png","jpg","jpeg","tif","bmp"])
  let destination:URL;let staging:URL
  var active:[UUID:(name:String,size:Int64,handle:FileHandle,url:URL,written:Int64)] = [:]
  var completed:[String:URL] = [:]
  var reserved:Int64 = 0
  var published = false
  init(destination:URL) throws {
    var directory:ObjCBool = false
    guard FileManager.default.fileExists(atPath:destination.path,isDirectory:&directory),directory.boolValue else {throw RaceError.invalid("Choose an existing destination folder.")}
    self.destination = destination
    staging = destination.appendingPathComponent(".OpenRaceRender-receive-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  }
  static func validate(_ name:String) throws {
    guard !name.isEmpty,name.utf8.count <= 255,!name.hasPrefix("."),!name.contains("/"),!name.contains("\\"),
      !name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
      extensions.contains((name as NSString).pathExtension.lowercased()) else {throw RaceError.invalid("Choose a supported media or telemetry filename without folders.")}
  }
  func begin(_ name:String,size:Int64,id:UUID) throws {
    try Self.validate(name)
    let canonical = name.precomposedStringWithCanonicalMapping.lowercased()
    guard !published,size > 0,size <= Self.maximumFileBytes,reserved <= Self.maximumSessionBytes-size,
      active.count+completed.count < 64,!completed.keys.contains(where:{$0.precomposedStringWithCanonicalMapping.lowercased() == canonical}),
      !active.values.contains(where:{$0.name.precomposedStringWithCanonicalMapping.lowercased() == canonical}) else {throw RaceError.invalid("Duplicate filename, completed transfer, or upload limit exceeded.")}
    let url = staging.appendingPathComponent(name)
    guard FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw RaceError.invalid("Could not create the incoming file.")}
    do {active[id] = (name,size,try FileHandle(forWritingTo:url),url,0);reserved += size}
    catch {try? FileManager.default.removeItem(at:url);throw error}
  }
  func write(_ data:Data,id:UUID) throws -> (Int64,Int64) {
    guard var file = active[id],Int64(data.count) <= file.size-file.written else {throw RaceError.invalid("Unexpected upload length.")}
    try file.handle.write(contentsOf:data);file.written += Int64(data.count);active[id] = file
    return (file.written,file.size)
  }
  func finishFile(_ id:UUID) throws {
    guard let file = active[id],file.written == file.size else {throw RaceError.invalid("Incomplete upload.")}
    try file.handle.synchronize();try file.handle.close();active.removeValue(forKey:id);completed[file.name] = file.url
  }
  func abort(_ id:UUID) {
    guard let file = active.removeValue(forKey:id) else {return}
    try? file.handle.close();try? FileManager.default.removeItem(at:file.url);reserved -= file.size
  }
  func commit() throws -> [URL] {
    guard !published,active.isEmpty,!completed.isEmpty else {throw RaceError.invalid("Finish all selected files before completing the transfer.")}
    let target = destination.appendingPathComponent("Received-"+ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")+"-"+String(UUID().uuidString.prefix(8)),isDirectory:true)
    try FileManager.default.moveItem(at:staging,to:target);published = true
    return completed.keys.sorted().map{target.appendingPathComponent($0)}
  }
  func cancel() {
    for id in Array(active.keys) {abort(id)}
    if !published {try? FileManager.default.removeItem(at:staging)}
  }
}
