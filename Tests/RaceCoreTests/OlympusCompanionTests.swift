import XCTest
@testable import RaceCore

final class OlympusCompanionTests:XCTestCase {
  func root() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:root)};return root
  }
  func sensors(sync:Bool = true) -> String {
    "$OLTIM,20260101,235957\n$OLTMP,68,1,0\n$OLTIM,20260101,235959\n$OLTMP,71.6,1,0\n$OLTIM,20260102,000001\n$OLTMP,75.2,1,0\n"+(sync ? "$OLSNSGPSTIM,20260101,235957,20260101,235959\n" : "")
  }
  func gps() -> String {
    "$GPRMC,235958,A,1000.0,N,02000.0,E,10,350,010126,,,A\n$GPRMC,235959,A,1000.006,N,02000.006,E,20,355,010126,,,A\n$GPRMC,000000,V,,,,,,,020126,,,N\n$GNRMC,000001,A,1000.018,N,02000.018,E,30,5,020126,,,A\n$GNRMC,000002,A,1000.024,N,02000.024,E,40,10,020126,,,A\n$GNRMC,000003,A,1000.030,N,02000.030,E,50,15,020126,,,A\n"
  }
  func pair(_ root:URL,sensor:String? = nil,log:String? = nil) throws -> URL {
    let sns = root.appendingPathComponent("SNSLOG"),gps = root.appendingPathComponent("GPSLOG")
    try FileManager.default.createDirectory(at:sns,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:gps,withIntermediateDirectories:true)
    let url = sns.appendingPathComponent("26010101.SNS")
    try Data((sensor ?? sensors()).utf8).write(to:url);try Data((log ?? self.gps()).utf8).write(to:gps.appendingPathComponent("26010101.LOG"));return url
  }
  func testAutomaticPairAcrossMidnightUsesCorrectedUTCAndPreservesVoidFix() throws {
    let url = try pair(root()),t = try Telemetry(url:url)
    XCTAssertEqual(t.count,6);XCTAssertEqual(t.duration,5);XCTAssertEqual(t.firstSampleUnixTime,1767311998)
    XCTAssertNil(t.value("Ambient temperature (C)",at:0))
    XCTAssertEqual(t.value("Ambient temperature (C)",at:1),20)
    XCTAssertEqual(t.value("Ambient temperature (C)",at:2) ?? 0,21,accuracy:1e-8)
    XCTAssertEqual(t.speed(at:0,unit:"m/s") ?? 0,5.14444,accuracy:1e-8)
    XCTAssertNil(t.value("lat",at:2));XCTAssertNil(t.speed(at:2,unit:"m/s"));XCTAssertNil(t.value("lat",at:2.5))
    XCTAssertEqual(t.value("lat",at:3) ?? 0,10.0003,accuracy:1e-8)
    XCTAssertTrue(t.warnings.contains{$0.hasPrefix("Merged the matching GPSLOG")})
    XCTAssertEqual(try Telemetry.sessions(in:url).first?.samples,6)
    var p = RaceProject();var input = MediaInput(name:"Paired log",path:url.path,kind:"data",legacyIndex:7)
    input.offset = 2.25;p.inputs = [input];p.rangeStart = 1;p.rangeEnd = 3.5
    let saved = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("saved.orrp")
    try p.save(saved);let reopened = try RaceProject.read(saved),table = try Telemetry.loadSources(reopened.inputs)
    XCTAssertEqual(table[7]?.count,6);XCTAssertEqual(reopened.inputs[0].offset,2.25);XCTAssertEqual(reopened.rangeEnd,3.5)
    XCTAssertEqual(try String(contentsOf:url,encoding:.utf8),sensors(),"Pairing never rewrites either source")
  }
  func testMissingClockInvalidDatesOrAmbiguousCompanionsLeaveSensorsUsable() throws {
    let root = try root(),url = try pair(root,sensor:sensors(sync:false))
    var t = try Telemetry(url:url);XCTAssertEqual(t.count,3);XCTAssertNil(t.value("lat",at:0));XCTAssertTrue(t.warnings.contains{$0.contains("requires one consistent")})
    try Data(sensors().utf8).write(to:url)
    let duplicate = url.deletingPathExtension().appendingPathExtension("log");try Data(gps().utf8).write(to:duplicate)
    t = try Telemetry(url:url);XCTAssertEqual(t.count,3);XCTAssertTrue(t.warnings.contains{$0.contains("More than one")})
    try FileManager.default.removeItem(at:duplicate)
    let log = root.appendingPathComponent("GPSLOG/26010101.LOG")
    for invalid in [gps().replacingOccurrences(of:"020126",with:"020125"),gps().replacingOccurrences(of:"010126",with:"310226"),gps().replacingOccurrences(of:"010126,,,A",with:"010126,,,A*00"),"$GPGGA,120000,1000,N,02000,E,1,10,1,100,M,0,M,,\n"] {
      try Data(invalid.utf8).write(to:log);t = try Telemetry(url:url)
      XCTAssertEqual(t.count,3);XCTAssertTrue(t.warnings.contains{$0.hasPrefix("Olympus GPS companion was not merged")})
    }
  }
  func testNoOverlapWrongNameAndMovingPairCannotLeakOtherGPS() throws {
    let root = try root(),url = try pair(root,log:gps().replacingOccurrences(of:"0126",with:"0127"))
    var t = try Telemetry(url:url);XCTAssertEqual(t.count,3);XCTAssertTrue(t.warnings.contains{$0.contains("no overlapping")})
    try FileManager.default.moveItem(at:root.appendingPathComponent("GPSLOG/26010101.LOG"),to:root.appendingPathComponent("GPSLOG/different.LOG"))
    t = try Telemetry(url:url);XCTAssertEqual(t.count,3);XCTAssertFalse(t.warnings.contains{$0.hasPrefix("Merged")})
    let moved = root.appendingPathComponent("moved");try FileManager.default.createDirectory(at:moved,withIntermediateDirectories:true)
    try FileManager.default.copyItem(at:url,to:moved.appendingPathComponent(url.lastPathComponent))
    try Data(gps().utf8).write(to:moved.appendingPathComponent("26010101.log"))
    let p = try Telemetry(url:moved.appendingPathComponent(url.lastPathComponent));XCTAssertEqual(p.count,6)
  }
  func testDifferentRatesRetainSensorTimesWithoutBridgingGPSOutage() throws {
    let sensor = "$OLTIM,20260101,120000\n$OLTMP,20,0,0\n$OLTIM,20260101,120010\n$OLTMP,30,0,0\n$OLTIM,20260101,120020\n$OLTMP,40,0,0\n$OLSNSGPSTIM,20260101,120000,20260101,120000\n"
    let log = [0,1,2,20].map{i in "$GPRMC,1200\(String(format:"%02d",i)),A,1000.0,N,02000.0,E,10,350,010126,,,A"}.joined(separator:"\n")
    let t = try Telemetry(url:pair(root(),sensor:sensor,log:log))
    XCTAssertEqual(t.count,5);XCTAssertNil(t.value("lat",at:10));XCTAssertEqual(t.value("Ambient temperature (C)",at:10),30)
    XCTAssertEqual(t.speed(at:20,unit:"m/s") ?? 0,5.14444,accuracy:1e-8)
  }
}
