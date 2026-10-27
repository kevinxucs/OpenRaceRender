import XCTest
@testable import RaceCore

final class NetworkTransferTests:XCTestCase {
  func root() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    addTeardownBlock {try? FileManager.default.removeItem(at:root)};return root
  }
  func head(_ text:String,token:String = "secret") throws -> TransferHTTPHead {try TransferHTTPHead.parse(Data(text.utf8),token:token)}
  func testPairingAndFramingRejectAmbiguousRequests() throws {
    let valid = try head("PUT /upload?token=secret&name=lap%20data.csv HTTP/1.1\r\nContent-Length: 20")
    XCTAssertEqual(valid.name,"lap data.csv");XCTAssertEqual(valid.length,20)
    for text in [
      "GET / HTTP/1.1", "GET /?token=wrong HTTP/1.1", "GET /?token=secret&token=secret HTTP/1.1",
      "PUT /upload?token=secret&name=a.csv HTTP/1.1", "PUT /upload?token=secret&name=a.csv HTTP/1.1\r\nContent-Length: 20\r\nContent-Length: 20",
      "PUT /upload?token=secret&name=a.csv HTTP/1.1\r\nContent-Length: 20\r\nTransfer-Encoding: chunked",
      "PUT /upload?token=secret&name=..%2Foutside.csv HTTP/1.1\r\nContent-Length: 20",
      "PUT /upload?token=secret&name=app.sh HTTP/1.1\r\nContent-Length: 20",
      "POST /finish?token=secret HTTP/1.1\r\nContent-Length: 1",
      "PUT /upload?token=secret&name=a.csv HTTP/1.1\r\nContent-Length: 9999999999999999999"] {XCTAssertThrowsError(try head(text),text)}
  }
  func testStreamingStagingPublishDoesNotOverwriteDestinationAndCleansPartial() throws {
    let root = try root(),existing = root.appendingPathComponent("session.csv")
    try Data("original".utf8).write(to:existing)
    let store = try TransferStore(destination:root),id = UUID(),bytes = Data("Time,Speed\n0,10\n1,20\n".utf8)
    defer {store.cancel()}
    try store.begin("session.csv",size:Int64(bytes.count),id:id)
    try store.write(Data(bytes.prefix(5)),id:id)
    XCTAssertThrowsError(try store.finishFile(id));XCTAssertThrowsError(try store.commit())
    try store.write(Data(bytes.dropFirst(5)),id:id);try store.finishFile(id)
    XCTAssertThrowsError(try store.begin("SESSION.CSV",size:10,id:UUID()))
    let files = try store.commit();XCTAssertEqual(files.count,1)
    XCTAssertEqual(try Data(contentsOf:files[0]),bytes)
    XCTAssertEqual(try String(contentsOf:existing),"original")
    store.cancel();XCTAssertTrue(FileManager.default.fileExists(atPath:files[0].path))
    XCTAssertFalse(FileManager.default.fileExists(atPath:store.staging.path))
    let unfinished = try TransferStore(destination:root),partial = UUID()
    try unfinished.begin("clip.mp4",size:100,id:partial);try unfinished.write(Data([1,2,3]),id:partial)
    unfinished.cancel();XCTAssertFalse(FileManager.default.fileExists(atPath:unfinished.staging.path))
  }
  func testLimitsAndFilenameCanonicalCollisions() throws {
    let store = try TransferStore(destination:root());defer {store.cancel()}
    for name in ["../bad.csv","nested/a.csv","..\\bad.csv",".hidden.csv","nul\u{0}.csv","a.rrp",String(repeating:"a",count:260)+".csv"] {XCTAssertThrowsError(try TransferStore.validate(name))}
    XCTAssertThrowsError(try store.begin("too.mp4",size:TransferStore.maximumFileBytes+1,id:UUID()))
    let a = UUID();try store.begin("café.csv",size:1,id:a)
    XCTAssertThrowsError(try store.begin("cafe\u{301}.csv",size:1,id:UUID()))
    XCTAssertThrowsError(try store.write(Data([1,2]),id:a))
    store.abort(a);XCTAssertEqual(store.reserved,0)
  }
  func testActualLoopbackHTTPBrowserPageUploadsAndCompletion() async throws {
    let root = try root(),complete = expectation(description:"Receiver publishes files")
    let server = LocalTransferServer {event in if case .complete = event {complete.fulfill()}}
    defer {server.stop()}
    let port = try await server.start(destination:root,loopbackOnly:true)
    let session = URLSession(configuration:.ephemeral);defer {session.invalidateAndCancel()}
    func request(_ route:String,method:String = "GET",body:Data? = nil,token:String? = nil) async throws -> (Data,Int) {
      let actual = token ?? server.token
      let separator = route.contains("?") ? "&" : "?"
      let url = try XCTUnwrap(URL(string:"http://127.0.0.1:\(port)\(route)\(separator)token=\(actual)"))
      var request = URLRequest(url:url);request.httpMethod = method;request.httpBody = body;request.timeoutInterval = 10
      let (data,response) = try await session.data(for:request)
      return (data,try XCTUnwrap(response as? HTTPURLResponse).statusCode)
    }
    let invalid = try await request("/",token:"invalid");XCTAssertEqual(invalid.1,400)
    let page = try await request("/");XCTAssertEqual(page.1,200);XCTAssertTrue(String(decoding:page.0,as:UTF8.self).contains("Send files to OpenRaceRender"))
    let csv = Data("Time,Speed\n0,10\n1,20\n".utf8)
    let uploaded = try await request("/upload?name=session.csv",method:"PUT",body:csv);XCTAssertEqual(uploaded.1,200)
    let movie = Data(repeating:37,count:200_000)
    let video = try await request("/upload?name=clip.mp4",method:"PUT",body:movie);XCTAssertEqual(video.1,200)
    let finished = try await request("/finish",method:"POST");XCTAssertEqual(finished.1,200)
    await fulfillment(of:[complete],timeout:10)
    let received = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("Received-")}
    let folder = try XCTUnwrap(received.first)
    XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("clip.mp4")),movie)
    XCTAssertEqual(try Telemetry(url:folder.appendingPathComponent("session.csv")).speed(at:0,unit:"m/s"),10)
  }
}
