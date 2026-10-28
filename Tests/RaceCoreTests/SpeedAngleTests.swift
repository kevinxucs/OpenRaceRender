import XCTest
@testable import RaceCore

final class SpeedAngleTests:XCTestCase {
  func fixture(unit:String = "KM/h",invalidFix:Bool = false) -> String {
    var lines = ["; Original synthetic SA fixture","#V=4.0.0=","#D=01-01-2026 12:00:00=","#S=Original track=","<trackplan #sectors=2>","</trackplan>","<timer #unit=\(unit)>","#2,0:00.250","#2,0:00.750","</timer>","<trace #pt=12>"]
    for i in 0..<13 {lines.append("10.\(i+100000),20.\(i+100000),-10,-11,25,26,\(36+i),-255,10,\(invalidFix && i == 5 ? 0 : 1),\(i == 2 || i == 7 ? "F" : "0")")}
    return (lines+["</trace>"]).joined(separator:"\n")
  }
  func file(_ text:String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sa")
    try Data(text.utf8).write(to:url);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testDocumentedFieldsUnitsClockAndPreciseLaps() throws {
    let data = try Telemetry(url:file(fixture()))
    XCTAssertEqual(data.count,13);XCTAssertEqual(data.duration,1.2,accuracy:1e-10)
    XCTAssertEqual(data.speed(at:0,unit:"km/h"),36);XCTAssertEqual(data.value("Lean angle (deg)",at:0),-10)
    XCTAssertEqual(data.value("SA second lean angle (deg)",at:0),-11);XCTAssertEqual(data.value("SA acceleration (raw)",at:0),25)
    XCTAssertNil(data.value("SA previous turn angle (deg)",at:0));XCTAssertNil(data.firstSampleUnixTime)
    XCTAssertEqual(data.locationName,"Original track")
    XCTAssertEqual(data.laps.map(\.start),[0,0.25,0.75]);XCTAssertEqual(data.laps.map(\.complete),[false,true,false])
    XCTAssertEqual(data.laps[1].duration,0.5,accuracy:1e-10)
    data.configure(DataSettings());data.configure(DataSettings())
    XCTAssertEqual(data.laps[1].start,0.25);XCTAssertFalse(data.recordedHeaders.contains{$0.hasPrefix("Calculated")})
    let mph = try Telemetry(url:file(fixture(unit:"MILE/h")));XCTAssertEqual(mph.speed(at:0,unit:"mph"),36)
  }
  func testInvalidGPSRowsRetainClockAndMotionWithoutStaleFix() throws {
    let data = try Telemetry(url:file(fixture(invalidFix:true)))
    XCTAssertEqual(data.count,13);XCTAssertNil(data.value("lat",at:0.5));XCTAssertNil(data.speed(at:0.5,unit:"km/h"))
    XCTAssertEqual(data.value("Lean angle (deg)",at:0.5),-10)
    XCTAssertTrue(data.warnings.contains{$0.contains("invalid GPS")})
    XCTAssertTrue(data.warnings.contains{$0.contains("raw scale")})
  }
  func testConcatenatedTracesRemainSelectableAndNativeMappingIsRefused() throws {
    let url = try file(fixture()+"\n"+fixture(unit:"MILE/h"))
    XCTAssertEqual(try Telemetry.sessions(in:url).count,2)
    XCTAssertEqual(try Telemetry(url:url,session:2).speed(at:0,unit:"mph"),36)
    XCTAssertThrowsError(try Telemetry(url:url,session:3))
    var p = RaceProject();p.inputs = [MediaInput(name:"SA",path:url.path,kind:"data",legacyIndex:0)]
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    XCTAssertTrue(Telemetry.supportedExtensions.contains("sa"));XCTAssertFalse(Telemetry.unsupportedLoggerExtensions.contains("sa"))
  }
  func testMalformedTraceCannotShiftTimeAndTimerDisagreementIsVisible() throws {
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"#V=4.0.0=",with:"#V=3.0.0="))))
    XCTAssertThrowsError(try Telemetry(url:file(fixture(unit:"unknown"))))
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"</trace>",with:""))))
    XCTAssertThrowsError(try Telemetry(url:file(fixture().replacingOccurrences(of:"25,26,36",with:"25,36"))))
    let mismatch = try Telemetry(url:file(fixture().replacingOccurrences(of:"0:00.250",with:"0:00.950")))
    XCTAssertTrue(mismatch.warnings.contains{$0.contains("disagree")});XCTAssertEqual(mismatch.laps[1].start,0.2)
    let count = try Telemetry(url:file(fixture().replacingOccurrences(of:"#pt=12",with:"#pt=99")))
    XCTAssertEqual(count.count,13);XCTAssertTrue(count.warnings.contains{$0.contains("point count")})
  }
}
