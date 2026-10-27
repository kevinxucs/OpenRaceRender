import AppKit
import XCTest
@testable import RaceCore

final class DerivedMotionTests:XCTestCase {
  func testNativeGWidgetHonorsExplicitLateralChannelAlongsideSharedLongitudinalRole() throws {
    let data = try Telemetry(text:"Time,Longitudinal acceleration (G),Lateral acceleration (G),Custom G\n0,0,0,1\n1,0,0,1\n2,0,0,1\n")
    var p = RaceProject(); var input = MediaInput(name:"Data",path:"",kind:"data"); input.duration = 2; p.inputs = [input]
    var object = DisplayObject(name:"G-force",kind:.gforce); object.x = 0; object.y = 0; object.width = 100; object.height = 100; p.objects = [object]
    func render(_ project:RaceProject) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:400,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      OverlayRenderer.draw(c,scene:RenderScene(project:project,telemetry:[0:data]),time:1,size:CGSize(width:100,height:100))
      return Data(bytes:try XCTUnwrap(c.data),count:40000)
    }
    let automatic = try render(p)
    p.objects[0].channel = "Custom G"; XCTAssertNotEqual(automatic,try render(p))
  }
  func testAccelerationHeadersAreNotGPSAliasesAndMapUsesOneCoordinateBasis() throws {
    let data = try Telemetry(text:"Time,X,Y,Latitude,Longitude,Lateral acceleration (G),Longitudinal acceleration (G)\n0,100,200,37,-122,0.4,0.2\n1,110,210,37.0001,-122.0001,0.4,0.2\n")
    XCTAssertEqual(data.value("lat",at:0),37); XCTAssertEqual(data.value("lon",at:0),-122)
    XCTAssertEqual(data.mapPoints.first?.0,100); XCTAssertEqual(data.trackPosition(at:0)?.0,100)
    XCTAssertEqual(data.mapPoints.first?.1,200); XCTAssertEqual(data.trackPosition(at:0)?.1,200)
    let xy = try Telemetry(text:"Time,X,Y,Lateral acceleration (G),Longitudinal acceleration (G)\n0,100,200,0.4,0.2\n1,110,210,0.4,0.2\n")
    XCTAssertNil(xy.aliases["lat"]); XCTAssertNil(xy.aliases["lon"])
    XCTAssertEqual(xy.mapPoints.first?.0,100)
    let rawAcceleration = try Telemetry(text:"Time,X acceleration (G),Y acceleration (G)\n0,0,1\n1,1,0\n")
    XCTAssertNil(rawAcceleration.aliases["x"]); XCTAssertNil(rawAcceleration.aliases["y"])
  }
  func testGPSCardinalHeadingAndSpeedAreSharedNamedChannels() throws {
    let north = try Telemetry(text:"Time,Latitude,Longitude\n0,0,0\n1,0.0001,0\n2,0.0002,0\n")
    XCTAssertEqual(try XCTUnwrap(north.value("heading",at:1)),0,accuracy:1e-7)
    XCTAssertEqual(try XCTUnwrap(north.speed(at:1,unit:"m/s")),11.1195,accuracy:0.01)
    XCTAssertEqual(try XCTUnwrap(north.value("gx",at:1)),0,accuracy:0.001)
    XCTAssertEqual(try XCTUnwrap(north.value("gy",at:1)),0,accuracy:0.001)
    XCTAssertEqual(north.provenance(for:"heading")?.kind,.gps)
    XCTAssertEqual(north.recordedHeaders,["Time","Latitude","Longitude"])
    let east = try Telemetry(text:"Time,Latitude,Longitude\n0,0,0\n1,0,0.0001\n2,0,0.0002\n")
    XCTAssertEqual(try XCTUnwrap(east.value("heading",at:1)),90,accuracy:1e-7)
  }
  func testAnalyticRightTurnAndLinearAccelerationHaveCorrectMagnitudeAndSign() throws {
    let rows = (0...100).map { i -> String in
      let t = Double(i)/10, angle = t*0.2
      let x = 100*(1-cos(angle)), y = 100*sin(angle)
      return "\(t),\(x),\(y),20"
    }
    let turn = try Telemetry(text:"Time,X,Y,Speed (m/s)\n"+rows.joined(separator:"\n"))
    XCTAssertEqual(try XCTUnwrap(turn.value("heading",at:5)),1.0*180 / .pi,accuracy:0.02)
    XCTAssertEqual(try XCTUnwrap(turn.value("gy",at:5)),4/9.80665,accuracy:0.001)
    XCTAssertEqual(try XCTUnwrap(turn.value("gx",at:5)),0,accuracy:0.001)
    let linear = try Telemetry(text:"Time,Speed (m/s)\n0,0\n1,2\n2,4\n3,6\n")
    XCTAssertEqual(try XCTUnwrap(linear.value("gx",at:1.5)),2/9.80665,accuracy:1e-9)
    XCTAssertEqual(linear.provenance(for:"gx")?.kind,.speed)
  }
  func testRecordedPriorityForcedCalculationAndHeadingAdjustmentDoNotRotatePhysicalG() throws {
    let data = try Telemetry(text:"Time,Latitude,Longitude,Speed (m/s),Heading (deg),Longitudinal acceleration (G),Lateral acceleration (G)\n0,0,0,10,30,1,2\n1,0.0001,0,10,30,1,2\n2,0.0002,0,10,30,1,2\n")
    XCTAssertEqual(data.value("heading",at:1),30); XCTAssertEqual(data.value("gx",at:1),1); XCTAssertEqual(data.value("gy",at:1),2)
    XCTAssertEqual(data.provenance(for:"heading")?.kind,.recorded)
    var s = DataSettings(); s.headingDerivation = .calculate; s.longitudinalDerivation = .calculate; s.lateralDerivation = .calculate
    s.headingAdjustment = 90; s.reverseHeading = true; data.configure(s)
    XCTAssertEqual(data.value("heading",at:1),90)
    XCTAssertEqual(try XCTUnwrap(data.value("gx",at:1)),0,accuracy:1e-6); XCTAssertEqual(try XCTUnwrap(data.value("gy",at:1)),0,accuracy:1e-6)
    XCTAssertEqual(data.value("Heading (deg)",at:1),30)
    XCTAssertEqual(data.provenance(for:"heading")?.kind,.gps)
    data.configure(DataSettings()); XCTAssertEqual(data.value("heading",at:1),30)
  }
  func testHeadingInterpolatesThroughNorthAndRecordedOnlyDisablesFallback() throws {
    let heading = try Telemetry(text:"Time,Heading,Speed (m/s)\n0,359,10\n1,1,10\n2,3,10\n")
    XCTAssertEqual(try XCTUnwrap(heading.value("heading",at:0.5)),0,accuracy:1e-9)
    XCTAssertEqual(try XCTUnwrap(heading.value("gy",at:1)),10*2 * .pi/180/9.80665,accuracy:1e-6)
    let gps = try Telemetry(text:"Time,Latitude,Longitude\n0,0,0\n1,0.0001,0\n2,0.0002,0\n")
    var s = DataSettings(); s.headingDerivation = .recordedOnly; s.longitudinalDerivation = .recordedOnly; s.lateralDerivation = .recordedOnly
    gps.configure(s); XCTAssertNil(gps.channelIndex("heading")); XCTAssertNil(gps.channelIndex("gx")); XCTAssertNil(gps.channelIndex("gy"))
    let ramp = try Telemetry(text:"Time,Speed (m/s)\n0,0\n1,10\n2,20\n")
    let zero = try Telemetry(text:"Time,Speed (m/s)\n0,0\n1,0\n2,0\n")
    ramp.configure(s); zero.configure(s)
    func legacyBall(_ data:Telemetry) throws -> Data {
      var o = DisplayObject(name:"Imported G ball",kind:.gforce); o.legacyType = 74
      var payload = Data(repeating:0,count:440); payload.putFloat(2,256); payload.putFloat(2,260)
      payload.putUTF16("(Accel Y)",0,128); payload.putUTF16("(Accel X)",128,128)
      payload.putU32(0xffffff,264); payload[277] = 20; o.legacyPayload = payload
      let c = try XCTUnwrap(CGContext(data:nil,width:200,height:200,bitsPerComponent:8,bytesPerRow:800,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      XCTAssertTrue(LegacyStyledRenderer.draw(c,object:o,rect:CGRect(x:0,y:0,width:200,height:200),data:data,time:1,unit:"m/s",canvasHeight:200))
      return Data(bytes:try XCTUnwrap(c.data),count:160000)
    }
    XCTAssertEqual(try legacyBall(ramp),try legacyBall(zero),"Recorded-only mode must also suppress the old renderer's private speed-acceleration fallback")
    ramp.configure(DataSettings())
    XCTAssertNotEqual(try legacyBall(ramp),try legacyBall(zero),"Native special G-field identifiers must resolve to the shared estimated roles")
  }
  func testMissingPositionsLargeGapsAndStationaryDataDoNotInventHeadingOrBridgeGap() throws {
    let stationary = try Telemetry(text:"Time,Latitude,Longitude\n0,37,-122\n1,37,-122\n2,37,-122\n")
    XCTAssertNil(stationary.value("heading",at:1)); XCTAssertEqual(stationary.value("gy",at:1),0)
    let gap = try Telemetry(text:"Time,Latitude,Longitude\n0,0,0\n0.1,0.00001,0\n0.2,0.00002,0\n100,0.01,0\n100.1,0.01001,0\n100.2,0.01002,0\n")
    XCTAssertNil(gap.value("heading",at:50)); XCTAssertNil(gap.speed(at:50,unit:"m/s")); XCTAssertNil(gap.value("gy",at:50))
    let missing = try Telemetry(text:"Time,Speed (m/s)\n0,10\n1,10\n")
    var force = DataSettings(); force.headingDerivation = .calculate; missing.configure(force)
    XCTAssertNil(missing.value("heading",at:0.5)); XCTAssertEqual(missing.provenance(for:"heading")?.kind,.position)
  }
  func testReconfigurationIsIdempotentAndInvalidatesDerivedBounds() throws {
    let data = try Telemetry(text:"Time,Raw speed\n0,0\n1000,2\n2000,4\n")
    var s = DataSettings(); s.assignments["speed"] = "Raw speed"; s.timeUnitsPerSecond = 1000; s.speedMultiplier = 2; s.speedUnit = "m/s"
    var f = CalculatedField(); f.name = "Double speed"; f.source = "speed"; f.multiply = 2; s.fields = [f]
    data.configure(s)
    XCTAssertEqual(data.duration,2); XCTAssertEqual(data.value("Double speed",at:1),8)
    XCTAssertEqual(try XCTUnwrap(data.value("gx",at:1)),4/9.80665,accuracy:1e-9)
    let headers = data.headers; _ = data.bounds("gx"); data.configure(s)
    XCTAssertEqual(data.headers,headers); XCTAssertEqual(data.duration,2); XCTAssertEqual(data.value("Double speed",at:1),8)
    data.configure(DataSettings()); XCTAssertEqual(data.duration,2000); XCTAssertEqual(data.recordedHeaders,data.headers)
  }
  func testModesPersistAndLegacyHeadingCalculationUsesDocumentedMarker() throws {
    var s = DataSettings(); s.headingDerivation = .calculate; s.headingAdjustment = -20; s.reverseHeading = true
    var input = MediaInput(name:"GPS",path:"gps.csv",kind:"data"); input.duration = 2; input.dataSettings = s
    var p = RaceProject(); p.inputs = [input]
    let bytes = try LegacyWriter.data(p,format:.rrp)
    let reopened = try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(reopened.inputs[0].dataSettings?.headingDerivation,.calculate)
    XCTAssertEqual(reopened.inputs[0].dataSettings?.headingAdjustment,-20)
    s.lateralDerivation = .recordedOnly; p.inputs[0].dataSettings = s
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    let decoded = try JSONDecoder().decode(DataSettings.self,from:JSONEncoder().encode(s))
    XCTAssertEqual(decoded,s)
  }
}
