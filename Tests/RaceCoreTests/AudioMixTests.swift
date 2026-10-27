import XCTest
@testable import RaceCore

final class AudioMixTests:XCTestCase {
  func testSourceThenDisplayRoutingGainAndPanMixIndependently() {
    var source = MediaInput(name:"Stereo",path:"",kind:"audio"); source.volume = 0.8
    var a = AudioSettings(); a.volume = 0.5; a.balance = -0.5; a.routing = .swap; source.audio = a
    var first = DisplayObject(name:"First",kind:.audio); var x = AudioSettings(); x.volume = 0.5; x.balance = -0.5; x.routing = .right; first.audio = x
    var second = DisplayObject(name:"Second",kind:.audio); var y = AudioSettings(); y.volume = 0.25; y.balance = 1; y.routing = .left; second.audio = y
    let result = StereoMatrix.make(source:source,displays:[first,second]).apply(0.25,0.75)
    XCTAssertEqual(result.0,0.025,accuracy:1e-9); XCTAssertEqual(result.1,0.0875,accuracy:1e-9)
    source.volume = 0
    XCTAssertEqual(StereoMatrix.make(source:source,displays:[first,second]),StereoMatrix())
  }
  func testAllRoutesDoubleSwapMonoAndMutedDisplays() {
    var source = MediaInput(name:"Stereo",path:"",kind:"audio"); source.audio = AudioSettings(); source.audio?.routing = .swap
    var display = DisplayObject(name:"Audio",kind:.audio); display.audio = AudioSettings(); display.audio?.routing = .swap
    var result = StereoMatrix.make(source:source,displays:[display]).apply(0.2,0.6)
    XCTAssertEqual(result.0,0.2); XCTAssertEqual(result.1,0.6)
    display.audio?.routing = .mono; result = StereoMatrix.make(source:source,displays:[display]).apply(0.2,0.6)
    XCTAssertEqual(result.0,0.4); XCTAssertEqual(result.1,0.4)
    display.audio?.volume = 0; XCTAssertEqual(StereoMatrix.make(source:source,displays:[display]),StereoMatrix())
    XCTAssertEqual(StereoMatrix.make(source:source,displays:[]),StereoMatrix())
  }
  func testInputGainProductRoundtripsToNativeWithoutChangingRenderedMatrix() throws {
    var p = RaceProject(); var source = MediaInput(name:"Camera",path:"camera.mov",kind:"video"); source.duration = 5; source.volume = 0.8
    var settings = AudioSettings(); settings.volume = 0.5; settings.routing = .swap; settings.balance = -0.2; source.audio = settings
    var display = DisplayObject(name:"Camera",kind:.video); var d = AudioSettings(); d.volume = 1.25; d.balance = 0.2; display.audio = d
    p.inputs = [source]; p.objects = [display]
    let read = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    let a = StereoMatrix.make(source:source,displays:[display]).apply(0.2,0.6),b = StereoMatrix.make(source:read.inputs[0],displays:read.objects).apply(0.2,0.6)
    XCTAssertEqual(a.0,b.0,accuracy:1e-9); XCTAssertEqual(a.1,b.1,accuracy:1e-9)
    p.objects[0].audio?.routing = .left; XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
}
