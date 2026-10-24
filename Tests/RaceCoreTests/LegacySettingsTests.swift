import XCTest
@testable import RaceCore

final class LegacySettingsTests: XCTestCase {
  func fixture(start: Double = 183.78294372558594, end: Double = 1401.374755859375) -> Data {
    var b = Data(repeating: 0, count: 2152 + 2216 + 56)
    b.replaceSubrange(0..<4, with: Data("RRP3".utf8))
    b.putU32(2152, 12); b.putU32(1, 16); b.putU32(2216, 20); b.putU32(56, 28)
    b.putFloat(start, 2128); b.putFloat(end, 2132)
    b.putUTF16("Camera", 2152, 128); b.putFloat(2000, 2152 + 2184)
    let settings = 2152 + 2216
    b[settings + 25] = 90; b[settings + 26] = 110; b[settings + 27] = 125
    b[settings + 28] = 211; b[settings + 29] = 255 // Native signed Int16: −45°.
    b[settings + 30] = 150
    return b
  }
  func read(_ data: Data) throws -> RaceProject {
    try LegacyReader.project(data, base: URL(fileURLWithPath: "/tmp"))
  }
  func testSavedNativeMarkersAndPictureControlsRoundTrip() throws {
    let bytes = fixture()
    var p = try read(bytes)
    XCTAssertEqual(p.rangeStart, 183.78294372558594)
    XCTAssertEqual(p.rangeEnd, 1401.374755859375)
    XCTAssertEqual(clockText(p.rangeStart!), "03:03.783")
    XCTAssertEqual(clockText(p.rangeEnd!), "23:21.375")
    XCTAssertEqual(p.defaultExportRange, 183.78294372558594...1401.374755859375)
    XCTAssertEqual(p.inputs[0].picture?.brightnessAdjustment ?? 0, -10, accuracy: 0.00001)
    XCTAssertEqual(p.inputs[0].picture?.contrastAdjustment ?? 0, 10, accuracy: 0.00001)
    XCTAssertEqual(p.inputs[0].picture?.saturationAdjustment, 25)
    XCTAssertEqual(p.inputs[0].picture?.sharpnessAdjustment, 50)
    XCTAssertEqual(p.inputs[0].picture?.hueAdjustment, -45)
    XCTAssertEqual(try p.patchLegacy(), bytes)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".orrp")
    defer { try? FileManager.default.removeItem(at: file) }
    try p.save(file)
    let reopened = try RaceProject.read(file)
    XCTAssertEqual(reopened.defaultExportRange, p.defaultExportRange)
    XCTAssertEqual(reopened.inputs[0].picture, p.inputs[0].picture)
    var earlier = p
    earlier.inputs[0].picture?.hue = nil; earlier.inputs[0].picture?.sharpness = nil
    earlier.inputs[0].picture?.brightness = 1.2
    try earlier.save(file)
    let recovered = try RaceProject.read(file)
    XCTAssertEqual(recovered.inputs[0].picture?.hue, -45)
    XCTAssertEqual(recovered.inputs[0].picture?.sharpness, 1.5)
    XCTAssertEqual(recovered.inputs[0].picture?.brightness, 1.2)
    p.rangeEnd = nil
    XCTAssertThrowsError(try p.patchLegacy())
  }
  func testUnsetSingleAndInvalidMarkers() throws {
    let none = try read(fixture(start: 0, end: 0))
    XCTAssertNil(none.rangeStart); XCTAssertNil(none.rangeEnd)
    XCTAssertEqual(none.defaultExportRange, 0...2000)
    XCTAssertEqual(try read(fixture(start: 0)).defaultExportRange, 0...1401.374755859375)
    XCTAssertEqual(try read(fixture(end: 0)).defaultExportRange, 183.78294372558594...2000)
    let invalid = try read(fixture(start: .nan, end: -.infinity))
    XCTAssertNil(invalid.rangeStart); XCTAssertNil(invalid.rangeEnd)
    XCTAssertNil(try read(fixture(start: -1, end: -1)).rangeStart)
    // Some reduced/older files have no fixed marker header. Do not read input bytes as flags.
    var small = Data(fixture().prefix(56)); small.putU32(56, 12); small.putU32(0, 16)
    XCTAssertNil(try read(small).rangeEnd)
  }
  func testSignedControlsClampAndKeepExistingMultiplierStorage() throws {
    var s = PictureSettings()
    XCTAssertEqual(s.brightnessAdjustment, 0); XCTAssertEqual(s.sharpnessAdjustment, 0)
    s.brightnessAdjustment = -100; s.contrastAdjustment = 100
    s.saturationAdjustment = 25; s.sharpnessAdjustment = -40; s.hueAdjustment = -45
    XCTAssertEqual(s.brightness, 0); XCTAssertEqual(s.contrast, 2)
    XCTAssertEqual(s.saturation, 1.25); XCTAssertEqual(s.sharpness, 0.6); XCTAssertEqual(s.hue, -45)
    s.brightnessAdjustment = -999; s.contrastAdjustment = 999; s.hueAdjustment = 999
    XCTAssertEqual(s.brightness, 0); XCTAssertEqual(s.contrast, 2); XCTAssertEqual(s.hue, 180)
    s.hueAdjustment = -.infinity; s.sharpnessAdjustment = .nan
    XCTAssertEqual(s.hue, 0); XCTAssertEqual(s.sharpness, 1)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    json.removeValue(forKey: "sharpness"); json.removeValue(forKey: "hue")
    let old = try JSONDecoder().decode(PictureSettings.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(old.sharpnessAdjustment, 0); XCTAssertEqual(old.hueAdjustment, 0)
    XCTAssertEqual(old.brightness, 0); XCTAssertEqual(old.contrast, 2)
  }
}
