import XCTest
@testable import RaceCore

actor ScriptedGoogle:YouTubeHTTPTransport {
  enum Step {case response(YouTubeHTTPResponse),failure}
  var steps:[Step];var requests:[URLRequest] = []
  init(_ steps:[Step]) {self.steps = steps}
  func send(_ request:URLRequest) async throws -> YouTubeHTTPResponse {
    requests.append(request)
    guard !steps.isEmpty else {throw RaceError.invalid("No scripted response")}
    switch steps.removeFirst() {case .response(let value):return value;case .failure:throw URLError(.networkConnectionLost)}
  }
}
final class YouTubeTests:XCTestCase {
  let upload = "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=original-test"
  func response(_ status:Int,_ headers:[String:String] = [:],_ json:[String:Any]? = nil) -> ScriptedGoogle.Step {
    .response(YouTubeHTTPResponse(status:status,headers:headers,data:json.flatMap{try? JSONSerialization.data(withJSONObject:$0)} ?? Data()))
  }
  func file(size:Int = 600_000) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    try Data((0..<size).map{UInt8($0 % 251)}).write(to:url);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func draft() -> YouTubeVideoDraft {var draft = YouTubeVideoDraft(title:"Original synthetic upload");draft.madeForKids = false;return draft}
  func testPKCEClientImportAndLeastScopeAuthorization() throws {
    var pkce = try GooglePKCE();XCTAssertEqual(pkce.verifier.count,43);XCTAssertNotEqual(pkce.state,pkce.verifier)
    pkce.verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    XCTAssertEqual(pkce.challenge,"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let client = try GoogleDesktopClient.read(JSONSerialization.data(withJSONObject:["installed":["client_id":"test.apps.googleusercontent.com","client_secret":"test+secret","auth_uri":"https://untrusted.invalid"]]))
    let url = try GoogleOAuth.authorizationURL(client:client,redirect:URL(string:"http://127.0.0.1:12345/oauth2callback")!,pkce:pkce)
    XCTAssertEqual(url.host,"accounts.google.com")
    let query = try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems)
    XCTAssertEqual(query.first(where:{$0.name == "scope"})?.value,GoogleOAuth.scope)
    XCTAssertEqual(query.first(where:{$0.name == "code_challenge_method"})?.value,"S256")
    XCTAssertThrowsError(try GoogleOAuth.authorizationURL(client:client,redirect:URL(string:"http://other.invalid/oauth2callback")!,pkce:pkce))
    XCTAssertThrowsError(try GoogleDesktopClient.read(Data("{\"web\":{}}".utf8)))
  }
  func testTokenExchangeRefreshAndRefusedScopes() async throws {
    let transport = ScriptedGoogle([response(200,[:],["access_token":"test-access","refresh_token":"test-refresh","token_type":"Bearer","expires_in":3600,"scope":GoogleOAuth.scope]),response(200,[:],["access_token":"renewed","token_type":"Bearer","expires_in":3600])])
    let client = GoogleDesktopClient(id:"test.apps.googleusercontent.com",secret:"a+b&c"),pkce = try GooglePKCE()
    let token = try await GoogleOAuth.exchange(code:"test+code",client:client,redirect:URL(string:"http://127.0.0.1:12345/oauth2callback")!,pkce:pkce,transport:transport)
    XCTAssertEqual(token.refreshToken,"test-refresh");XCTAssertFalse(token.needsRefresh)
    let renewed = try await GoogleOAuth.refresh(token,client:client,transport:transport)
    XCTAssertEqual(renewed.refreshToken,"test-refresh");XCTAssertEqual(renewed.accessToken,"renewed")
    let requests = await transport.requests
    XCTAssertEqual(requests[0].url?.host,"oauth2.googleapis.com")
    let body = String(decoding:try XCTUnwrap(requests[0].httpBody),as:UTF8.self)
    XCTAssertTrue(body.contains("a%2Bb%26c"));XCTAssertTrue(body.contains("test%2Bcode"));XCTAssertTrue(body.contains("code_verifier="))
    let denied = ScriptedGoogle([response(200,[:],["access_token":"test","token_type":"Bearer","expires_in":3600,"scope":"read-only"])])
    do {_ = try await GoogleOAuth.refresh(token,client:client,transport:denied);XCTFail("Wrong scope accepted")} catch {}
  }
  func testResumableChunksQueryServerPositionAfterFailure() async throws {
    let url = try file(),bytes = try Data(contentsOf:url)
    let transport = ScriptedGoogle([
      response(200,["Location":upload]),response(308),response(308,["Range":"bytes=0-262143"]),.failure,response(500),
      response(308,["Range":"bytes=0-299999"]),response(308,["Range":"bytes=0-562143"]),response(201,[:],["id":"original_test_id"])])
    let uploader = YouTubeUploader(transport:transport,sleep:{_ in})
    let pending = try await uploader.begin(file:url,draft:draft(),token:"test-access",chunkSize:262_144)
    let id = try await uploader.upload(pending,token:{"test-access"},progress:{_,_ in})
    XCTAssertEqual(id,"original_test_id")
    let requests = await transport.requests
    XCTAssertEqual(requests.count,8)
    XCTAssertEqual(requests[0].value(forHTTPHeaderField:"X-Upload-Content-Length"),"600000")
    let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with:requests[0].httpBody!) as? [String:Any])
    XCTAssertEqual((metadata["status"] as? [String:Any])?["privacyStatus"] as? String,"private")
    XCTAssertEqual(requests[1].value(forHTTPHeaderField:"Content-Range"),"bytes */600000")
    XCTAssertEqual(requests[5].value(forHTTPHeaderField:"Content-Range"),"bytes */600000")
    XCTAssertEqual(requests[6].value(forHTTPHeaderField:"Content-Range"),"bytes 300000-562143/600000")
    XCTAssertEqual(requests[6].httpBody,Data(bytes[300000..<562144]))
    XCTAssertEqual(requests[7].httpBody,Data(bytes[562144..<600000]))
  }
  func testResumeDetectsAlreadyCompletedAndChangedOrUnsafeFiles() async throws {
    let url = try file(),transport = ScriptedGoogle([response(200,["Location":upload]),response(200,[:],["id":"already_done"])])
    let uploader = YouTubeUploader(transport:transport,sleep:{_ in})
    var pending = try await uploader.begin(file:url,draft:draft(),token:"test")
    let completed = try await uploader.upload(pending,token:{"test"},progress:{_,_ in});XCTAssertEqual(completed,"already_done")
    pending.url = URL(string:"https://untrusted.invalid/upload/youtube/v3/videos")!
    do {_ = try await uploader.upload(pending,token:{XCTFail("Token sent to untrusted host");return "test"},progress:{_,_ in});XCTFail("Unsafe URL accepted")} catch {}
    pending.url = URL(string:upload)!
    var bytes = try Data(contentsOf:url);bytes[0] ^= 1;try bytes.write(to:url)
    do {_ = try await uploader.upload(pending,token:{XCTFail("Changed file reached network");return "test"},progress:{_,_ in});XCTFail("Changed file accepted")} catch {}
  }
  func testRepeatedNoProgressHasBoundedRetriesAndCancellation() async throws {
    let url = try file(),transport = ScriptedGoogle([response(200,["Location":upload])]+Array(repeating:response(308),count:30))
    let uploader = YouTubeUploader(transport:transport,sleep:{_ in}),pending = try await uploader.begin(file:url,draft:draft(),token:"test",chunkSize:262_144)
    do {_ = try await uploader.upload(pending,token:{"test"},progress:{_,_ in});XCTFail("No-progress loop did not stop")} catch {}
    let requests = await transport.requests;XCTAssertLessThanOrEqual(requests.count,14)
    let task = Task {try await uploader.upload(pending,token:{"test"},progress:{_,_ in})};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled upload continued")} catch {}
    let finalCount = await transport.requests.count;XCTAssertEqual(finalCount,requests.count)
  }
  func testCallbackRequiresStateAndActualLoopbackFlow() async throws {
    let callback = GoogleOAuthCallback(state:"test-state"),redirect = try await callback.start();defer {callback.cancel()}
    func url(_ state:String) -> URL {var parts = URLComponents(url:redirect,resolvingAgainstBaseURL:false)!;parts.queryItems = [URLQueryItem(name:"state",value:state),URLQueryItem(name:"code",value:"test-code")];return parts.url!}
    let waiter = Task {try await callback.code()}
    let session = URLSession(configuration:.ephemeral);defer {session.invalidateAndCancel()}
    let (_,invalid) = try await session.data(from:url("wrong-state"));XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode,400)
    let (_,valid) = try await session.data(from:url("test-state"));XCTAssertEqual((valid as? HTTPURLResponse)?.statusCode,200)
    let code = try await waiter.value;XCTAssertEqual(code,"test-code")
    let forged = Data("GET /oauth2callback?state=test-state&code=one&code=two HTTP/1.1\r\nHost: 127.0.0.1:1234".utf8)
    XCTAssertNil(GoogleOAuthCallback.parse(forged,port:1234,state:"test-state"))
  }
}
