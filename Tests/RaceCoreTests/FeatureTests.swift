import CoreImage
import XCTest
@testable import RaceCore

final class FeatureTests: XCTestCase {
  func testSegmentChangesInheritIndependentlyAndRespectExactBoundary() {
    var o = DisplayObject(name: "Camera", kind: .video)
    o.x = 5; o.inputIndex = 0
    var a = ObjectSegment(time: 10); a.x = 30; a.inputIndex = 1
    var b = ObjectSegment(time: 20); b.visible = false
    o.segments = [b, a]
    XCTAssertEqual(o.resolved(at: 9.999).x, 5)
    XCTAssertEqual(o.resolved(at: 10).inputIndex, 1)
    XCTAssertEqual(o.resolved(at: 25).x, 30)
    XCTAssertFalse(o.resolved(at: 20).visible)
    o.x = 8
    XCTAssertEqual(o.resolved(at: 11).x, 30)
    XCTAssertEqual(o.resolved(at: 5).x, 8)
    o.segments?[1].x = nil
    XCTAssertEqual(o.resolved(at: 25).x, 8)
  }
  func testEditingSegmentRecordsOnlyChangedFields() {
    var o = DisplayObject(name: "Title", kind: .text)
    var changed = o; changed.text = "Lap 2"; changed.opacity = 0.5
    o.editSegment(at: 15, from: o, to: changed)
    XCTAssertNil(o.segments?.first?.x)
    XCTAssertEqual(o.resolved(at: 15).text, "Lap 2")
    XCTAssertEqual(o.resolved(at: 14).text, "")
    o.x = 40
    XCTAssertEqual(o.resolved(at: 25).x, 40)
  }
  func testTrimRateOffsetAndDelayedStartUseSameMapping() {
    var i = MediaInput(name: "Camera", path: "", kind: "video", legacyIndex: 7)
    i.duration = 100; i.offset = 5
    var t = InputTiming(); t.trimStart = 10; t.trimEnd = 75; t.rate = 2; t.projectStart = 4
    i.timing = t
    var p = RaceProject(); p.inputs = [i]
    XCTAssertNil(p.media(for: 7, at: 3.99))
    XCTAssertEqual(p.sourceTime(for: 7, at: 4), 15)
    XCTAssertEqual(p.sourceTime(for: 7, at: 9), 25)
    XCTAssertNil(p.media(for: 7, at: 34))
    XCTAssertEqual(p.duration, 34)
    XCTAssertEqual(p.placements[0].projectTime(for: 25), 9)
    p.inputs[0].offset = -6
    XCTAssertEqual(p.placements[0].start, 7)
    XCTAssertEqual(p.sourceTime(for: 7, at: 7), 10)
  }
  func testJoinedClipsHaveOneRootAndNoOverlapAtCut() {
    var a = MediaInput(name: "A", path: "", kind: "video", legacyIndex: 0); a.duration = 10
    var b = MediaInput(name: "B", path: "", kind: "video", legacyIndex: 1); b.duration = 20; b.joinedTo = 0
    var p = RaceProject(); p.inputs = [a,b]
    XCTAssertEqual(p.media(for: 0, at: 9.99)?.input.name, "A")
    XCTAssertEqual(p.media(for: 0, at: 10)?.input.name, "B")
    XCTAssertEqual(p.sourceTime(for: 0, at: 10), 0)
    XCTAssertEqual(p.sourceTime(for: 0, at: 25), 15)
    XCTAssertNil(p.media(for: 1, at: 15))
    XCTAssertEqual(p.duration, 30)
  }
  func testLapExportRangeAccountsForSourceRateAndClampsToProject() {
    var i = MediaInput(name: "Data", path: "", kind: "data", legacyIndex: 2); i.duration = 100; i.offset = 10
    var t = InputTiming(); t.rate = 2; i.timing = t
    var p = RaceProject(); p.inputs = [i]; p.explicitDuration = 15
    let laps = [TelemetryLap(number: 1, start: 20, end: 40, complete: true), TelemetryLap(number: 2, start: 40, end: 60, complete: true)]
    XCTAssertEqual(p.lapRange(laps, inputIndex: 2, first: 1, last: 2), 5...15)
    XCTAssertNil(p.lapRange(laps, inputIndex: 2, first: 2, last: 1))
  }
  func load(_ text: String, ext: String) throws -> Telemetry {
    let data = Data(text.utf8)
    return try Telemetry(text: TelemetryFormats.csv(from: data, text: text, extension: ext))
  }
  func testGPXNamespacesFractionalTimeAndDerivedSpeed() throws {
    let data = try load("""
      <?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
      <trkpt lat="36" lon="-121"><ele>50</ele><time>2026-01-01T00:00:00.500Z</time></trkpt>
      <trkpt lat="36.0001" lon="-121"><ele>51</ele><time>2026-01-01T00:00:01.500Z</time></trkpt>
      </trkseg></trk></gpx>
      """, ext: "gpx")
    XCTAssertEqual(data.count, 2)
    XCTAssertEqual(data.duration, 1)
    XCTAssertEqual(data.speed(at: 0, unit: "m/s")!, 11.11949, accuracy: 0.01)
    XCTAssertEqual(data.value("lat", at: 0), 36)
  }
  func testTCXExtensionsAndMalformedXML() throws {
    let data = try load("""
      <?xml version="1.0"?><TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity><Lap><Track><Trackpoint><Time>2026-01-01T00:00:00Z</Time><Position><LatitudeDegrees>36</LatitudeDegrees><LongitudeDegrees>-121</LongitudeDegrees></Position><HeartRateBpm><Value>140</Value></HeartRateBpm><Extensions><TPX><Speed>12</Speed><Watts>200</Watts></TPX></Extensions></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>
      """, ext: "tcx")
    XCTAssertEqual(data.value("Speed (m/s)", at: 0), 12)
    XCTAssertEqual(data.value("Heart Rate", at: 0), 140)
    XCTAssertThrowsError(try load("<?xml version='1.0'?><gpx><trkpt", ext: "gpx"))
  }
  func testNMEAMergesTalkersValidFixesAndMidnightRollover() throws {
    let data = try load("""
      $GNRMC,235959.00,A,3600.000,N,12100.000,W,10,90,010126,,,A
      $GNGGA,235959.00,3600.000,N,12100.000,W,1,08,1.0,50,M,0,M,,
      $GNRMC,000001.00,A,3600.100,N,12100.000,W,20,90,020126,,,A
      $GNRMC,000002.00,V,3600.200,N,12100.000,W,50,90,020126,,,A
      $GPRMC,000003.00,A,3600.300,N,12100.000,W,50,90,020126,,,A*00
      """, ext: "nmea")
    XCTAssertEqual(data.count, 2)
    XCTAssertEqual(data.duration, 2)
    XCTAssertEqual(data.value("lon", at: 0), -121)
    XCTAssertEqual(data.value("Altitude", at: 0), 50)
    XCTAssertEqual(data.speed(at: 0, unit: "knots")!, 10, accuracy: 0.001)
  }
  func testVBOCoordinatesWestPositiveAndVelocityUnits() throws {
    let data = try load("""
      File created on 01/01/2026
      [column names]
      sats time lat long velocity heading height
      [data]
      8 120000.000 2160.000 7260.000 36.0 90 50
      8 120001.000 2160.006 7260.000 72.0 90 51
      """, ext: "vbo")
    XCTAssertEqual(data.value("lat", at: 0), 36)
    XCTAssertEqual(data.value("lon", at: 0), -121)
    XCTAssertEqual(data.speed(at: 0, unit: "m/s")!, 10, accuracy: 0.001)
  }
  func testEventDetectionRequiresActualStopAndMovement() throws {
    let d = try Telemetry(text: "Time,Speed (m/s),Gear\n0,0,0\n1,0,1\n2,5,2\n3,10,3\n4,0,1\n")
    XCTAssertEqual(d.syncEvents.first { $0.name == "Start moving after a stop" }?.time, 2)
    XCTAssertEqual(d.syncEvents.first { $0.name == "First stop after moving" }?.time, 4)
  }
  func testPictureCropFlipAndRotationExtent() {
    let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
    var s = PictureSettings(); s.left = 0.25; s.right = 0.25; s.rotation = 90; s.flipX = true
    let result = PictureProcessor.apply(image, settings: s)
    XCTAssertEqual(result.extent.width, 100, accuracy: 0.0001)
    XCTAssertEqual(result.extent.height, 100, accuracy: 0.0001)
    s.left = 10; s.right = 10
    XCTAssertGreaterThan(PictureProcessor.apply(image, settings: s).extent.height, 0)
  }
  func testNativeOldVersionWithoutNewKeysStillDecodes() throws {
    var p = RaceProject(); p.objects = [DisplayObject(name: "A", kind: .text)]
    let data = try JSONEncoder().encode(p)
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for key in ["explicitDuration", "rangeStart", "rangeEnd"] { json.removeValue(forKey: key) }
    let decoded = try JSONDecoder().decode(RaceProject.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(decoded.explicitDuration)
    XCTAssertNil(decoded.objects[0].segments)
    p.objects[0].segments = [ObjectSegment(time: 10)]
    let roundtrip = try JSONDecoder().decode(RaceProject.self, from: JSONEncoder().encode(p))
    XCTAssertEqual(roundtrip.objects[0].segments?.count, 1)
  }
  func testDataAssignmentsAndCalculatedChannels() throws {
    let d = try Telemetry(text: "Time,Wheel,Pedal\n0,10,50\n1,20,100\n")
    var settings = DataSettings(); settings.assignments["speed"] = "Wheel"
    var field = CalculatedField(); field.name = "Feet"; field.source = "Wheel"; field.multiply = 3.28084; field.add = 1
    settings.fields = [field]; d.configure(settings)
    XCTAssertEqual(d.speed(at: 0, unit: "m/s"), 10)
    XCTAssertEqual(d.value("Feet", at: 1)!, 66.6168, accuracy: 0.0001)
  }
  func testFinishLineDetectsForwardCrossingsWithInterpolatedTime() throws {
    let d = try Telemetry(text: "Time,Latitude,Longitude\n0,35.9999,-121\n2,36.0001,-121\n10,36.0001,-121.01\n20,35.9999,-121.01\n30,35.9999,-121\n32,36.0001,-121\n40,36.0002,-121\n")
    var settings = DataSettings(); settings.finishLine = FinishLine(latitude: 36, longitude: -121, heading: 0)
    d.configure(settings)
    XCTAssertEqual(d.laps.count, 3)
    XCTAssertEqual(d.laps[1].start, 1, accuracy: 0.001)
    XCTAssertEqual(d.laps[1].end, 31, accuracy: 0.001)
    XCTAssertTrue(d.laps[1].complete)
    XCTAssertEqual(d.bestLap?.duration, 30)
  }
  func makeFIT(_ records: Data) -> Data {
    var header = Data([14, 0x20, 0, 0, 0, 0, 0, 0, 46, 70, 73, 84])
    header.putU32(UInt32(records.count), 4)
    let hcrc = FITReader.crc(header); header.append(UInt8(truncatingIfNeeded: hcrc)); header.append(UInt8(truncatingIfNeeded: hcrc >> 8))
    header.append(records)
    let crc = FITReader.crc(header); header.append(UInt8(truncatingIfNeeded: crc)); header.append(UInt8(truncatingIfNeeded: crc >> 8))
    return header
  }
  func testConcatenatedFITActivitiesHaveIndependentSelections() throws {
    var a = Data([0x40,0,0,20,0,2,253,4,0x86,6,2,0x84])
    a.append(contentsOf:[0,31,0,0,0,0x10,0x27,0,33,0,0,0,0x20,0x4e])
    var b = a;b[b.count-1] = 0x75;b[b.count-2] = 0x30
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".fit")
    try (makeFIT(a)+makeFIT(b)).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
    XCTAssertEqual(try Telemetry.sessions(in:url).count,2)
    XCTAssertEqual(try Telemetry(url:url).speed(at:2,unit:"m/s"),20)
    XCTAssertEqual(try Telemetry(url:url,session:2).speed(at:2,unit:"m/s"),30)
  }
  func testFITDefinitionsEndianScalingAndCompressedTimestamps() throws {
    // Local 0: timestamp + speed. Local 1: speed, for compressed timestamps.
    var records = Data([0x40,0,0,20,0,2, 253,4,0x86, 6,2,0x84])
    records.append(contentsOf: [0, 0x1f,0,0,0, 0x10,0x27]) // t31, 10 m/s
    records.append(contentsOf: [0x41,0,1,0,20,1, 6,2,0x84]) // big-endian redefinition
    records.append(contentsOf: [0xa1, 0x4e,0x20]) // t33, 20 m/s
    let d = try Telemetry(text: FITReader.csv(makeFIT(records)))
    XCTAssertEqual(d.times, [0,2])
    XCTAssertEqual(d.speed(at: 0, unit: "m/s"), 10)
    XCTAssertEqual(d.speed(at: 2, unit: "m/s"), 20)
    var corrupted = makeFIT(records); corrupted[20] ^= 1
    XCTAssertThrowsError(try FITReader.csv(corrupted))
    XCTAssertThrowsError(try FITReader.csv(Data(makeFIT(records).dropLast())))
    XCTAssertNil(FITReader.number(Data([0xff,0xff]), type: 4, bigEndian: false))
    XCTAssertEqual(FITReader.number(Data([0xff]), type: 1, bigEndian: false), -1)
  }
  func testLegacyGaugeRangeLabelSweepAndColor() {
    var d = Data(repeating: 0, count: 712)
    d.putUTF16("Speed",128,128)
    let bits = Double(120).bitPattern
    d.putU32(UInt32(truncatingIfNeeded: bits),264); d.putU32(UInt32(truncatingIfNeeded: bits >> 32),268)
    d[296] = 135; d[298] = 90; d.putU32(0xff0a00,308)
    var object = DisplayObject(name: "Speedometer",kind: .speed); object.legacyType = 30; object.legacyPayload = d
    LegacyReader.inferDetails(&object)
    XCTAssertEqual(object.maximum,120)
    XCTAssertEqual(object.gauge?.label,"Speed")
    XCTAssertEqual(object.gauge?.sweep,135)
    XCTAssertEqual(object.gauge?.rotation,90)
    XCTAssertEqual(object.color,"#FF0A00")
  }
  func testCompactVideoStyleWithoutThumbnail() throws {
    var common = Data(repeating: 0,count: 36)
    common.putFloat(100,8); common.putFloat(100,12); common[20] = 10; common[21] = 1; common[24] = 1; common[33] = 100
    var file = Data("rro1".utf8); file.append(Data(repeating: 0,count: 16))
    file.putU32(0x41297ea8,4); file.putU32(36,16)
    file.append(LegacyCodec.transform(common,key: LegacyCodec.templateKey(0x41297ea8,salt:"RaceRender LLC")))
    file.append(Data(repeating: 0,count: 12))
    let project = try LegacyReader.style(file)
    XCTAssertEqual(project.objects.count,1)
    XCTAssertEqual(project.objects[0].kind,.video)
    XCTAssertEqual(project.objects[0].width,100)
  }
}
