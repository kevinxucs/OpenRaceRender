import AppKit
import XCTest
@testable import RaceCore

final class EnhancedHistoryTests: XCTestCase {
  func payload(background: String,foreground: String,width: Int = 8,height: Int = 8) -> Data {
    var d = Data(repeating:0,count:67168)
    d.putU32(UInt32(width | height << 16),280);d[284] = 4
    d.putUTF16("Arial",432,128)
    for (offset,source) in [(1632,background),(34400,foreground)] {
      let bytes = Data(source.utf8);d.replaceSubrange(offset..<offset+bytes.count,with:bytes)
    }
    return d
  }
  func canvas(_ width: Int = 8,_ height: Int = 8) -> CGContext {
    CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  }
  func history(_ background: String,_ foreground: String) throws -> (EnhancedHistory,ScriptDrawing) {
    let program = try EnhancedProgram(payload(background:background,foreground:foreground))
    let c = canvas(),drawing = ScriptDrawing(context:canvas(),font:"Arial",data:nil,time:0,unit:"mph")
    let machine = ScriptMachine(variables:[:]) { _,_ in .number(0) };try machine.run(program.background)
    return (EnhancedHistory(program:program,background:try XCTUnwrap(c.makeImage()),telemetry:nil,
      initial:EnhancedState(variables:machine.variables,outline:-1)),drawing)
  }
  func testReplayIsIndependentOfSeekingAndRepeatedFrames() throws {
    let (runtime,drawing) = try history("sum = 0;", "sum += DataValue;")
    func render(_ frame: Int) throws -> Double {
      try runtime.render(frame:frame,drawing:drawing) { ["datavalue":.number(Double(($0+1)*2))] }["sum"]!.number
    }
    XCTAssertEqual(try render(2),12)
    XCTAssertEqual(try render(2),12)
    XCTAssertEqual(try render(0),2)
    XCTAssertEqual(try render(600),361802)
    XCTAssertEqual(try render(1),6)
    XCTAssertEqual(try render(600),361802)
    XCTAssertThrowsError(try render(1_000_001))
  }
  func testCompletedPeaksAreHeldThroughTheFollowingDeceleration() throws {
    let (runtime,drawing) = try history("previous = 0; peak = 0; held = 0; rising = 0;",
      "if (DataValue > previous) { peak = DataValue; rising = 1; } else if (DataValue < previous && rising) { held = peak; rising = 0; } previous = DataValue;")
    let samples: [Double] = [0,10,30,50,40,20,10,15]
    func render(_ frame: Int) throws -> [String:ScriptValue] {
      try runtime.render(frame:frame,drawing:drawing) { ["datavalue":.number(samples[$0])] }
    }
    XCTAssertEqual(try render(6)["held"]?.number,50)
    XCTAssertEqual(try render(3)["held"]?.number,0)
    XCTAssertEqual(try render(7)["held"]?.number,50)
  }
  func testPersistentInstancesAndNonpersistentFramesHaveSeparateState() throws {
    var o = DisplayObject(name:"Synthetic counter",kind:.enhanced);o.legacyType = 50
    o.legacyPayload = payload(background:"count = 0;",foreground:"count += 1; DrawRect(0,0,8,8,count*65536,Filled);")
    func red(_ object: DisplayObject,_ frame: Int) throws -> UInt8 {
      let c = canvas()
      XCTAssertTrue(LegacyEnhancedRenderer.draw(c,object:object,rect:CGRect(x:0,y:0,width:8,height:8),data:nil,time:Double(frame)/30,unit:"mph"))
      return try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))[0]
    }
    XCTAssertEqual(try red(o,2),3)
    XCTAssertEqual(try red(o,2),3)
    var other = o;other.id = UUID()
    XCTAssertEqual(try red(other,0),1)
    XCTAssertEqual(try red(o,3),4)
    var stateless = o;stateless.legacyPayload![284] = 0
    XCTAssertEqual(try red(stateless,20),1)
    let shifted = canvas()
    XCTAssertTrue(LegacyEnhancedRenderer.draw(shifted,object:o,rect:CGRect(x:0,y:0,width:8,height:8),data:nil,time:100.2,unit:"mph",
      timeline:EnhancedTimeline(sourceStart:100,sourceStep:0.1,displayStart:2,frameInterval:0.05)))
    XCTAssertEqual(try XCTUnwrap(shifted.data?.assumingMemoryBound(to:UInt8.self))[0],3)
  }
  func testBuiltinChannelsUseLateralGAndProjectSpeedUnits() throws {
    let data = try Telemetry(text:"Time,Speed (m/s),Lateral acceleration (G) *calc\n0,10,-0.4\n1,40,1.2\n")
    let speed = LegacyEnhancedRenderer.resolveChannel("(Speed)",fallback:"")
    let lateral = LegacyEnhancedRenderer.resolveChannel("(Accel Y)",fallback:"")
    XCTAssertEqual(LegacyEnhancedRenderer.channelValue(speed,data:data,time:1,unit:"mph"),40*2.2369362921,accuracy:0.00001)
    XCTAssertEqual(LegacyEnhancedRenderer.channelValue(lateral,data:data,time:1,unit:"mph"),1.2,accuracy:0.00001)
    XCTAssertEqual(try XCTUnwrap(LegacyEnhancedRenderer.channelBounds(speed,data:data,unit:"mph")).0,10*2.2369362921,accuracy:0.00001)
    let timeline = EnhancedTimeline(sourceStart:10,sourceStep:1.0/15,displayStart:2,frameInterval:1.0/30)
    XCTAssertEqual(timeline.displayTime(at:10.4),2.2,accuracy:0.00001)
  }
  func testTextAtCanvasEdgeIsVisible() throws {
    let c = canvas(100,60)
    let drawing = ScriptDrawing(context:c,font:"Arial",data:nil,time:0,unit:"mph")
    _ = try drawing.call("drawtext",[.string("Peak"),.number(10),.number(0),.number(0xffffff),.number(40),.number(0)])
    let image = try XCTUnwrap(c.makeImage()),pixels = try XCTUnwrap(image.dataProvider?.data) as Data
    XCTAssertTrue(stride(from:3,to:pixels.count,by:4).contains { pixels[$0] > 0 })
  }
  func testAutoBannerFollowsItsDelayedInputAvailability() throws {
    var o = DisplayObject(name:"Synthetic Auto banner",kind:.enhanced)
    o.legacyType = 50;o.legacyActivation = 0;o.x = 0;o.y = 0;o.width = 100;o.height = 100
    o.legacyPayload = payload(background:"",foreground:"DrawRect(0,0,8,8,Red,Filled);")
    var p = RaceProject();p.width = 8;p.height = 8;p.objects = [o]
    var input = MediaInput(name:"Delayed data",path:"",kind:"data");input.offset = -2;input.duration = 10;p.inputs = [input]
    let data = try Telemetry(text:"Time,Speed\n0,10\n10,20\n")
    for (time,alpha) in [(0.0,UInt8(0)),(3.0,UInt8(255))] {
      let c = canvas();OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[0:data]),time:time,size:CGSize(width:8,height:8))
      XCTAssertEqual(try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))[3],alpha)
    }
  }
  func testOldAutoImportsAreRepairedButNewNativeHidesArePreserved() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer { try? FileManager.default.removeItem(at:url) }
    var p = RaceProject(),o = DisplayObject(name:"Synthetic Auto",kind:.enhanced)
    var common = Data(repeating:0,count:344);common[284] = 0
    o.legacyCommon = common;o.visible = false;p.objects = [o];try p.save(url)
    var restored = try RaceProject.read(url)
    XCTAssertTrue(restored.objects[0].visible)
    XCTAssertEqual(restored.objects[0].legacyActivation,0)
    restored.objects[0].visible = false;try restored.save(url)
    XCTAssertFalse(try RaceProject.read(url).objects[0].visible)
  }
}
