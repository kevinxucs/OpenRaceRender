import XCTest
@testable import RaceCore

final class SonyGPSTests:XCTestCase {
  func fixture() -> String {
    "@Sonygps/ver5.0/wgs-84/20260101120000.000/\n@Sonygpsoption/0/20260101120001.000/20260101120002.000/\n$GPRMC,120001.000,A,1000.0,N,02000.0,E,10,350,010126,,,A\n$GPRMC,120002.000,V,,,,,,,010126,,,N\n$GNRMC,120003.000,A,1000.006,N,02000.006,E,20,10,010126,,,A\n"
  }
  func file(_ data:Data,ext:String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
    try data.write(to:url);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testIdentifiedMOFFTextRetainsDatedClockUnitsAndVoidSamples() throws {
    let bytes = Data("MOFF8Original index".utf8)+Data([0,255,1])+Data(fixture().utf8)+Data([0,255])
    let url = try file(bytes,ext:"moff"),t = try Telemetry(url:url)
    XCTAssertEqual(t.count,3);XCTAssertEqual(t.duration,2);XCTAssertEqual(t.firstSampleUnixTime,1767268801)
    XCTAssertEqual(t.speed(at:0,unit:"m/s") ?? 0,5.14444,accuracy:1e-8)
    XCTAssertNil(t.value("lat",at:1));XCTAssertNil(t.speed(at:1,unit:"km/h"))
    XCTAssertEqual(t.value("lat",at:2) ?? 0,10.0001,accuracy:1e-8)
    XCTAssertTrue(t.warnings.contains{$0.contains("trim metadata is not interpreted")})
    XCTAssertTrue(t.warnings.contains{$0.contains("1.000 seconds")})
    XCTAssertEqual(try Data(contentsOf:url),bytes)
  }
  func testSonyRecordingsStaySeparateAcrossHeadersAndBinaryBoundaries() throws {
    let text = fixture()+fixture().replacingOccurrences(of:"1200",with:"1300")
    let url = try file(Data(text.utf8),ext:"log")
    XCTAssertEqual(try Telemetry.sessions(in:url).count,2)
    let t = try Telemetry(url:url,session:2);XCTAssertEqual(t.count,3);XCTAssertEqual(t.firstSampleUnixTime,1767272401)
    let binary = Data("MOFF8".utf8)+Data([0])+Data(fixture().utf8)+Data([0,255])+Data(fixture().utf8)
    XCTAssertEqual(try Telemetry.sessions(in:file(binary,ext:"moff")).count,2)
    XCTAssertThrowsError(try Telemetry(url:url,session:3))
    var p = RaceProject();var input = MediaInput(name:"Sony",path:url.path,kind:"data",legacyIndex:0);input.dataSession = 2;p.inputs = [input]
    let saved = try file(Data(),ext:"orrp");try p.save(saved)
    XCTAssertEqual(try Telemetry.loadSources(RaceProject.read(saved).inputs)[0]?.firstSampleUnixTime,1767272401)
  }
  func testUnsupportedBinaryVersionsDatumsAndCorruptClocksFailExplicitly() throws {
    for bytes in [Data("MOFF8index only".utf8),Data(fixture().utf8),Data("MOFF8\0".utf8)+Data(fixture().replacingOccurrences(of:"ver5.0",with:"ver6.0").utf8),Data("MOFF8\0".utf8)+Data(fixture().replacingOccurrences(of:"wgs-84",with:"other").utf8),Data("MOFF8\0".utf8)+Data(fixture().replacingOccurrences(of:"20260101",with:"20260230").utf8),Data("MOFF8\0".utf8)+Data(fixture().replacingOccurrences(of:"010126,,,A",with:"010126,,,A*00").utf8)] {
      XCTAssertThrowsError(try Telemetry(url:file(bytes,ext:"moff")))
    }
    let old = "@Sonygps/ver1.0/wgs-84/\n$GPRMC,120000,A,1000,N,02000,E,10,90,010126,,,A\n$GPRMC,120001,A,1000,N,02000,E,10,90,010126,,,A\n"
    XCTAssertThrowsError(try Telemetry(url:file(Data(fixture().replacingOccurrences(of:"ver5.0",with:"ver6.0").utf8),ext:"log")),"Future recording scopes cannot silently collapse into one generic NMEA run")
    XCTAssertEqual(try Telemetry(url:file(Data(old.utf8),ext:"log")).count,2,"Existing generic NMEA logs must remain usable")
  }
  func testMissingFieldsRemainMissingAndNativeMOFFMappingIsRefused() throws {
    let url = try file(Data("MOFF8\0".utf8)+Data(fixture().replacingOccurrences(of:",10,350,",with:",,350,").utf8),ext:"moff")
    XCTAssertNil(try Telemetry(url:url).speed(at:0,unit:"m/s"))
    var p = RaceProject();p.inputs = [MediaInput(name:"Sony",path:url.path,kind:"data",legacyIndex:0)]
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    XCTAssertTrue(Telemetry.supportedExtensions.contains("moff"));XCTAssertFalse(Telemetry.unsupportedLoggerExtensions.contains("moff"))
    let fractional = fixture().replacingOccurrences(of:"120002.000",with:"120002.200")
    let t = try Telemetry(url:file(Data("MOFF8\0".utf8)+Data(fractional.utf8),ext:"moff"))
    XCTAssertEqual(t.times[1],1.2);XCTAssertNil(t.speed(at:1.2,unit:"m/s"),"Epoch rounding must not hold the previous fix at the missing-sample boundary")
  }
}
