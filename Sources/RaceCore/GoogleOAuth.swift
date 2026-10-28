import Foundation
import CryptoKit
import Security

public struct GoogleDesktopClient:Codable,Equatable,Sendable {
  public var id:String
  public var secret:String?
  public init(id:String,secret:String? = nil) {self.id = id;self.secret = secret}
  public static func read(_ data:Data) throws -> Self {
    guard data.count <= 65_536,let json = try JSONSerialization.jsonObject(with:data) as? [String:Any],let installed = json["installed"] as? [String:Any],let id = installed["client_id"] as? String else {throw RaceError.invalid("Choose Google OAuth credentials for a Desktop app (installed client JSON).")}
    let value = Self(id:id,secret:installed["client_secret"] as? String);try value.validate();return value
  }
  public func validate() throws {
    guard id.hasSuffix(".apps.googleusercontent.com"),id.utf8.count <= 256,!id.contains(where:\.isWhitespace),secret.map({$0.utf8.count <= 512 && !$0.contains(where:\.isWhitespace)}) ?? true else {throw RaceError.invalid("Invalid Google Desktop OAuth client credentials.")}
  }
}
public struct GoogleOAuthToken:Codable,Equatable,Sendable {
  public var accessToken:String
  public var refreshToken:String?
  public var expiresAt:Date
  public init(accessToken:String,refreshToken:String?,expiresAt:Date) {self.accessToken = accessToken;self.refreshToken = refreshToken;self.expiresAt = expiresAt}
  public var needsRefresh:Bool {expiresAt.timeIntervalSinceNow < 90}
}
public struct GooglePKCE:Sendable {
  public var verifier:String
  public var state:String
  public var challenge:String {Self.base64url(Data(SHA256.hash(data:Data(verifier.utf8))))}
  public init() throws {verifier = try Self.random();state = try Self.random()}
  static func base64url(_ data:Data) -> String {data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
  static func random() throws -> String {
    var bytes = [UInt8](repeating:0,count:32)
    guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else {throw RaceError.invalid("Could not generate a secure Google sign-in request.")}
    return base64url(Data(bytes))
  }
}
public enum GoogleOAuth {
  public static let scope = "https://www.googleapis.com/auth/youtube.upload"
  public static func authorizationURL(client:GoogleDesktopClient,redirect:URL,pkce:GooglePKCE) throws -> URL {
    try client.validate()
    guard redirect.scheme == "http",redirect.host == "127.0.0.1",redirect.port != nil,redirect.path == "/oauth2callback" else {throw RaceError.invalid("Google Desktop sign-in needs a loopback redirect.")}
    var url = URLComponents(string:"https://accounts.google.com/o/oauth2/v2/auth")!
    url.queryItems = ["client_id":client.id,"redirect_uri":redirect.absoluteString,"response_type":"code","scope":scope,"code_challenge":pkce.challenge,"code_challenge_method":"S256","state":pkce.state,"access_type":"offline","prompt":"select_account consent"].sorted{$0.key < $1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
    return url.url!
  }
  static func form(_ values:[String:String]) -> Data {
    var url = URLComponents();url.queryItems = values.sorted{$0.key < $1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
    return Data((url.percentEncodedQuery ?? "").replacingOccurrences(of:"+",with:"%2B").utf8)
  }
  public static func exchange(code:String,client:GoogleDesktopClient,redirect:URL,pkce:GooglePKCE,transport:any YouTubeHTTPTransport) async throws -> GoogleOAuthToken {
    try client.validate()
    return try await token(["client_id":client.id,"client_secret":client.secret ?? "","code":code,"redirect_uri":redirect.absoluteString,"code_verifier":pkce.verifier,"grant_type":"authorization_code"],refresh:nil,transport:transport)
  }
  public static func refresh(_ previous:GoogleOAuthToken,client:GoogleDesktopClient,transport:any YouTubeHTTPTransport) async throws -> GoogleOAuthToken {
    try client.validate()
    guard let refresh = previous.refreshToken,!refresh.isEmpty else {throw RaceError.invalid("Google authorization expired. Sign in again.")}
    return try await token(["client_id":client.id,"client_secret":client.secret ?? "","refresh_token":refresh,"grant_type":"refresh_token"],refresh:refresh,transport:transport)
  }
  static func token(_ fields:[String:String],refresh:String?,transport:any YouTubeHTTPTransport) async throws -> GoogleOAuthToken {
    var request = URLRequest(url:URL(string:"https://oauth2.googleapis.com/token")!);request.httpMethod = "POST"
    var values = fields
    if values["client_secret"]?.isEmpty == true {values.removeValue(forKey:"client_secret")}
    request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type");request.httpBody = form(values)
    let response = try await transport.send(request)
    guard response.status == 200,let json = try JSONSerialization.jsonObject(with:response.data) as? [String:Any],let access = json["access_token"] as? String,!access.isEmpty,access.utf8.count <= 16_384,access.utf8.allSatisfy({(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95,126,43,47,61].contains($0)}),
      let expires = json["expires_in"] as? Double,expires.isFinite,expires > 0,expires <= 86400,
      (json["token_type"] as? String)?.lowercased() == "bearer" else {throw RaceError.invalid("Google authorization was refused or expired (HTTP \(response.status)). Check the Desktop client and sign in again.")}
    if let scope = json["scope"] as? String,!scope.split(separator:" ").contains(Substring(Self.scope)) {throw RaceError.invalid("Google did not grant the YouTube upload scope.")}
    return GoogleOAuthToken(accessToken:access,refreshToken:(json["refresh_token"] as? String) ?? refresh,expiresAt:Date().addingTimeInterval(expires))
  }
}
