import AVFoundation
import CryptoKit
import XCTest
@testable import RaceCore
@testable import OpenRaceRender

@MainActor final class MemoryYouTubeStore:YouTubeCredentialStore {
  var items:[String:Data] = [:];var reads:[String] = []
  func read(_ account:String) throws -> Data? {reads.append(account);return items[account]}
  func write(_ value:Data?,account:String) throws {items[account] = value}
}
actor EditorGoogleMock:YouTubeHTTPTransport {
  var replies:[YouTubeHTTPResponse];var requests:[URLRequest] = []
  init(_ replies:[YouTubeHTTPResponse]) {self.replies = replies}
  func send(_ request:URLRequest) async throws -> YouTubeHTTPResponse {
    requests.append(request)
    guard !replies.isEmpty else {throw RaceError.invalid("Unexpected test request")};return replies.removeFirst()
  }
}
final class YouTubeEditorTests:XCTestCase {
  @MainActor func authorize(_ model:YouTubeUploadModel,store:MemoryYouTubeStore,pending:YouTubePendingUpload? = nil) throws -> String {
    let json = try JSONSerialization.data(withJSONObject:["installed":["client_id":"test.apps.googleusercontent.com","client_secret":"synthetic-client"]])
    try model.installClient(json)
    let account = try XCTUnwrap(store.reads.last(where:{$0.hasPrefix("account-")}))
    store.items[account] = try JSONEncoder().encode(YouTubeUploadModel.SavedConnection(token:GoogleOAuthToken(accessToken:"test-access",refreshToken:"test-refresh",expiresAt:Date().addingTimeInterval(3600)),pending:pending))
    model.restore();return account
  }
  @MainActor func testExplicitUploadPersistsOriginalMetadataAndCompletionWithoutGoogleOrKeychain() async throws {
    let (asset,_,_) = try await GeneratedVideoClock.shared.source()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("original.mov");try FileManager.default.copyItem(at:asset.url,to:file)
    let transport = EditorGoogleMock([
      YouTubeHTTPResponse(status:200,headers:["Location":"https://www.googleapis.com/upload/youtube/v3/videos?upload_id=synthetic"]),
      YouTubeHTTPResponse(status:308),YouTubeHTTPResponse(status:201,data:Data("{\"id\":\"synthetic_video\"}".utf8))])
    let store = MemoryYouTubeStore(),model = YouTubeUploadModel(file:file,title:"Original test",store:store,transport:transport)
    let account = try authorize(model,store:store)
    let before = await transport.requests;XCTAssertTrue(before.isEmpty)
    model.draft.madeForKids = false;model.draft.description = "Synthetic description";model.draft.privacy = .private
    model.upload()
    for _ in 0..<250 {if !model.working {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertFalse(model.working);XCTAssertEqual(model.videoID,"synthetic_video");XCTAssertNil(model.pending)
    let requests = await transport.requests;XCTAssertEqual(requests.count,3)
    let metadata = try XCTUnwrap(try JSONSerialization.jsonObject(with:requests[0].httpBody!) as? [String:Any])
    XCTAssertEqual((metadata["snippet"] as? [String:Any])?["description"] as? String,"Synthetic description")
    let saved = try JSONDecoder().decode(YouTubeUploadModel.SavedConnection.self,from:try XCTUnwrap(store.items[account]))
    XCTAssertNil(saved.pending);XCTAssertEqual(saved.token?.refreshToken,"test-refresh")
    XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
  }
  @MainActor func testRestorePauseDiscardAndLocalDisconnectDoNotTransmitOrDeleteVideo() async throws {
    let (asset,_,_) = try await GeneratedVideoClock.shared.source()
    let store = MemoryYouTubeStore(),transport = EditorGoogleMock([])
    let model = YouTubeUploadModel(file:nil,title:"Draft",store:store,transport:transport)
    var draft = YouTubeVideoDraft(title:"Saved draft");draft.madeForKids = false
    let identity = try YouTubeFileIdentity.read(asset.url)
    let pending = YouTubePendingUpload(url:URL(string:"https://www.googleapis.com/upload/youtube/v3/videos?upload_id=saved")!,file:identity,draft:draft,chunkSize:262_144)
    let account = try authorize(model,store:store,pending:pending)
    XCTAssertEqual(model.pending,pending);XCTAssertEqual(model.file,asset.url);XCTAssertEqual(model.draft,draft)
    model.pause();XCTAssertEqual(model.pending,pending)
    model.discardResume();XCTAssertNil(model.pending)
    XCTAssertTrue(FileManager.default.fileExists(atPath:asset.url.path))
    let requests = await transport.requests;XCTAssertTrue(requests.isEmpty)
    model.disconnect();XCTAssertFalse(model.connected);XCTAssertNil(store.items[account])
    XCTAssertNotNil(store.items["desktop-client"])
  }
  @MainActor func testAuthorizationFailureRetainsDurableResumeAndReopeningChecksCompletion() async throws {
    let (asset,_,_) = try await GeneratedVideoClock.shared.source()
    let store = MemoryYouTubeStore(),transport = EditorGoogleMock([
      YouTubeHTTPResponse(status:200,headers:["Location":"https://www.googleapis.com/upload/youtube/v3/videos?upload_id=resume"]),YouTubeHTTPResponse(status:401)])
    let model = YouTubeUploadModel(file:asset.url,title:"Original resume test",store:store,transport:transport)
    let account = try authorize(model,store:store);model.draft.madeForKids = false;model.upload()
    for _ in 0..<150 {if !model.working {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertNotNil(model.pending);XCTAssertNil(model.videoID)
    let saved = try JSONDecoder().decode(YouTubeUploadModel.SavedConnection.self,from:try XCTUnwrap(store.items[account]))
    XCTAssertNotNil(saved.pending)
    let resumedTransport = EditorGoogleMock([YouTubeHTTPResponse(status:200,data:Data("{\"id\":\"already_uploaded\"}".utf8))])
    let reopened = YouTubeUploadModel(file:nil,title:"Other draft",store:store,transport:resumedTransport)
    reopened.restore();XCTAssertEqual(reopened.draft.title,"Original resume test")
    reopened.upload()
    for _ in 0..<150 {if !reopened.working {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertEqual(reopened.videoID,"already_uploaded");XCTAssertNil(reopened.pending)
    let requests = await resumedTransport.requests;XCTAssertEqual(requests.count,1);XCTAssertEqual(requests.first?.httpMethod,"PUT")
    XCTAssertTrue(requests.first?.value(forHTTPHeaderField:"Content-Range")?.hasPrefix("bytes */") == true)
  }
  @MainActor func testMissingOrUnfinishedVideoCannotCreateRemoteSession() async throws {
    let store = MemoryYouTubeStore(),transport = EditorGoogleMock([])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    try Data("unfinished file".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
    let model = YouTubeUploadModel(file:url,title:"Draft",store:store,transport:transport)
    _ = try authorize(model,store:store);model.draft.madeForKids = false;model.upload()
    for _ in 0..<100 {if !model.working {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertFalse(model.working);XCTAssertNil(model.pending);XCTAssertNil(model.videoID)
    let requests = await transport.requests;XCTAssertTrue(requests.isEmpty)
  }
}
