import Foundation

public struct YouTubeHTTPResponse:Sendable {
  public var status:Int
  public var headers:[String:String]
  public var data:Data
  public init(status:Int,headers:[String:String] = [:],data:Data = Data()) {self.status = status;self.headers = headers;self.data = data}
  public func header(_ name:String) -> String? {headers.first(where:{$0.key.caseInsensitiveCompare(name) == .orderedSame})?.value}
}
public protocol YouTubeHTTPTransport:Sendable {
  func send(_ request:URLRequest) async throws -> YouTubeHTTPResponse
}
/// Redirects are refused so authorization headers cannot follow an unexpected Location.
private final class GoogleRedirectPolicy:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
  func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {completionHandler(nil)}
}
public final class GoogleHTTPTransport:YouTubeHTTPTransport,@unchecked Sendable {
  private let session:URLSession
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 120;configuration.httpShouldSetCookies = false
    configuration.urlCache = nil;configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration:configuration,delegate:GoogleRedirectPolicy(),delegateQueue:nil)
  }
  deinit {session.invalidateAndCancel()}
  public func send(_ request:URLRequest) async throws -> YouTubeHTTPResponse {
    let (data,response) = try await session.data(for:request)
    guard let response = response as? HTTPURLResponse,data.count <= 2*1024*1024 else {throw RaceError.invalid("Invalid or oversized Google API response.")}
    let headers = response.allHeaderFields.reduce(into:[String:String]()) {result,item in if let name = item.key as? String {result[name] = String(describing:item.value)}}
    return YouTubeHTTPResponse(status:response.statusCode,headers:headers,data:data)
  }
  public func invalidate() {session.invalidateAndCancel()}
}
