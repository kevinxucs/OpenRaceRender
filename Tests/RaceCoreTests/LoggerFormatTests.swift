import XCTest
@testable import RaceCore

final class LoggerFormatTests:XCTestCase {
  func file(_ text:String,_ ext:String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
    try Data(text.utf8).write(to:url);addTeardownBlock {try? FileManager.default.removeItem(at:url)};return url
  }
  func testMSLUnitsAssignmentsAndRestartedClock() throws {
    let text = "MS3 firmware\nCapture date without timezone\nTime\tRPM\tTPS\tCLT\tMAT\tVSS1\tGear\nms\tRPM\t%\tF\tC\tmph\t\n1000\t1000\t20\t212\t30\t10\t2\n2000\t2000\t40\t194\t35\t20\t3\nMARK 1\n0\t3000\t60\t176\t40\t30\t4\n1000\t4000\t80\t158\t45\t40\t5\n"
    let url = try file(text,"msl"),first = try Telemetry(url:url),second = try Telemetry(url:url,session:2)
    XCTAssertEqual(first.duration,1);XCTAssertEqual(first.fileSessions.count,2)
    XCTAssertEqual(first.value("rpm",at:0),1000);XCTAssertEqual(second.value("gear",at:0),4)
    XCTAssertEqual(first.value("coolant",at:0),100);XCTAssertEqual(first.value("intake",at:0),30)
    XCTAssertEqual(first.value("throttle",at:0),20)
    XCTAssertEqual(try XCTUnwrap(second.speed(at:0,unit:"mph")),30,accuracy:1e-6)
    XCTAssertNil(first.firstSampleUnixTime)
    XCTAssertThrowsError(try Telemetry(url:url,session:3));XCTAssertThrowsError(try Telemetry(url:url,session:0))
    XCTAssertThrowsError(try LoggerText.msl(text.replacingOccurrences(of:"ms\t",with:"ticks\t")))
  }
  func testTextSessionsKeepIndependentClocksCacheKeysAndTemplateRoles() throws {
    let url = try file("Time,Speed\n0,10\n1,20\nTime,Speed\n0,30\n1,40\n","csv")
    XCTAssertEqual(try Telemetry.sessions(in:url).map(\.samples),[2,2])
    var first = MediaInput(name:"First",path:url.path,kind:"data",legacyIndex:1);first.duration = 1
    var second = first;second.id = UUID();second.legacyIndex = 2;second.dataSession = 2
    let tables = try Telemetry.loadSources([first,second])
    XCTAssertEqual(tables[1]?.value("speed",at:0),10);XCTAssertEqual(tables[2]?.value("speed",at:0),30)
    XCTAssertFalse(tables[1] === tables[2])
    var legacy = second;legacy.dataSession = nil;legacy.legacyTrackIndex = 2
    XCTAssertEqual(try Telemetry.loadSources([legacy])[2]?.value("speed",at:0),30)
    var project = RaceProject();project.inputs = [second];var widget = DisplayObject(name:"Speed",kind:.speed);widget.inputIndex = 2;project.objects = [widget]
    let duplicate = try project.duplicateDataInput(second.id)
    XCTAssertEqual(project.inputs.first(where:{$0.id == duplicate})?.dataSession,2)
    XCTAssertTrue(try project.reusableLayout().inputs.allSatisfy{$0.dataSession == nil && $0.legacyTrackIndex == nil})
  }
  func testGPXTracksAndTCXActivitiesSelectWithoutSplittingSegments() throws {
    let gpx = "<gpx><trk><name>Morning</name><trkseg><trkpt lat=\"10\" lon=\"20\"><time>2026-01-01T00:00:00Z</time></trkpt></trkseg><trkseg><trkpt lat=\"11\" lon=\"21\"><time>2026-01-01T00:00:05Z</time></trkpt></trkseg></trk><trk><name>Afternoon</name><trkseg><trkpt lat=\"12\" lon=\"22\"><time>2026-01-01T01:00:00Z</time></trkpt><trkpt lat=\"13\" lon=\"23\"><time>2026-01-01T01:00:02Z</time></trkpt></trkseg></trk></gpx>"
    let url = try file(gpx,"gpx"),info = try Telemetry.sessions(in:url)
    XCTAssertEqual(info.map(\.name),["Morning","Afternoon"]);XCTAssertEqual(info.map(\.samples),[2,2])
    let data = try Telemetry(url:url,session:2)
    XCTAssertEqual(data.duration,2);XCTAssertEqual(data.value("lat",at:0),12);XCTAssertNotNil(data.firstSampleUnixTime)
    let tcx = "<TrainingCenterDatabase><Activities><Activity><Id>First</Id><Lap><Track><Trackpoint><Time>2026-01-01T00:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint><Trackpoint><Time>2026-01-01T00:00:03Z</Time><DistanceMeters>10</DistanceMeters></Trackpoint></Track></Lap></Activity><Activity><Id>Second</Id><Lap><Track><Trackpoint><Time>2026-01-01T02:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint><Trackpoint><Time>2026-01-01T02:00:04Z</Time><DistanceMeters>20</DistanceMeters></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>"
    let activity = try Telemetry(url:file(tcx,"tcx"),session:2)
    XCTAssertEqual(activity.duration,4);XCTAssertEqual(activity.fileSessions.map(\.name),["First","Second"])
  }
  func testGUTMAUnitsUTCAndExplicitMissingValues() throws {
    let log:[String:Any] = ["exchange":["exchange_type":"flight_logging","message":["flight_logging":[
      "flight_logging_keys":["timestamp","gps_lon","gps_lat","speed","battery_voltage"],
      "flight_logging_items":[[0.5,20,10,3,12],[1,NSNull(),NSNull(),NSNull(),11],[1.5,21,11,4,10]],
      "logging_start_dtg":"2026-01-01T00:00:00.000Z","uom_system":"Metric"]]]]
    let text = String(decoding:try JSONSerialization.data(withJSONObject:log),as:UTF8.self)
    let data = try Telemetry(url:file(text,"json"))
    XCTAssertEqual(data.duration,1);XCTAssertEqual(data.value("lat",at:0),10)
    XCTAssertNil(data.value("lat",at:0.5));XCTAssertNil(data.value("speed",at:0.5))
    XCTAssertEqual(data.value("Battery voltage (V)",at:1),10)
    XCTAssertEqual(try XCTUnwrap(data.firstSampleUnixTime),1767225600.5,accuracy:1e-6)
    XCTAssertThrowsError(try Telemetry(url:file(text.replacingOccurrences(of:"Metric",with:"Imperial"),"json")))
    XCTAssertThrowsError(try Telemetry(url:file("{}","json")))
    let gap = try Telemetry(text:"Time,Speed\n0,1\n1,nan\n2,3\n")
    XCTAssertNil(gap.value("speed",at:1))
  }
  func testUnsupportedFormatsExplainConversion() throws {
    for ext in Telemetry.unsupportedLoggerExtensions {
      XCTAssertThrowsError(try Telemetry(url:file("unverified binary",ext))) {error in XCTAssertTrue(error.localizedDescription.contains("Export a timestamped"))}
    }
  }
}
