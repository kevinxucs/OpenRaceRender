import XCTest

@testable import RaceCore

final class RaceCoreTests: XCTestCase {
  func csv(_ text: String) throws -> Telemetry {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".csv")
    try text.write(to: u, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: u) }
    return try Telemetry(url: u)
  }
  func testQuotedCSVAndEscapes() {
    XCTAssertEqual(
      Telemetry.parseRow("1,\"turn, apex\",\"say \"\"go\"\"\",,3"),
      ["1", "turn, apex", "say \"go\"", "", "3"])
  }
  func testRaceChronoPreambleAndTimeNormalization() throws {
    let d = try csv(
      "This file is created using RaceChrono Pro\nSession title,\"A, B\"\n\nTime (s),Speed (m/s),RPM (rpm) *obd\n1700000000,10,\n1700000001,20,3000\n1700000002,,4000\n"
    )
    XCTAssertEqual(d.title, "A, B")
    XCTAssertEqual(d.times, [0, 1, 2])
    XCTAssertEqual(d.value("speed", at: 0.5)!, 15, accuracy: 0.001)
    XCTAssertNil(d.value("rpm", at: 0))
    XCTAssertEqual(d.value("rpm", at: 1.5)!, 3500, accuracy: 0.01)
    XCTAssertEqual(d.value("speed", at: 2)!, 20)
    XCTAssertNil(d.value("speed", at: 3))
    XCTAssertNil(d.value("speed", at: -1))
    XCTAssertEqual(d.speed(at: 0, unit: "mph")!, 22.369362921, accuracy: 0.0001)
  }
  func testDuplicateSamplesAndOutOfOrderRows() throws {
    let d = try csv("Time,Speed\n10,1\n11,2\n11,3\n10.5,99\n12,4\n")
    XCTAssertEqual(d.times, [0, 1, 2])
    XCTAssertEqual(d.value("speed", at: 1), 3)
    XCTAssertEqual(d.index(at: 1000), 2)
    XCTAssertEqual(d.index(at: -10), 0)
  }
  func testUnitsAndAlternateTimeFormats() throws {
    let d = try csv("Time\tKPH\tGear\n00:00:10\t36\t2\n00:00:11\t72\t3\n")
    XCTAssertEqual(d.speed(at: 0, unit: "m/s")!, 10, accuracy: 0.001)
    XCTAssertEqual(d.value("gear", at: 0.8, interpolate: false), 2)
    XCTAssertEqual(Telemetry.parseTime("01:02:03.25"), 3723.25)
  }
  func testLapBoundariesAndPartialLapExclusion() throws {
    let d = try csv(
      "Time,Speed,Lap #,Distance (m)\n0,1,,0\n2,2,1,20\n12,3,2,120\n21,4,3,220\n25,5,3,250\n")
    XCTAssertEqual(d.laps.count, 3)
    XCTAssertEqual(d.bestLap?.number, 2)
    XCTAssertEqual(d.bestLap?.duration, 9)
    XCTAssertEqual(d.lap(at: 15)?.number, 2)
    XCTAssertFalse(d.laps.last!.complete)
  }
  func testMissingTimeRejected() { XCTAssertThrowsError(try csv("RPM,Speed\n1000,1\n")) }
  func testMissingChannelIsNotZero() throws {
    let d = try csv("Time,Speed\n0,\n1,10\n")
    XCTAssertNil(d.value("speed", at: 0))
    XCTAssertNil(d.value("unavailable", at: 1))
  }
  func testTemplateTransformIsSymmetricAndLengthDependent() {
    let key = LegacyCodec.templateKey(0x1234_5678)
    let input = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) })
    let encoded = LegacyCodec.transform(input, key: key)
    XCTAssertNotEqual(input, encoded)
    XCTAssertEqual(LegacyCodec.transform(encoded, key: key), input)
    XCTAssertEqual(LegacyCodec.transform(Data(), key: key), Data())
    XCTAssertNotEqual(
      LegacyCodec.transform(Data(input.prefix(128)), key: key), Data(encoded.prefix(128)))
  }
  func testCodecKeyDeterministicAcrossHostArchitectures() {
    XCTAssertEqual(
      LegacyCodec.templateKey(0xbe87_390a).map { String(format: "%02x", $0) }.joined(),
      "f94fe07f33b2e9434b71acde18fb88b9ed326021c0c4f32a848cb2ed1f593cc9")
  }
  func syntheticRRP() -> Data {
    var b = Data(repeating: 0, count: 2600)
    b.replaceSubrange(0..<4, with: Data("RRP3".utf8))
    b.putU32(2152, 12)
    b.putU32(0, 16)
    b.putU32(2216, 20)
    b.putU32(56, 28)
    b.putU32(1, 32)
    b.putU32(344, 36)
    let o = 2200
    b.putUTF16("Test Speed", o, 128)
    b.putUTF16("Original Style", o + 128, 128)
    b.putU32(UInt32.max, o + 256)
    b.putFloat(5, o + 260)
    b.putFloat(10, o + 264)
    b.putFloat(20, o + 268)
    b.putFloat(30, o + 272)
    b[o + 280] = 30
    b[o + 281] = 2
    b[o + 284] = 1
    b[o + 293] = 100
    return b
  }
  func testRRPReaderAndLosslessPatch() throws {
    let original = syntheticRRP()
    var p = try LegacyReader.project(original, base: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(p.objects.count, 1)
    XCTAssertEqual(p.objects[0].kind, .speed)
    XCTAssertEqual(p.objects[0].x, 5)
    XCTAssertEqual(try p.patchLegacy(), original)
    p.objects[0].x = 9
    p.objects[0].name = "Edited"
    let patched = try p.patchLegacy()
    let reopened = try LegacyReader.project(patched, base: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(reopened.objects[0].x, 9)
    XCTAssertEqual(reopened.objects[0].name, "Edited")
    XCTAssertEqual(original.f32(2460), 5)
    p.objects.append(DisplayObject(name: "New", kind: .text))
    XCTAssertThrowsError(try p.patchLegacy())
  }
  func testLegacyAutoActivationIsVisibleAndPreservedByCopyExport() throws {
    var original = syntheticRRP();original[2200+284] = 0
    var p = try LegacyReader.project(original,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertTrue(p.objects[0].visible)
    XCTAssertEqual(p.objects[0].legacyActivation,0)
    XCTAssertEqual(try p.patchLegacy(),original)
    p.objects[0].x = 12
    XCTAssertEqual(try p.patchLegacy()[2200+284],0)
    p.objects[0].visible = false
    XCTAssertThrowsError(try p.patchLegacy())
  }
  func testDecodedGaugeSettingsPreserveUnchangedRRPCopy() throws {
    var original = syntheticRRP()
    original.append(Data(repeating: 0, count: 800))
    original.putU32(712, 2544)
    let bits = Double(120).bitPattern
    original.putU32(UInt32(truncatingIfNeeded: bits), 2548+264)
    original.putU32(UInt32(truncatingIfNeeded: bits >> 32), 2548+268)
    original[2548+296] = 135
    var project = try LegacyReader.project(original, base: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(project.objects[0].maximum, 120)
    XCTAssertEqual(try project.patchLegacy(), original)
    project.objects[0].gauge?.sweep = 180
    XCTAssertThrowsError(try project.patchLegacy())
  }
  func testMalformedCountsRejected() {
    var b = syntheticRRP()
    b.putU32(UInt32.max, 16)
    XCTAssertThrowsError(try LegacyReader.project(b, base: URL(fileURLWithPath: "/tmp")))
  }
  func testLegacyVideoAspectFlagAndCopyPreservation() throws {
    var b = syntheticRRP();b.putUTF16("Camera",2200,128);b[2200+280] = 10;b[2200+285] = 0
    var p = try LegacyReader.project(b,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(p.objects[0].picture?.maintainAspect,false)
    XCTAssertEqual(try p.patchLegacy(),b)
    p.objects[0].picture?.maintainAspect = true
    XCTAssertThrowsError(try p.patchLegacy())
  }
  func testImportedHUDDisappearsAfterDataEnds() throws {
    let data = try csv("Time,Speed\n0,10\n1,20\n")
    var p = RaceProject();var input = MediaInput(name:"Data",path:"",kind:"data",legacyIndex:1);input.duration = 1;p.inputs = [input]
    var display = DisplayObject(name:"Speed",kind:.speed);display.legacyType = 30;display.inputIndex = 1
    display.x = 0;display.y = 0;display.width = 100;display.height = 100
    var gauge = GaugeSettings();gauge.showLabels = false;gauge.showNumber = false;display.gauge = gauge;p.objects = [display]
    func alpha(_ time: Double) throws -> UInt8 {
      let c = try XCTUnwrap(CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,
        space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[1:data]),time:time,size:CGSize(width:64,height:64))
      return try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))[((32*64+32)*4)+3]
    }
    XCTAssertGreaterThan(try alpha(0.5),0)
    XCTAssertEqual(try alpha(1.5),0)
    p.objects[0].legacyType = nil
    XCTAssertGreaterThan(try alpha(1.5),0)
  }
  func testRRPInputPictureSettingsAndCompatibleCopy() throws {
    var b = Data(repeating: 0, count: 56 + 2216 + 56)
    b.replaceSubrange(0..<4, with: Data("RRP3".utf8))
    b.putU32(56, 12); b.putU32(1, 16); b.putU32(2216, 20); b.putU32(56, 28)
    b.putUTF16("Camera", 56, 128)
    let settings = 56 + 2216
    b[settings + 25] = 90; b[settings + 26] = 110; b[settings + 27] = 125
    var p = try LegacyReader.project(b, base: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(p.inputs[0].picture?.brightness, 0.9)
    XCTAssertEqual(p.inputs[0].picture?.contrast, 1.1)
    XCTAssertEqual(p.inputs[0].picture?.saturation, 1.25)
    XCTAssertEqual(try p.patchLegacy(), b)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer { try? FileManager.default.removeItem(at:url) }
    var earlier = p
    earlier.inputs[0].picture = nil
    earlier.inputs.append(MediaInput(name:"New camera",path:"",kind:"video",legacyIndex:0))
    try earlier.save(url)
    let recovered = try RaceProject.read(url)
    XCTAssertEqual(recovered.inputs[0].picture,p.inputs[0].picture)
    XCTAssertNil(recovered.inputs[1].picture)
    p.inputs[0].picture?.brightness = 1
    XCTAssertThrowsError(try p.patchLegacy())
    XCTAssertThrowsError(try LegacyReader.project(Data(b.dropLast()), base: URL(fileURLWithPath: "/tmp")))
  }
  func testTruncatedTemplateRejected() {
    XCTAssertThrowsError(try LegacyReader.template(Data(repeating: 0, count: 56)))
  }
  func testNativeProjectRoundTripPreservesOpaquePayload() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".orrp")
    defer { try? FileManager.default.removeItem(at: url) }
    var p = RaceProject()
    var o = DisplayObject(name: "Test", kind: .enhanced)
    o.legacyPayload = Data([1, 2, 3, 0, 255])
    p.objects = [o]
    try p.save(url)
    let q = try RaceProject.read(url)
    XCTAssertEqual(q.objects, p.objects)
    XCTAssertEqual(q.formatVersion, 1)
  }
  func testLowerLeftGeometryAndTimeFormatting() {
    let o = DisplayObject(name: "Test", kind: .text)
    let r = OverlayRenderer.rect(o, size: CGSize(width: 1920, height: 1080))
    XCTAssertEqual(r.minX, 96)
    XCTAssertEqual(r.minY, 54)
    XCTAssertEqual(clockText(125.125), "02:05.125")
  }
}
