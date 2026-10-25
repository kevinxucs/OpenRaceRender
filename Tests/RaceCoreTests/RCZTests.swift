import XCTest
@testable import RaceCore

final class RCZTests: XCTestCase {
  let epoch: Int64 = 1_700_000_000_000
  func ints(_ values: [Int32]) -> Data { values.reduce(into: Data()) { data, v in var n = v.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } } }
  func longs(_ values: [Int64]) -> Data { values.reduce(into: Data()) { data, v in var n = v.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } } }
  func doubles(_ values: [Double]) -> Data { values.reduce(into: Data()) { data, v in var n = v.bitPattern.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } } }
  func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
  func archive(_ files: [(String, Data)]) -> Data {
    var output = Data(), directory = Data()
    func word(_ n: Int, _ data: inout Data) { var v = UInt16(n).littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    func dword(_ n: UInt32, _ data: inout Data) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    for (name, bytes) in files {
      let offset = UInt32(output.count), label = Data(name.utf8), crc = ZIPArchive.checksum(bytes)
      dword(0x04034b50, &output); word(20, &output); word(0x800, &output); word(0, &output)
      word(0, &output); word(0, &output); dword(crc, &output)
      dword(UInt32(bytes.count), &output); dword(UInt32(bytes.count), &output)
      word(label.count, &output); word(0, &output); output += label; output += bytes
      dword(0x02014b50, &directory); word(20, &directory); word(20, &directory); word(0x800, &directory)
      word(0, &directory); word(0, &directory); word(0, &directory); dword(crc, &directory)
      dword(UInt32(bytes.count), &directory); dword(UInt32(bytes.count), &directory)
      word(label.count, &directory); word(0, &directory); word(0, &directory); word(0, &directory)
      word(0, &directory); dword(0, &directory); dword(offset, &directory); directory += label
    }
    let start = UInt32(output.count); output += directory
    dword(0x06054b50, &output); word(0, &output); word(0, &output)
    word(files.count, &output); word(files.count, &output)
    dword(UInt32(directory.count), &output); dword(start, &output); word(0, &output)
    return output
  }
  func read(_ files: [(String, Data)]) throws -> Telemetry {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".RCZ")
    defer { try? FileManager.default.removeItem(at: url) }
    try archive(files).write(to: url)
    return try Telemetry(url: url)
  }
  func testIndependentClocksUnitsDeviceRolesAndMissingValues() throws {
    let t = [epoch, epoch + 1000, epoch + 2000]
    let d = try read([
      ("session.json", try json(["title": "Clock test"])),
      ("sessionfragment.json", try json(["primaryGpsDeviceIndex": 42, "devices2": [
        ["selector": ["id": 42, "type": 1]], ["selector": ["id": 7, "type": 2]], ["selector": ["id": 88, "type": 12]],
        ["selector": ["id": 102, "type": 3], "gyroBias": [-1.77344, -0.60249, 2.74557]] as [String: Any]]])),
      ("channel_1_42_0_1_1", longs(t)), ("channel_1_42_0_4_0", ints([10000, 20000, 30000])),
      ("channel_1_42_0_3_1", ints([222000000, -732000000, 222006000, -731994000, 222012000, -731988000])),
      ("channel_1_42_0_2_1", longs([0, 100000, 250000])),
      ("channel_1_42_0_6_0", ints([359000, 1000, 3000])),
      ("channel_3_102_0_1_1", longs(t)), ("channel_3_102_0_12_0", ints([1000, 1000, 1000])),
      ("channel_3_102_0_14_0", ints([0, 0, 0])),
      ("channel_2_7_0_1_1", longs([epoch, epoch + 500, epoch + 1000, epoch + 1500, epoch + 2000])),
      ("channel_2_7_0_9_0", ints([9807, .max, 0, -9807, 0])),
      ("channel_12_88_10024_1_1", longs([epoch + 250, epoch + 750, epoch + 1250, epoch + 1750])),
      ("channel2_12_88_10024_10024_3", doubles([1000, 2000, 3000, 4000])),
      ("channel_12_88_1004_1_1", longs([epoch + 250, epoch + 1250])),
      ("channel2_12_88_1004_1004_3", doubles([1, 2])),
      ("channel_12_88_7_1_1", longs(t)), ("channel2_12_88_7_7_3", doubles([9.80665, 0, -9.80665])),
      ("channel_12_88_4_1_1", longs(t)), ("channel2_12_88_4_4_3", doubles([90, 90, 90])),
    ])
    XCTAssertEqual(d.title, "Clock test"); XCTAssertEqual(d.duration, 2)
    XCTAssertEqual(d.firstSampleUnixTime, Double(epoch) / 1000)
    XCTAssertEqual(d.count, 9)
    XCTAssertEqual(d.speed(at: 0.5, unit: "km/h")!, 54, accuracy: 0.00001)
    XCTAssertEqual(d.value("rpm", at: 0.5)!, 1500, accuracy: 0.00001)
    XCTAssertNil(d.value("rpm", at: 0))
    XCTAssertEqual(d.value("gear", at: 0.75), 1)
    XCTAssertEqual(d.value("gear", at: 1.25), 2)
    XCTAssertEqual(d.value("gear", at: 1.2499), 1)
    XCTAssertEqual(d.value("gy", at: 0), 1)
    XCTAssertEqual(d.value("gy", at: 2), -1)
    XCTAssertNil(d.aliases["gx"]) // Raw phone X does not imply vehicle longitudinal G.
    XCTAssertNil(d.value("X acceleration", at: 0.5))
    XCTAssertEqual(d.value("distance", at: 2), 250)
    XCTAssertEqual(d.value("lat", at: 0), 37)
    XCTAssertEqual(d.value("lon", at: 0), -122)
    XCTAssertEqual(d.value("Heading", at: 0.5), 359)
    XCTAssertEqual(d.value("Heading", at: 0.9999), 359)
    XCTAssertEqual(d.value("X rotation rate", at: 0)!, 2.773, accuracy: 0.000001)
    XCTAssertEqual(d.value("Z rotation rate", at: 0)!, -2.746, accuracy: 0.000001)
    XCTAssertFalse(d.mapPoints.isEmpty); XCTAssertTrue(d.warnings.isEmpty)
  }
  func testExactLapBoundariesPartialAndInvalidLaps() throws {
    let d = try read([
      ("session.json", try json(["laps": [
        ["number": 1, "startTimestamp": epoch - 5000, "finishTimestamp": epoch + 5000],
        ["number": 2, "startTimestamp": epoch + 5000, "finishTimestamp": epoch + 15000],
        ["number": 3, "startTimestamp": epoch + 15000, "finishTimestamp": epoch + 25000, "isInvalid": true],
        ["number": 4, "startTimestamp": epoch + 25000]]])),
      ("channel_1_9_0_1_1", longs([epoch, epoch + 10000, epoch + 20000, epoch + 30000])),
      ("channel_1_9_0_4_0", ints([1000, 2000, 3000, 4000])),
    ])
    XCTAssertEqual(d.laps.map(\.number), [1, 2, 3, 4])
    XCTAssertEqual(d.laps.map(\.complete), [false, true, false, false])
    XCTAssertEqual(d.laps.map(\.start), [0, 5, 15, 25])
    XCTAssertEqual(d.bestLap?.number, 2)
    XCTAssertEqual(d.lap(at: 15)?.number, 3)
    XCTAssertEqual(d.value("lap", at: 5, interpolate: false), 2)
    XCTAssertEqual(d.syncEvents.filter { $0.name.contains("Lap") }.map(\.time), [0, 5, 15, 25])
  }
  func testWrappedSessionResumesKeepGapsAndCumulativeDistance() throws {
    let d = try read([
      ("recording/session.json", try json(["title": "Paused"])),
      ("recording/channel_1_9_0_1_1", longs([epoch, epoch + 1000])),
      ("recording/channel_1_9_0_4_0", ints([0, 10000])),
      ("recording/channel_1_9_0_2_1", longs([0, 1000])),
      ("recording/resume_1/channel_1_9_0_1_1", longs([epoch + 3000, epoch + 4000])),
      ("recording/resume_1/channel_1_9_0_4_0", ints([20000, 30000])),
      ("recording/resume_1/channel_1_9_0_2_1", longs([0, 1500])),
    ])
    XCTAssertEqual(d.duration, 4)
    XCTAssertNil(d.speed(at: 2, unit: "m/s"))
    XCTAssertEqual(d.speed(at: 3, unit: "m/s"), 20)
    XCTAssertEqual(d.value("distance", at: 4), 2.5)
  }
  func testExportScopeLimitsBufferedSamplesWithoutUsingCreationTimeAsZero() throws {
    let d = try read([
      ("session.json", try json(["timeCreated": epoch - 10000, "firstTimestamp": epoch + 500, "latestTimestamp": epoch + 2500])),
      ("channel_1_9_0_1_1", longs([epoch, epoch + 1000, epoch + 2000, epoch + 3000])),
      ("channel_1_9_0_4_0", ints([10000, 20000, 30000, 40000])),
    ])
    XCTAssertEqual(d.firstSampleUnixTime, Double(epoch + 500) / 1000)
    XCTAssertEqual(d.times, [0, 0.5, 1.5, 2])
    XCTAssertEqual(d.duration, 2)
    XCTAssertEqual(d.speed(at: 0, unit: "m/s"), 15)
    XCTAssertEqual(d.speed(at: 2, unit: "m/s"), 35)
  }
  func testSensorPositionsSentinelsAndUnknownChannels() throws {
    let t = longs([epoch, epoch + 1000])
    let d = try read([
      ("session.json", try json([:] as [String: String])),
      ("channel_5_300_197622_1_1", t), ("channel2_5_300_197622_197622_3", doubles([270, 271])),
      ("channel_5_300_99317_1_1", t), ("channel2_5_300_99317_99317_3", doubles([25, 26])),
      ("channel_4_5_0_1_1", t), ("channel_4_5_0_12345_0", ints([1234567, .max])),
    ])
    XCTAssertEqual(d.value("Tyre pressure FL", at: 0), 270)
    XCTAssertEqual(d.value("Tyre temperature RR", at: 1), 26)
    XCTAssertEqual(d.value("Raw RCZ channel 12345", at: 0), 1234567)
    XCTAssertNil(d.value("Raw RCZ channel 12345", at: 1))
    XCTAssertEqual(d.warnings.count, 1)
  }
  func testResumedDistanceUsesVisibleFragmentBoundaries() throws {
    let d = try read([
      ("session.json", try json([:] as [String: String])),
      ("sessionfragment.json", try json(["firstTimestamp": epoch + 500, "latestTimestamp": epoch + 1500])),
      ("channel_1_9_0_1_1", longs([epoch, epoch + 1000, epoch + 2000])),
      ("channel_1_9_0_2_1", longs([0, 1000, 2000])),
      ("resume_1/sessionfragment.json", try json(["firstTimestamp": epoch + 3500, "latestTimestamp": epoch + 4500])),
      ("resume_1/channel_1_9_0_1_1", longs([epoch + 3000, epoch + 4000, epoch + 5000])),
      ("resume_1/channel_1_9_0_2_1", longs([0, 2000, 4000])),
    ])
    XCTAssertEqual(d.firstSampleUnixTime, Double(epoch + 500) / 1000)
    XCTAssertEqual(d.value("distance", at: 1), 1.5)
    XCTAssertNil(d.value("distance", at: 2))
    XCTAssertEqual(d.value("distance", at: 3), 1.5)
    XCTAssertEqual(d.value("distance", at: 4), 3.5)
  }
  func testDuplicateTimesPaddingAndMalformedStreams() throws {
    let files = [("session.json", try json([:] as [String: String])),
      ("channel_1_9_0_1_1", longs([epoch, epoch + 1000, epoch + 1000, 0, .max])),
      ("channel_1_9_0_4_0", ints([1000, 2000, 3000, 0, 0]))]
    let d = try read(files)
    XCTAssertEqual(d.count, 2); XCTAssertEqual(d.speed(at: 1, unit: "m/s"), 3)
    XCTAssertThrowsError(try read([files[0], (files[1].0, longs([epoch + 1, epoch])), files[2]]))
    XCTAssertThrowsError(try read([files[0], files[1], (files[2].0, Data([1]))]))
    XCTAssertThrowsError(try read([("vehicleProfile.json", try json([:] as [String: String]))]))
    XCTAssertThrowsError(try read(files + [("other/session.json", try json([:] as [String: String]))]))
  }
  func testZIPIntegrityBoundsAndRealDeflateEncoding() throws {
    XCTAssertEqual(ZIPArchive.checksum(Data("123456789".utf8)), 0xcbf43926)
    let files = [("session.json", try json(["title": "CRC"])),
      ("channel_1_9_0_1_1", longs([epoch, epoch + 1000])), ("channel_1_9_0_4_0", ints([1000, 2000]))]
    var bad = archive(files); bad[30 + files[0].0.utf8.count] ^= 1
    XCTAssertThrowsError(try RCZReader.read(bad, title: "Bad"))
    XCTAssertThrowsError(try ZIPArchive(Data(bad.dropLast())))
    XCTAssertThrowsError(try ZIPArchive(archive(files + [files[0]])))
    XCTAssertThrowsError(try ZIPArchive(archive([("../session.json", Data())])))
    var oversized = archive(files)
    let directory = Int(oversized.u32(oversized.count - 6))
    oversized.putU32(UInt32(ZIPArchive.maximumEntrySize + 1), directory + 24)
    XCTAssertThrowsError(try ZIPArchive(oversized))
    var encrypted = archive(files); encrypted[directory + 8] |= 1
    XCTAssertThrowsError(try ZIPArchive(encrypted))
    let encoded = "UEsDBBQAAAAIAAAAIVA1NFnYHAAAABoAAAAMAAAAc2Vzc2lvbi5qc29uq1YqySzJSVWyUlAKrswryUgtyUxWCHKOUqoFAFBLAwQUAAAACAAAACFQzTGfzw4AAAAQAAAAEgAAAGNoYW5uZWxfMV80Ml8wXzFfMWPIeHq+m5GB4UU2hAYAUEsDBBQAAAAIAAAAIVCk5rXJCgAAAAgAAAASAAAAY2hhbm5lbF8xXzQyXzBfNF8wE1BnYFDwY2AAAFBLAQIUAxQAAAAIAAAAIVA1NFnYHAAAABoAAAAMAAAAAAAAAAAAAACAAQAAAABzZXNzaW9uLmpzb25QSwECFAMUAAAACAAAACFQzTGfzw4AAAAQAAAAEgAAAAAAAAAAAAAAgAFGAAAAY2hhbm5lbF8xXzQyXzBfMV8xUEsBAhQDFAAAAAgAAAAhUKTmtckKAAAACAAAABIAAAAAAAAAAAAAAIABhAAAAGNoYW5uZWxfMV80Ml8wXzRfMFBLBQYAAAAAAwADALoAAAC+AAAAAAA="
    let decoded = try RCZReader.read(try XCTUnwrap(Data(base64Encoded: encoded)), title: "Fallback")
    XCTAssertEqual(decoded.title, "Synthetic RCZ"); XCTAssertEqual(decoded.times, [0, 1])
    XCTAssertEqual(decoded.columns[decoded.aliases["speed"]!], [10, 20])
  }
}
