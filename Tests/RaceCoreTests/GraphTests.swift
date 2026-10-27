import XCTest
@testable import RaceCore

final class GraphTests: XCTestCase {
  func fixture() throws -> (DisplayObject,Telemetry) {
    var o = DisplayObject(name:"Speed graph",kind:.graph); o.channel = "Speed"; o.graph = GraphSettings()
    let d = try Telemetry(text:"Time,Speed,Distance,Brake\n0,0,0,0\n1,20,10,100\n2,80,30,30\n3,40,60,0\n4,0,80,60")
    return (o,d)
  }
  func testHistoryCenteredFixedAndProgressAreSeekIndependentAndDoNotClampFutureSamples() throws {
    var (o,d) = try fixture(); o.graph?.timeSpan = 2
    var p = GraphSampler.plot(object:o,data:d,time:1)
    XCTAssertEqual(p.xRange,-1...1); XCTAssertEqual(p.points.map(\.time),[0,1])
    o.graph?.mode = .centered
    p = GraphSampler.plot(object:o,data:d,time:1)
    XCTAssertEqual(p.xRange,0...2); XCTAssertEqual(p.points.map(\.time),[0,1,2])
    o.graph?.mode = .fixed; o.graph?.timeStart = 1; o.graph?.timeEnd = 3
    p = GraphSampler.plot(object:o,data:d,time:1.5)
    XCTAssertEqual(p.xRange,1...3); XCTAssertEqual(p.points.map(\.time),[1,2,3]); XCTAssertEqual(p.cursor?.y,50)
    o.graph?.mode = .progress
    let first = GraphSampler.plot(object:o,data:d,time:1.5)
    _ = GraphSampler.plot(object:o,data:d,time:3)
    XCTAssertEqual(first.points,GraphSampler.plot(object:o,data:d,time:1.5).points)
    XCTAssertEqual(first.points.map(\.time),[1]); XCTAssertNil(GraphSampler.plot(object:o,data:d,time:0).cursor)
  }
  func testDistanceAndNonmonotonicChannelAxesRangesAndMissingFields() throws {
    var (o,d) = try fixture(); o.graph?.mode = .fixed; o.graph?.axis = .distance
    var p = GraphSampler.plot(object:o,data:d,time:2)
    XCTAssertEqual(p.points.map(\.x),[0,10,30,60,80]); XCTAssertEqual(p.xRange,0...80)
    o.graph?.axis = .channel; o.graph?.horizontalChannel = "Brake"
    p = GraphSampler.plot(object:o,data:d,time:2)
    XCTAssertEqual(p.points.map(\.x),[0,100,30,0,60])
    o.graph?.sortX = true; o.graph?.xMinimum = -10; o.graph?.xMaximum = 110
    p = GraphSampler.plot(object:o,data:d,time:2)
    XCTAssertEqual(p.points.map(\.x),[0,0,30,60,100]); XCTAssertEqual(p.xRange,-10...110)
    o.graph?.horizontalChannel = "Not recorded"
    XCTAssertEqual(GraphSampler.plot(object:o,data:d,time:2).message,"X channel unavailable")
    o.channel = "Missing"
    XCTAssertEqual(GraphSampler.plot(object:o,data:d,time:2).message,"Y channel unavailable")
  }
  func testExtremaReductionPreservesNarrowPeaksGapsAndInvalidatesAfterTransforms() throws {
    var o = DisplayObject(name:"Peak",kind:.graph); o.channel = "Speed"; o.graph = GraphSettings(); o.graph?.mode = .fixed
    let d = try Telemetry(text:"Time,Speed\n"+(0..<10000).map { "\($0),\($0 == 5432 ? 999 : 1)" }.joined(separator:"\n"))
    d.columns[1][120] = .nan
    let p = GraphSampler.plot(object:o,data:d,time:500,resolution:32)
    XCTAssertLessThan(p.points.count,200); XCTAssertTrue(p.points.contains { $0.y == 999 })
    XCTAssertGreaterThan(p.points.filter(\.beginsPath).count,1)
    d.columns[1][5432] = 777; d.renderRevision += 1
    XCTAssertTrue(GraphSampler.plot(object:o,data:d,time:500,resolution:32).points.contains { $0.y == 777 })
    XCTAssertFalse(GraphSampler.plot(object:o,data:d,time:500,resolution:32).points.contains { $0.y == 999 })
  }
  func testMalformedRangesAndFlatDataProduceFinitePlotAndNoFutureHold() throws {
    var (o,d) = try fixture(); o.graph?.timeSpan = .nan; o.graph?.xMinimum = 5; o.graph?.xMaximum = -5
    o.minimum = 4; o.maximum = 4
    let p = GraphSampler.plot(object:o,data:d,time:30)
    XCTAssertTrue(p.points.isEmpty); XCTAssertNil(p.cursor)
    XCTAssertGreaterThan(p.xRange.upperBound,p.xRange.lowerBound); XCTAssertGreaterThan(p.yRange.upperBound,p.yRange.lowerBound)
    o.graph?.automaticMinimum = true; o.graph?.automaticMaximum = true
    XCTAssertEqual(GraphSampler.plot(object:o,data:d,time:2).yRange,0...80)
  }
  func testNativeSaveTemplateTimelineAndOldLegacyMigration() throws {
    var (o,_) = try fixture(); var p = RaceProject(); o.graph?.axis = .channel; o.graph?.horizontalChannel = "Brake"
    o.graph?.fill = true; o.graph?.lineGradient = "#FFFF00"; o.graph?.timeSpan = 8
    p.objects = [o]; p.inputs = [MediaInput(name:"Data",path:"",kind:"data")]
    var edited = o; edited.graph?.timeSpan = 3; edited.graph?.mode = .centered
    p.objects[0].editSegment(at:2,from:o,to:edited)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("graph.orrp"); try p.save(file)
    let reopened = try RaceProject.read(file)
    XCTAssertEqual(reopened.objects[0].graph,o.graph); XCTAssertEqual(reopened.objects[0].resolved(at:2).graph,edited.graph)
    let template = try reopened.reusableLayout()
    XCTAssertEqual(template.objects[0].graph,o.graph)
    var legacy = legacyGraph(); legacy.graph = nil; legacy.kind = .speed
    var old = RaceProject(); old.objects = [legacy]; try old.save(file)
    let migrated = try RaceProject.read(file)
    XCTAssertEqual(migrated.objects[0].kind,.graph); XCTAssertEqual(migrated.objects[0].graph?.mode,.fixedBoth)
    XCTAssertEqual(migrated.objects[0].minimum,-20)
  }
  func legacyGraph() -> DisplayObject {
    var common = Data(repeating:0,count:344); common[280] = 35; common[281] = 2
    common.putUTF16("Speed graph",0,128); common.putU32(.max,256)
    common.putFloat(5,260); common.putFloat(5,264); common.putFloat(50,268); common.putFloat(30,272)
    common.putU32(600 | (300 << 16),296)
    var d = Data(repeating:0,count:624); d.putUTF16("Speed",0,128); d.putUTF16("Brake",472,128)
    d.putDouble(-20,256); d.putDouble(180,264); d.putFloat(7.5,272); d[429] = 6
    d.putDouble(10,600); d.putDouble(90,608); d.putFloat(1.25,448); d.putFloat(18.75,452)
    d.putFloat(10,436); d.putFloat(14,468); d[616] = 3
    var o = LegacyReader.decodeCommon(common,at:0,legacyIndex:0); o.legacyPayload = d; LegacyReader.inferDetails(&o)
    return o
  }
  func testLegacyGraphConfigRoundTripAndUnsupportedAppearanceIsExplicit() throws {
    var o = legacyGraph()
    XCTAssertEqual(o.kind,.graph); XCTAssertEqual(o.minimum,-20); XCTAssertEqual(o.maximum,180)
    XCTAssertEqual(o.graph?.horizontalChannel,"Brake"); XCTAssertEqual(o.graph?.xMinimum,10)
    XCTAssertEqual(o.graph?.mode,.fixedBoth); XCTAssertEqual(o.graph?.timeSpan,7.5)
    o.graph?.axis = .time; o.graph?.horizontalChannel = ""; o.graph?.mode = .centered
    o.graph?.timeSpan = 13; o.graph?.timeStart = nil; o.graph?.timeEnd = nil
    o.graph?.xMinimum = nil; o.graph?.xMaximum = nil; o.graph?.vertical = true; o.graph?.reverse = true
    o.graph?.sortX = false; o.minimum = -50
    var p = RaceProject(); p.objects = [o]; p.inputs = [MediaInput(name:"Data",path:"",kind:"data")]
    let output = try LegacyWriter.data(p,format:.rrp)
    let reopened = try LegacyReader.project(output,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(reopened.objects[0].graph,o.graph); XCTAssertEqual(reopened.objects[0].minimum,-50)
    p.objects[0].graph?.lap = 2
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
  func testAuthoredGraphModesAndAppearanceRoundTripAcrossAllLegacyContainers() throws {
    var (o,_) = try fixture(); o.width = 45; o.height = 30
    o.graph?.background = false; o.graph?.fill = true; o.graph?.fillColor = "#224466"
    o.graph?.lineGradient = "#112233"; o.graph?.fillGradient = "#334455"
    o.graph?.interval = 20
    o.graph?.label = "Speed"; o.graph?.markerColor = "#FF0000"; o.graph?.markerSize = 4
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    for mode in GraphSettings.Mode.allCases {
      o.graph?.mode = mode
      var p = RaceProject(); p.objects = [o]; p.inputs = [MediaInput(name:"Logger",path:"",kind:"data")]
      for format in [LegacyWriter.Format.rrp,.rrt,.rro] {
        let file = root.appendingPathComponent("graph."+format.rawValue)
        try LegacyWriter.data(p,format:format).write(to:file)
        let result = try RaceProject.read(file)
        XCTAssertEqual(result.objects[0].kind,.graph)
        XCTAssertEqual(result.objects[0].graph,o.graph,"\(mode) / \(format)")
      }
    }
  }
  func testGraphRenderingSettingsAndCursorAffectPixelsAndRepeatOnSeek() throws {
    var (o,d) = try fixture(); o.graph?.mode = .fixedBoth
    func pixels(_ object:DisplayObject,_ time:Double = 2) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:600,height:300,bitsPerComponent:8,bytesPerRow:2400,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      GraphRenderer.draw(c,object:object,rect:CGRect(x:0,y:0,width:600,height:300),data:d,time:time)
      return Data(bytes:try XCTUnwrap(c.data),count:720000)
    }
    let first = try pixels(o)
    XCTAssertNotEqual(first,try pixels(o,1)); XCTAssertEqual(first,try pixels(o))
    o.graph?.fill = true; XCTAssertNotEqual(first,try pixels(o))
    let filled = try pixels(o); o.graph?.vertical = true; XCTAssertNotEqual(filled,try pixels(o))
    o.graph?.axis = .channel; o.graph?.horizontalChannel = "Brake"; o.graph?.connect = false
    XCTAssertNotEqual(filled,try pixels(o))
    o.graph?.background = false; o.graph?.lineWidth = .nan; o.graph?.interval = .infinity
    XCTAssertNoThrow(try pixels(o))
  }
}
