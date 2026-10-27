import AppKit
import XCTest
@testable import RaceCore

final class TelemetrySmoothingTests:XCTestCase {
  func testTimeWeightedAveragesUseIrregularTimestampsClipAtEndsAndResetCache() throws {
    let data = try Telemetry(text:"Time,Speed (m/s),RPM\n0,0,0\n1,10,10\n3,10,10\n")
    XCTAssertEqual(try XCTUnwrap(data.averagedValue("rpm",at:1.5,window:3)),25/3,accuracy:1e-9)
    XCTAssertEqual(try XCTUnwrap(data.averagedValue("rpm",at:0.1,window:2)),6/1.1,accuracy:1e-9)
    XCTAssertEqual(try XCTUnwrap(data.speed(at:1.5,unit:"km/h",smoothing:3)),30,accuracy:1e-8)
    let forward = [0.2,1.0,2.0].map{data.averagedValue("rpm",at:$0,window:1)}
    let reversed = [2.0,1.0,0.2].map{data.averagedValue("rpm",at:$0,window:1)}
    XCTAssertEqual(forward,Array(reversed.reversed()))
    var settings = DataSettings(); settings.interpolate = false; data.configure(settings)
    XCTAssertEqual(try XCTUnwrap(data.averagedValue("rpm",at:1.5,window:3)),20/3,accuracy:1e-9)
    data.configure(DataSettings()); XCTAssertEqual(try XCTUnwrap(data.averagedValue("rpm",at:1.5,window:3)),25/3,accuracy:1e-9)
  }
  func testCircularAveragesAndDiscreteGearsLapsDoNotBlend() throws {
    let data = try Telemetry(text:"Time,Heading,Gear,Lap\n0,359,1,1\n1,1,2,2\n2,3,3,3\n")
    let heading = try XCTUnwrap(data.averagedValue("heading",at:0.5,window:1))
    XCTAssertEqual(Telemetry.headingDelta(from:0,to:heading),0,accuracy:1e-8)
    XCTAssertEqual(data.averagedValue("gear",at:0.5,window:2),1)
    XCTAssertEqual(data.averagedValue("lap",at:0.5,window:2),1)
    XCTAssertEqual(data.averagedValue("gear",at:1,window:2),2)
  }
  func testMissingAndLongGapsAreNotInterpolatedOrAveragedAcross() throws {
    let data = try Telemetry(text:"Time,RPM\n0,0\n0.1,10\n10,1000\n10.1,1010\n")
    XCTAssertNil(data.value("rpm",at:5)); XCTAssertNil(data.averagedValue("rpm",at:5,window:10))
    XCTAssertEqual(data.averagedValue("rpm",at:0.1,window:1),10,"A window crossing a pause falls back to its current valid sample")
    let c = try XCTUnwrap(data.channelIndex("rpm")); data.columns[c][1] = .nan; data.recordedState = nil; data.configure(DataSettings())
    XCTAssertNil(data.averagedValue("rpm",at:0.1,window:1))
  }
  func testHeldGPSUpdatesAreOptInPreserveStopsAndDoNotModifyOBDSpeedOrClocks() throws {
    let rows = (0...60).map { i -> String in
      let fix = i < 30 ? i/10 : i < 60 ? 2 : 3
      return "\(Double(i)/10),\(37+Double(fix)*0.0001),\(-122+Double(fix)*0.0001),\(fix*10),\(i)"
    }
    let data = try Telemetry(text:"Time,Latitude,Longitude,Speed (m/s) *OBD,RPM\n"+rows.joined(separator:"\n"))
    XCTAssertEqual(data.value("lat",at:0.5),37)
    let times = data.times; var settings = DataSettings(); settings.detectGPSUpdates = true; data.configure(settings)
    XCTAssertEqual(try XCTUnwrap(data.value("lat",at:0.5)),37.00005,accuracy:1e-10)
    XCTAssertEqual(data.value("lat",at:4),37.0002,"A long repeated location must remain a stop")
    XCTAssertEqual(data.speed(at:0.5,unit:"m/s"),0,"Do not reconstruct high-rate OBD speed using GPS rules")
    XCTAssertEqual(data.times,times); let value = data.value("lat",at:0.5); data.configure(settings); XCTAssertEqual(data.value("lat",at:0.5),value)
    settings.interpolate = false; data.configure(settings); XCTAssertEqual(data.value("lat",at:0.5),37)
    data.configure(DataSettings()); XCTAssertEqual(data.value("lat",at:0.5),37)
    let gpsRows = (0...30).map{"\(Double($0)/10),\(($0/10)*10)"}
    let speed = try Telemetry(text:"Time,Speed (m/s)\n"+gpsRows.joined(separator:"\n"))
    settings.interpolate = true; speed.configure(settings); XCTAssertEqual(speed.speed(at:0.5,unit:"m/s"),5)
  }
  func testMapCurvesAreBoundedAndTraceMatchesMarker() throws {
    let data = try Telemetry(text:"Time,X,Y\n0,0,0\n1,1,1\n2,2,0\n")
    XCTAssertEqual(data.trackPosition(at:0.5)?.1,0.5)
    var settings = DataSettings(); settings.smoothCurves = true; data.configure(settings)
    XCTAssertEqual(data.trackPosition(at:0.5)?.1,0.625)
    XCTAssertGreaterThan(data.mapPoints.count,3)
    XCTAssertTrue(data.mapPoints.allSatisfy{$0.1 >= 0 && $0.1 <= 1})
    XCTAssertTrue(data.mapPoints.contains{abs($0.0-0.5) < 1e-12 && abs($0.1-0.625) < 1e-12})
    XCTAssertEqual(data.laps.count,0)
    settings.interpolate = false; data.configure(settings); XCTAssertEqual(data.trackPosition(at:0.5)?.1,0)
    data.configure(DataSettings()); XCTAssertEqual(data.trackPosition(at:0.5)?.1,0.5)
  }
  func testOptionsPersistInProfilesAndUnverifiedLegacyFlagsAreRejected() throws {
    var settings = DataSettings(); settings.detectGPSUpdates = true; settings.smoothCurves = true
    let profile = DataProfile(name:"Phone GPS",settings:settings)
    XCTAssertEqual(try JSONDecoder().decode(DataProfile.self,from:JSONEncoder().encode(profile)),profile)
    var input = MediaInput(name:"Data",path:"data.csv",kind:"data"); input.dataSettings = settings
    var project = RaceProject(); project.inputs = [input]
    XCTAssertThrowsError(try LegacyWriter.data(project,format:.rrp))
    settings.detectGPSUpdates = nil; settings.smoothCurves = nil; settings.interpolate = false; project.inputs[0].dataSettings = settings
    let bytes = try LegacyWriter.data(project,format:.rrp)
    let reopened = try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(reopened.inputs[0].dataSettings?.interpolate,false)
  }
}
