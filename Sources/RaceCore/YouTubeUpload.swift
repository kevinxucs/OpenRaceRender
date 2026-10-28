import Foundation
import CryptoKit

public enum YouTubePrivacy:String,Codable,CaseIterable,Sendable {case `private`,unlisted,`public`}
public struct YouTubeVideoDraft:Codable,Equatable,Sendable {
  public var title:String
  public var description:String = ""
  public var tags:[String] = []
  public var categoryID:String = "2"
  public var privacy:YouTubePrivacy = .private
  public var madeForKids:Bool?
  public var notifySubscribers = false
  public init(title:String) {self.title = title}
  public func validate() throws {
    guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count <= 100,!title.contains("<"),!title.contains(">") else {throw RaceError.invalid("Enter a title of 1–100 characters without angle brackets.")}
    guard description.utf8.count <= 5000,!description.contains("<"),!description.contains(">") else {throw RaceError.invalid("Description must be at most 5000 UTF-8 bytes and contain no angle brackets.")}
    guard !tags.contains(where:{$0.isEmpty}),tags.reduce(0,{$0+$1.count+1+($1.contains(" ") ? 2 : 0)}) <= 500 else {throw RaceError.invalid("Tags must fit within YouTube’s 500-character limit.")}
    guard !categoryID.isEmpty,categoryID.allSatisfy(\.isNumber),categoryID.count <= 3 else {throw RaceError.invalid("Choose a YouTube category.")}
    guard madeForKids != nil else {throw RaceError.invalid("Choose the intended audience before uploading.")}
  }
  func data() throws -> Data {
    try validate()
    let json:[String:Any] = ["snippet":["title":title,"description":description,"tags":tags,"categoryId":categoryID],"status":["privacyStatus":privacy.rawValue,"selfDeclaredMadeForKids":madeForKids!]]
    return try JSONSerialization.data(withJSONObject:json)
  }
}
public struct YouTubeFileIdentity:Codable,Equatable,Sendable {
  public var path:String;public var size:Int64;public var modified:Double;public var edgesHash:String
  public static func read(_ url:URL) throws -> Self {
    let values = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey])
    guard values.isRegularFile == true,let size = values.fileSize,size > 0,size <= 256_000_000_000,let date = values.contentModificationDate,
      ["mp4","mov","m4v","webm"].contains(url.pathExtension.lowercased()) else {throw RaceError.invalid("Choose a completed MP4, MOV, M4V or WebM video, up to 256 GB.")}
    let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
    var bytes = try file.read(upToCount:65_536) ?? Data()
    if size > 65_536 {try file.seek(toOffset:UInt64(max(65_536,size-65_536)));bytes += try file.read(upToCount:65_536) ?? Data()}
    return Self(path:url.standardizedFileURL.path,size:Int64(size),modified:date.timeIntervalSinceReferenceDate,edgesHash:SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined())
  }
  public func validate() throws {
    guard try Self.read(URL(fileURLWithPath:path)) == self else {throw RaceError.invalid("The video changed since this upload began. Choose a new upload; the saved resume session cannot be used with a different file.")}
  }
}
public struct YouTubePendingUpload:Codable,Equatable,Sendable {
  public var url:URL
  public var file:YouTubeFileIdentity
  public var draft:YouTubeVideoDraft
  public var chunkSize:Int
}
public final class YouTubeUploader:Sendable {
  let transport:any YouTubeHTTPTransport
  let sleep:@Sendable (Double) async throws -> Void
  public init(transport:any YouTubeHTTPTransport) {
    self.transport = transport;sleep = {seconds in try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
  }
  init(transport:any YouTubeHTTPTransport,sleep:@escaping @Sendable(Double) async throws -> Void) {self.transport = transport;self.sleep = sleep}
  static func validUploadURL(_ url:URL) -> Bool {
    guard url.scheme == "https",url.user == nil,url.password == nil,url.fragment == nil,url.port == nil || url.port == 443,
      let host = url.host?.lowercased(),host == "www.googleapis.com" || host == "youtube.googleapis.com" else {return false}
    return url.path.hasPrefix("/upload/youtube/") || url.path.hasPrefix("/resumable/upload/")
  }
  public func begin(file:URL,draft:YouTubeVideoDraft,token:String,chunkSize:Int = 16*1024*1024) async throws -> YouTubePendingUpload {
    try draft.validate()
    guard chunkSize >= 262_144,chunkSize <= 64*1024*1024,chunkSize % 262_144 == 0 else {throw RaceError.invalid("Upload chunks must be 256 KiB multiples, between 256 KiB and 64 MiB.")}
    let identity = try YouTubeFileIdentity.read(file)
    let endpoint = "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers="+(draft.notifySubscribers ? "true" : "false")
    var request = Self.request(URL(string:endpoint)!,token:token);request.httpMethod = "POST";request.httpBody = try draft.data()
    request.setValue("application/json; charset=UTF-8",forHTTPHeaderField:"Content-Type")
    request.setValue(String(identity.size),forHTTPHeaderField:"X-Upload-Content-Length");request.setValue(Self.mime(file),forHTTPHeaderField:"X-Upload-Content-Type")
    let response = try await transport.send(request)
    guard [200,201].contains(response.status) else {throw Self.apiError(response)}
    guard let location = response.header("Location"),let url = URL(string:location),Self.validUploadURL(url) else {throw RaceError.invalid("YouTube returned an unexpected resumable upload address.")}
    return YouTubePendingUpload(url:url,file:identity,draft:draft,chunkSize:chunkSize)
  }
  static func mime(_ url:URL) -> String {url.pathExtension.lowercased() == "mov" ? "video/quicktime" : url.pathExtension.lowercased() == "webm" ? "video/webm" : "video/mp4"}
  static func request(_ url:URL,token:String) -> URLRequest {
    var request = URLRequest(url:url);request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization");return request
  }
  static func apiError(_ response:YouTubeHTTPResponse) -> RaceError {
    if response.status == 401 {return .invalid("YouTube authorization expired or was revoked. Sign in again; the upload can then be resumed.")}
    if response.status == 404 || response.status == 410 {return .invalid("This YouTube upload session expired. Discard its local resume state and start a new upload.")}
    return .invalid("YouTube returned HTTP \(response.status). Check API access, quota and channel eligibility before resuming.")
  }
  static func videoID(_ response:YouTubeHTTPResponse) throws -> String {
    guard let json = try JSONSerialization.jsonObject(with:response.data) as? [String:Any],let id = json["id"] as? String,!id.isEmpty,id.count <= 128,id.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")}) else {throw RaceError.invalid("YouTube completed the upload without a valid video ID. Resume to check its status before starting another upload.")};return id
  }
  static func acknowledged(_ response:YouTubeHTTPResponse,size:Int64) throws -> Int64 {
    guard let range = response.header("Range") else {return 0}
    guard range.hasPrefix("bytes=0-"),let last = Int64(range.dropFirst(8)),last >= 0,last < size else {throw RaceError.invalid("YouTube returned an invalid acknowledged byte range.")};return last+1
  }
  func delay(_ response:YouTubeHTTPResponse?,attempt:Int) async throws {
    var seconds = pow(2,Double(attempt))
    if let value = response?.header("Retry-After") {
      if let number = Double(value),number.isFinite {seconds = max(seconds,number)}
      else {let date = DateFormatter();date.locale = Locale(identifier:"en_US_POSIX");date.timeZone = TimeZone(secondsFromGMT:0);date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz";if let target = date.date(from:value) {seconds = max(seconds,target.timeIntervalSinceNow)}}
    }
    guard seconds <= 3600 else {throw RaceError.invalid("YouTube requested a long retry delay. Pause and resume later.")}
    try await sleep(max(0,seconds))
  }
  public func upload(_ pending:YouTubePendingUpload,token:@escaping @Sendable () async throws -> String,progress:@escaping @Sendable (Int64,Int64)->Void) async throws -> String {
    guard Self.validUploadURL(pending.url),pending.chunkSize >= 262_144,pending.chunkSize <= 64*1024*1024,pending.chunkSize % 262_144 == 0 else {throw RaceError.invalid("Invalid saved YouTube upload session.")}
    try pending.file.validate();try pending.draft.validate()
    let file = try FileHandle(forReadingFrom:URL(fileURLWithPath:pending.file.path));defer {try? file.close()}
    var offset:Int64 = 0,query = true,attempt = 0
    while true {
      try Task.checkCancellation();try pending.file.validate()
      var request = Self.request(pending.url,token:try await token());request.httpMethod = "PUT"
      if query {request.httpBody = Data();request.setValue("0",forHTTPHeaderField:"Content-Length");request.setValue("bytes */\(pending.file.size)",forHTTPHeaderField:"Content-Range")}
      else {
        let count = Int(min(Int64(pending.chunkSize),pending.file.size-offset))
        guard count > 0 else {throw RaceError.invalid("YouTube acknowledged all bytes without a completed video. Resume later to check processing status.")}
        try file.seek(toOffset:UInt64(offset));let bytes = try file.read(upToCount:count) ?? Data()
        guard bytes.count == count else {throw RaceError.invalid("Video was truncated during upload.")}
        request.httpBody = bytes;request.setValue(String(count),forHTTPHeaderField:"Content-Length")
        request.setValue(Self.mime(URL(fileURLWithPath:pending.file.path)),forHTTPHeaderField:"Content-Type")
        request.setValue("bytes \(offset)-\(offset+Int64(count)-1)/\(pending.file.size)",forHTTPHeaderField:"Content-Range")
      }
      let response:YouTubeHTTPResponse
      do {response = try await transport.send(request)}
      catch {
        try Task.checkCancellation();guard attempt < 5 else {throw RaceError.invalid("Network transfer interrupted. The saved upload can be resumed.")}
        attempt += 1;try await delay(nil,attempt:attempt);query = true;continue
      }
      if [200,201].contains(response.status) {let id = try Self.videoID(response);progress(pending.file.size,pending.file.size);return id}
      if response.status == 429 || (500...599).contains(response.status) {
        guard attempt < 5 else {throw Self.apiError(response)};attempt += 1;try await delay(response,attempt:attempt);query = true;continue
      }
      guard response.status == 308 else {throw Self.apiError(response)}
      let next = try Self.acknowledged(response,size:pending.file.size)
      if !query,next <= offset {
        guard attempt < 5 else {throw RaceError.invalid("YouTube is not acknowledging new bytes. Pause and resume later.")}
        attempt += 1;try await delay(response,attempt:attempt);query = true;continue
      }
      if !query {guard next <= offset+Int64(request.httpBody?.count ?? 0) else {throw RaceError.invalid("YouTube acknowledged bytes beyond the submitted chunk.")}}
      guard next >= offset else {throw RaceError.invalid("YouTube’s acknowledged upload position moved backwards. Check the saved session before resuming.")}
      if next > offset {attempt = 0}
      offset = next;query = false;progress(offset,pending.file.size)
      if response.header("Retry-After") != nil {try await delay(response,attempt:0)}
    }
  }
}
