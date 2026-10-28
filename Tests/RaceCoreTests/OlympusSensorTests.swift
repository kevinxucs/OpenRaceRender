import XCTest
@testable import RaceCore

final class OlympusSensorTests:XCTestCase {
  func fixture() -> String {
    "$OLTIM,20260101,235959.5\n$OLCMP,90\n$OLPRE,1000,100,328.084\n$OLTMP,68,1,0\n$OLACC,1000,-20,30\n$OLTIM,20260102,000001.5\n$OLPRE,1001,101,331.365\n$OLTMP,21,0,0\n$OLACC,1001,-21,31\n$OLTIM,20260102,000003.5\n$OLTMP,70,1,0\n"
  }
  func file(_ text:String,ext:String = "sns") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
    try Data(text.utf8).write(to:url);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testObservedSentencesTemperatureUnitsMidnightAndMissingValues() throws {
    let t = try Telemetry(url:file(fixture()))
    XCTAssertEqual(t.count,3);XCTAssertEqual(t.duration,4)
    XCTAssertEqual(t.firstSampleUnixTime,1767311999.5)
    XCTAssertEqual(t.value("Ambient temperature (C)",at:0),20);XCTAssertEqual(t.value("Ambient temperature (C)",at:2),21)
    XCTAssertEqual(t.value("Atmospheric pressure (hPa)",at:0),1000)
    XCTAssertEqual(t.value("Camera acceleration X (raw)",at:0),1000)
    XCTAssertEqual(t.value("Camera compass (deg)",at:0),90)
    XCTAssertNil(t.value("Camera compass (deg)",at:2));XCTAssertNil(t.value("Atmospheric pressure (hPa)",at:4))
    XCTAssertNil(t.value("gx",at:0));XCTAssertNil(t.value("heading",at:0))
    XCTAssertTrue(t.warnings.contains{$0.contains("without GPS clock correction")})
    XCTAssertEqual(try Telemetry(url:file(fixture(),ext:"snslog")).count,3)
  }
  func testClockCorrectionRequiresOneConsistentOffset() throws {
    let sync = "$OLSNSGPSTIM,20260101,235959,20260102,000001\n"
    let t = try Telemetry(url:file(fixture()+sync+sync))
    XCTAssertEqual(t.firstSampleUnixTime,1767312001.5);XCTAssertEqual(t.duration,4)
    let changed = try Telemetry(url:file(fixture()+sync+"$OLSNSGPSTIM,20260102,000001,20260102,000004\n"))
    XCTAssertNil(changed.firstSampleUnixTime);XCTAssertTrue(changed.warnings.contains{$0.contains("offsets change")})
    XCTAssertEqual(changed.duration,4)
  }
  func testMalformedOrAmbiguousPacketsFailWithoutShiftingClock() throws {
    for invalid in ["20260230,235959.5","20260101,240000","20260101,235960","20260101,235959.","٢٠٢٦٠١٠١,235959"] {
      XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"20260101,235959.5",with:invalid))))
    }
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"$OLACC,1000,-20,30",with:"$OLACC,1000,-20"))))
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"$OLCMP,90",with:"$OLCMP,90\n$OLCMP,91"))))
    XCTAssertThrowsError(try Telemetry(url:file("$OLCMP,90\n"+fixture())))
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"20260102,000001.5",with:"20260101,235959.5"))))
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"$OLCMP,90",with:"$OLCMP,90*00"))))
    let payload = "OLCMP,90",check = payload.utf8.reduce(UInt8(0),^)
    XCTAssertNoThrow(try Telemetry(url:file(fixture().replacingOccurrences(of:"$OLCMP,90",with:String(format:"$%@*%02X",payload,check)))))
    let missing = try Telemetry(url:file(fixture().replacingOccurrences(of:"$OLTMP,68,1,0",with:"$OLTMP,68,9,0")+"$OLUNKNOWN,1\n"))
    XCTAssertNil(missing.value("Ambient temperature (C)",at:0));XCTAssertTrue(missing.warnings.contains{$0.contains("Unknown Olympus")})
  }
  func testExplicitManualMappingAndNativeMappingRefusal() throws {
    let url = try file(fixture());var settings = DataSettings();settings.assignments["heading"] = "Camera compass (deg)"
    let t = try Telemetry(url:url,settings:settings);XCTAssertEqual(t.value("heading",at:0),90)
    var p = RaceProject();p.inputs = [MediaInput(name:"Sensors",path:url.path,kind:"data",legacyIndex:0)]
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    XCTAssertTrue(Telemetry.supportedExtensions.contains("sns"));XCTAssertFalse(Telemetry.unsupportedLoggerExtensions.contains("sns"))
  }
}
