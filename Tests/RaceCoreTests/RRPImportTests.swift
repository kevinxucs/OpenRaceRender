import XCTest
@testable import RaceCore

final class RRPImportTests: XCTestCase {
  func header(inputs: Int, objects: Int) -> Data {
    var b = Data(repeating: 0, count: 2152)
    b.replaceSubrange(0..<4, with: Data("RRP3".utf8))
    for (offset, value) in [(12,2152),(16,inputs),(20,2216),(24,11312),(28,56),(32,objects),(36,344),(40,24),(44,208)] { b.putU32(UInt32(value), offset) }
    b[2120] = 2; b[2121] = 255; b[2126] = 2
    b.putUTF16("Synthetic import notes", 48, 2048)
    return b
  }
  func input(_ name: String, type: UInt8 = 1, parent: UInt8 = 255, duration: Double = 6, start: Double = 0, end: Double = 356400, rate: Double = 1) -> Data {
    var b = Data(repeating: 0, count: 2216)
    b.putUTF16(name, 0, 128); b.putUTF16(type == 5 ? "*JOINV*" : name + (type == 4 ? ".csv" : ".mp4"), 128, 2048)
    b[2176] = type; b[2178] = parent; b.putU32(320 | (180 << 16), 2180)
    b.putFloat(duration, 2184); b.putFloat(start, 2192); b.putFloat(end, 2196); b.putFloat(rate, 2204)
    if type == 5 { return b }
    var settings = Data(repeating: 0, count: type == 4 ? 11312 : 56)
    if type != 4 { settings[0] = 100; settings[1] = 100; settings[25] = 100; settings[26] = 100; settings[27] = 100; settings[30] = 100 }
    return b + settings
  }
  func text(_ content: String) -> Data {
    var b = Data(repeating: 0, count: 808)
    b.putU32(0xffffff, 0); b.putUTF16(content, 4, 512); b.putUTF16("Helvetica", 516, 128); b.putFloat(32, 644)
    return b
  }
  func object(_ name: String, type: UInt8 = 10, input: UInt8 = 0, payload: Data = Data()) -> Data {
    var b = Data(repeating: 0, count: 348)
    b.putUTF16(name, 0, 128); b.putU32(UInt32.max, 256)
    b.putFloat(100, 268); b.putFloat(100, 272); b[280] = type; b[281] = 2; b[282] = input; b[284] = 1
    b[288] = 7; b[292] = 100; b[293] = 100
    b.putU32(UInt32(payload.count), 344)
    return b + payload + Data(repeating: 0, count: 4)
  }
  func segment(time: Double, flags: UInt32, payload: Data = Data()) -> Data {
    var b = Data(repeating: 0, count: 212)
    b.putFloat(time, 0); b.putU32(flags, 4); b.putFloat(12.5, 8+128); b.putFloat(62.5, 8+136); b.putFloat(100, 8+140)
    b[8+144] = 0; b[8+148] = 23; b[8+151] = 63
    b.putU32(UInt32(payload.count), 208)
    return b + payload + Data(repeating: 0, count: 4)
  }
  func fixture() -> Data {
    var b = header(inputs: 3, objects: 2); b[2121] = 2
    b += input("A", parent: 2, duration: 6, start: 1, end: 5, rate: 2)
    b += input("B", parent: 2, duration: 4)
    var root = input("Joined", type: 5, duration: 6); root.putFloat(1, 2188); b += root
    b += object("Camera", input: 2)
    b += object("Title", type: 13, input: 255, payload: text("Before"))
    var counts = Data(repeating: 0, count: 8); counts.putU32(1, 0); counts.putU32(1, 4); b += counts
    b += segment(time: 5.5, flags: 0x48e)
    b += segment(time: 7.25, flags: 0x1000, payload: text("After"))
    return b
  }
  func read(_ data: Data) throws -> RaceProject {
    var project = try LegacyReader.project(data, base: URL(fileURLWithPath: "/tmp"))
    project.sourcePath = "/tmp/import-fixture.rrp"
    return project
  }

  func testStructuredSourceJoinsTimingAndTimelineInheritance() throws {
    let p = try read(fixture())
    XCTAssertEqual(p.notes, "Synthetic import notes"); XCTAssertEqual(p.speedUnit, "km/h")
    XCTAssertEqual(p.inputs.count, 3); XCTAssertEqual(p.inputs[2].isJoinRoot, true); XCTAssertTrue(p.inputs[2].path.isEmpty)
    XCTAssertEqual(p.placements.count, 2); XCTAssertEqual(p.duration, 7)
    XCTAssertEqual(p.sourceTime(for: 2, at: 2), 3)
    XCTAssertEqual(p.sourceTime(for: 2, at: 3), 0)
    XCTAssertNil(p.sourceTime(for: 2, at: 0.9))
    let camera = p.objects[0]
    XCTAssertTrue(camera.resolved(at: 5.49).visible); XCTAssertFalse(camera.resolved(at: 5.5).visible)
    XCTAssertEqual(camera.resolved(at: 5.5).opacity, 0.77, accuracy: 1e-9)
    XCTAssertEqual(camera.resolved(at: 5.5).x, 12.5); XCTAssertEqual(camera.resolved(at: 5.5).width, 62.5)
    XCTAssertEqual(camera.resolved(at: 5.5).audio?.volume, 0.63)
    XCTAssertEqual(p.objects[1].resolved(at: 7).text, "Before")
    XCTAssertEqual(p.objects[1].resolved(at: 7.25).text, "After")
    XCTAssertTrue(p.warnings.contains { $0.contains("2 timeline segments") })
  }
  func testSavedStandardAndWideWorkspacesAreImported() throws {
    var bytes = fixture()
    XCTAssertEqual(try read(bytes).width, 1920)
    bytes[2126] = 0
    let standard = try read(bytes)
    XCTAssertEqual(standard.width, 1440); XCTAssertEqual(standard.height, 1080)
    bytes[2126] = 254
    XCTAssertTrue(try read(bytes).warnings.contains { $0.contains("workspace mode 254") })
  }
  func testVirtualJoinRootHasNoPictureRecordEvenAtEndOfFile() throws {
    let project = try read(header(inputs: 1, objects: 0) + input("Empty joined stream", type: 5))
    XCTAssertEqual(project.inputs[0].isJoinRoot, true)
    XCTAssertNil(project.inputs[0].picture)
    XCTAssertEqual(project.objects.count, 0)
  }
  func testNativeRoundTripAndConservativeCopyKeepImportedSettings() throws {
    let bytes = fixture(), p = try read(bytes)
    let copy = try p.patchLegacy()
    XCTAssertEqual(copy, bytes, "Changed byte offsets: \(zip(copy.indices, zip(copy, bytes)).filter { $0.1.0 != $0.1.1 }.map(\.0).prefix(30))")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".orrp")
    defer { try? FileManager.default.removeItem(at: file) }
    try p.save(file); let saved = try RaceProject.read(file)
    XCTAssertEqual(saved.objects[1].resolved(at: 8).text, "After")
    XCTAssertEqual(saved.inputs[2].isJoinRoot, true); XCTAssertEqual(saved.notes, p.notes)
    var edited = p; edited.objects[1].typography?.bold = true
    XCTAssertThrowsError(try edited.patchLegacy())
    let template = try p.reusableLayout()
    XCTAssertNil(template.notes); XCTAssertNil(template.lengthInputIndex)
    XCTAssertTrue(template.inputs.allSatisfy { $0.isJoinRoot == nil && $0.audio == nil })
  }
  func testImportedDataProfileTimeUnitsArithmeticAndLapLine() throws {
    var b = Data(repeating: 0, count: 11312)
    b.putUTF16("Clock ms", 0, 128); b.putFloat(1000, 128)
    b.putUTF16("Speed (mph)", 776, 128); b.putFloat(1.609344, 904)
    b.putFloat(30, 1036); b[1593] = 1; b[1595] = 1; b[1596] = 2; b[2656] = 1
    b.putUTF16("Triple speed", 1600, 128); b.putUTF16("Speed (mph)", 1728, 128); b.putFloat(3, 1856)
    let lon = (-121.0).bitPattern, lat = (36.0).bitPattern
    b.putU32(UInt32(truncatingIfNeeded: lon), 1552); b.putU32(UInt32(lon >> 32), 1556)
    b.putU32(UInt32(truncatingIfNeeded: lat), 1560); b.putU32(UInt32(lat >> 32), 1564)
    b[1592] = 128; b.putFloat(90, 1584); b.putFloat(25, 1588)
    var warnings: [String] = []
    var s = try XCTUnwrap(LegacyProjectSettings.data(b, warnings: &warnings)); s.speedUnit = "km/h"
    XCTAssertEqual(s.fields.first?.multiply, 3); XCTAssertEqual(s.gearAdjustment, 1)
    XCTAssertEqual(s.finishLine?.latitude, 36); XCTAssertEqual(s.finishLine?.headingTolerance, 25)
    let d = try Telemetry(text: "Clock ms,Speed (mph),Gear,Heading\n1000,10,1,20\n2000,20,2,40", timeColumn: s.assignments["time"])
    d.configure(s)
    XCTAssertEqual(d.duration, 1)
    XCTAssertEqual(d.speed(at: 1, unit: "mph") ?? 0, 20, accuracy: 0.001)
    XCTAssertEqual(d.value("Triple speed", at: 1), 60)
    XCTAssertEqual(d.value("gear", at: 1), 3); XCTAssertEqual(d.value("heading", at: 1), 350)
  }
  func testLoopPlacementsAndJoinedRootTrimUseOneSourceClock() {
    var p = RaceProject(), i = MediaInput(name: "Loop", path: "loop.mp4", kind: "video")
    i.duration = 2; var timing = InputTiming(); timing.loop = true; i.timing = timing
    p.inputs = [i]; p.explicitDuration = 5
    XCTAssertEqual(p.placements.count, 3)
    XCTAssertEqual(p.sourceTime(for: 0, at: 4.5), 0.5)
    p.explicitDuration = nil; p.lengthInputIndex = 0
    XCTAssertEqual(p.duration, 2)
  }
  func testSourceCropRotationMirroringAndAudioAreImportedIndependently() throws {
    var b = header(inputs: 1, objects: 0), source = input("Camera")
    let s = 2216
    source[s] = 137; source[s+1] = 170; source[s+2] = 2
    source.putU32(32, s+4); source.putU32(18, s+8); source.putU32(64, s+12); source.putU32(36, s+16)
    source.putFloat(17, s+20); source[s+24] = 1; source[s+40] = 16
    b += source
    let p = try read(b), camera = p.inputs[0]
    XCTAssertEqual(camera.volume, 1.37); XCTAssertEqual(camera.audio?.routing, .left)
    XCTAssertEqual(camera.audio?.balance ?? 0, 0.7, accuracy: 1e-9)
    XCTAssertEqual(camera.picture?.left, 0.1); XCTAssertEqual(camera.picture?.top, 0.1)
    XCTAssertEqual(camera.picture?.right, 0.2); XCTAssertEqual(camera.picture?.bottom, 0.2)
    XCTAssertEqual(camera.picture?.rotation, 17); XCTAssertEqual(camera.picture?.flipX, true)
    XCTAssertEqual(camera.picture?.flipY, false)
  }
  func testMalformedModernRecordsAreRejectedWithoutScanningInsidePayloads() throws {
    var b = fixture(); b.removeLast()
    XCTAssertThrowsError(try read(b))
    b = fixture(); b.putU32(1000000, 2152 + 2272 + 2272 + 2216 + 352 + 1160)
    XCTAssertThrowsError(try read(b))
  }
  func testStereoRoutingAndPerDisplayGainMatrices() {
    var input = MediaInput(name: "Audio", path: "", kind: "audio"), audio = AudioSettings()
    var display = DisplayObject(name: "Audio", kind: .audio)
    audio.routing = .left; input.audio = audio
    var result = StereoMatrix.make(source: input, displays: [display]).apply(0.25, 0.75)
    XCTAssertEqual(result.0, 0.25); XCTAssertEqual(result.1, 0.25)
    input.audio?.routing = .swap
    var gain = AudioSettings(); gain.volume = 0.5; gain.balance = 1; display.audio = gain
    result = StereoMatrix.make(source: input, displays: [display]).apply(0.25, 0.75)
    XCTAssertEqual(result.0, 0); XCTAssertEqual(result.1, 0.125)
    XCTAssertEqual(StereoMatrix.make(source: input, displays: []).apply(0.25, 0.75).0, 0)
  }
}
