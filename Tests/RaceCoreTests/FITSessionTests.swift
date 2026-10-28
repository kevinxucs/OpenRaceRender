import XCTest
@testable import RaceCore

final class FITSessionTests:XCTestCase {
  let origin:UInt32 = 1_000_000_000
  func word(_ value:UInt32) -> Data {var n = value.littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
  func container(_ body:Data) -> Data {
    var b = Data([14,0x20,0,0])+word(UInt32(body.count))+Data(".FIT".utf8)
    let header = FITReader.crc(b);b.append(contentsOf:[UInt8(truncatingIfNeeded:header),UInt8(truncatingIfNeeded:header>>8)])
    b.append(body);let crc = FITReader.crc(b);b.append(contentsOf:[UInt8(truncatingIfNeeded:crc),UInt8(truncatingIfNeeded:crc>>8)]);return b
  }
  func activity(summaryFirst:Bool = false,ranges:[(UInt32,UInt32)] = [(0,2000),(2,2000)],samples:[UInt32] = [0,1,2,3,4],laps:[UInt32] = []) -> Data {
    let definitions = Data([0x40,0,0,20,0,2,253,4,0x86,6,2,0x84,0x41,0,0,18,0,3,253,4,0x86,2,4,0x86,7,4,0x86,0x42,0,0,19,0,1,2,4,0x86])
    var summaries = Data(),records = Data()
    for (start,elapsed) in ranges {summaries.append(1);summaries.append(word(origin+start));summaries.append(word(origin+start));summaries.append(word(elapsed))}
    for value in samples {records.append(0);records.append(word(origin+value));var speed = UInt16((value+1)*1000).littleEndian;records.append(withUnsafeBytes(of:&speed){Data($0)})}
    for start in laps {records.append(2);records.append(word(origin+start))}
    return container(definitions+(summaryFirst ? summaries+records : records+summaries))
  }
  func file(_ data:Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".fit");try data.write(to:url)
    addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testSummaryFirstAndLastUseElapsedRangesAndPerSessionUTC() throws {
    for first in [false,true] {
      let url = try file(activity(summaryFirst:first)),a = try Telemetry(url:url),b = try Telemetry(url:url,session:2)
      XCTAssertEqual(a.fileSessions.map(\.samples),[2,3]);XCTAssertEqual(a.duration,1);XCTAssertEqual(b.duration,2)
      XCTAssertEqual(a.speed(at:1,unit:"m/s"),2);XCTAssertEqual(b.speed(at:0,unit:"m/s"),3)
      XCTAssertEqual(a.firstSampleUnixTime,Double(origin)+631065600);XCTAssertEqual(b.firstSampleUnixTime,Double(origin)+631065602)
      XCTAssertThrowsError(try Telemetry(url:url,session:3))
    }
  }
  func testGapsKeepUnassignedRecordsAndLapsRestartWithoutBleeding() throws {
    let url = try file(activity(ranges:[(0,1000),(3,1000)],samples:[0,1,2,3,4,5],laps:[0,1,3,4]))
    let a = try Telemetry(url:url),b = try Telemetry(url:url,session:2),unassigned = try Telemetry(url:url,session:3)
    XCTAssertEqual(a.fileSessions.map(\.samples),[2,2,2]);XCTAssertEqual(a.value("Lap #",at:1),2);XCTAssertEqual(b.value("Lap #",at:0),1)
    XCTAssertEqual(unassigned.times,[0,3]);XCTAssertEqual(unassigned.speed(at:0,unit:"m/s"),3);XCTAssertEqual(unassigned.speed(at:3,unit:"m/s"),6)
    XCTAssertTrue(a.warnings.contains{$0.contains("outside session")})
  }
  func testConcatenatedContainersFlattenInternalSelectionsAndCacheIndependently() throws {
    let url = try file(activity()+activity(summaryFirst:true))
    XCTAssertEqual(try Telemetry.sessions(in:url).count,4)
    XCTAssertEqual(try Telemetry.sessions(in:url)[3].name,"Activity 2 · Session 2")
    var a = MediaInput(name:"First",path:url.path,kind:"data",legacyIndex:0),b = a
    a.dataSession = 1;b.id = UUID();b.legacyIndex = 1;b.dataSession = 4
    let tables = try Telemetry.loadSources([a,b])
    XCTAssertEqual(tables[0]?.speed(at:0,unit:"m/s"),1);XCTAssertEqual(tables[1]?.speed(at:0,unit:"m/s"),3)
    XCTAssertFalse(tables[0] === tables[1])
  }
  func testOverlapsMissingBoundsAndEmptySummariesAreExplicit() throws {
    XCTAssertThrowsError(try FITReader.sessions(activity(ranges:[(0,3000),(2,2000)])))
    XCTAssertThrowsError(try FITReader.sessions(activity(ranges:[(0,2000),(2,UInt32.max)])))
    let single = try FITReader.sessions(activity(ranges:[(0,UInt32.max)]))
    XCTAssertEqual(single.count,1);XCTAssertEqual(single[0].count,5);XCTAssertFalse(single[0].warnings.isEmpty)
    let empty = try FITReader.sessions(activity(ranges:[(0,2000),(2,2000),(10,1000)]))
    XCTAssertEqual(empty.count,2);XCTAssertTrue(empty[0].warnings.contains{$0.contains("no records")})
    let duplicate = try FITReader.sessions(activity(ranges:[(0,2000),(0,2000),(2,2000)]))
    XCTAssertEqual(duplicate.count,2)
  }
  func testDeviceRelativeClocksHaveNoUTCAndCompressedOverflowIsRefused() throws {
    var body = Data([0x40,0,0,20,0,2,253,4,0x86,6,2,0x84,0]);body.append(word(31));body.append(contentsOf:[0xe8,3])
    XCTAssertNil(try FITReader.sessions(container(body))[0].epoch)
    var overflow = Data([0x40,0,0,20,0,2,253,4,0x86,6,2,0x84,0]);overflow.append(word(UInt32.max-1));overflow.append(contentsOf:[0xe8,3,0x81,0xe8,3])
    XCTAssertThrowsError(try FITReader.sessions(container(overflow)))
  }
  func testMissingRecordValuesDoNotHoldEarlierTelemetry() throws {
    let csv = FITReader.csv(rows:[[253:Double(origin),6:1000],[253:Double(origin+1)],[253:Double(origin+2),6:3000]],lapStarts:[])
    let data = try Telemetry(text:csv)
    XCTAssertEqual(data.speed(at:0,unit:"m/s"),1);XCTAssertNil(data.speed(at:1,unit:"m/s"));XCTAssertEqual(data.speed(at:2,unit:"m/s"),3)
  }
}
