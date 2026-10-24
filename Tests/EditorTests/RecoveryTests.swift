import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class RecoveryTests: XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor func testFailedRelinkPreservesSourceSettingsTelemetryAndDirtyState() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let bad = root.appendingPathComponent("invalid.csv")
    try Data("This is not telemetry or video".utf8).write(to: bad)
    let model = EditorModel()
    var input = MediaInput(name: "Laps", path: "/missing/old.csv", kind: "data", legacyIndex: 7)
    input.offset = 2; input.duration = 40; input.picture = PictureSettings()
    model.project.inputs = [input]
    let oldData = try Telemetry(text: "Time,Speed\n0,10\n1,20\n")
    model.telemetry = [7: oldData]
    model.dirty = false
    let before = model.project
    let success = await model.relink(input.id, to: bad)
    XCTAssertFalse(success)
    XCTAssertEqual(model.project, before)
    XCTAssertTrue(model.telemetry[7] === oldData)
    XCTAssertFalse(model.dirty)
    XCTAssertFalse(model.busy)
    XCTAssertTrue(model.error?.contains("previous source is unchanged") == true)
    // A file that exists but has no video track must not replace a camera either.
    model.project.inputs[0].kind = "video"; model.dirty = false
    let camera = model.project
    let videoSuccess = await model.relink(input.id, to: bad)
    XCTAssertFalse(videoSuccess)
    XCTAssertEqual(model.project, camera)
    XCTAssertFalse(model.dirty)
  }
  @MainActor func testDataRelinkRetainsSynchronizationAndChannelSettingsAndCanUndo() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let replacement = root.appendingPathComponent("new.csv")
    try Data("Time,Velocity\n0,10\n1,20\n2,30\n".utf8).write(to: replacement)
    let model = EditorModel()
    var input = MediaInput(name: "Laps", path: "/missing/old.csv", kind: "data", legacyIndex: 7)
    input.offset = 0.5; input.duration = 40
    var timing = InputTiming(); timing.trimStart = 0.25; timing.projectStart = 1; timing.rate = 0.5
    input.timing = timing
    var settings = DataSettings(); settings.assignments["speed"] = "Velocity"
    input.dataSettings = settings
    model.project.inputs = [input]
    model.project.rangeStart = 1; model.project.rangeEnd = 3
    var display = DisplayObject(name: "Speed", kind: .speed); display.inputIndex = 7
    model.project.objects = [display]; model.dirty = false
    model.exportStart = 1; model.exportDuration = 1
    XCTAssertTrue(model.exportRangeError?.contains("old.csv") == true)
    let before = model.project
    let success = await model.relink(input.id, to: replacement)
    XCTAssertTrue(success)
    XCTAssertNil(model.exportRangeError)
    var expected = input; expected.path = replacement.path; expected.duration = 2
    XCTAssertEqual(model.project.inputs, [expected])
    XCTAssertEqual(model.telemetry[7]?.count, 3)
    XCTAssertEqual(model.telemetry[7]?.channelIndex("speed"), 1)
    XCTAssertEqual(model.project.objects, before.objects)
    XCTAssertEqual(model.project.rangeStart, 1)
    XCTAssertEqual(model.project.rangeEnd, 3)
    XCTAssertTrue(model.dirty)
    let saved = root.appendingPathComponent("recovered.orrp")
    try model.project.save(saved)
    XCTAssertEqual(try RaceProject.read(saved).inputs, [expected])
    model.undo()
    XCTAssertEqual(model.project, before)
  }
  @MainActor func testImageRelinkUpdatesDisplayedAssetAndUndoRestoresIt() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let replacement = root.appendingPathComponent("new.png")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: replacement)
    let model = EditorModel()
    let input = MediaInput(name: "Logo", path: "/missing/old.png", kind: "image", legacyIndex: 8)
    var display = DisplayObject(name: "Logo", kind: .image); display.inputIndex = 8; display.text = input.path
    model.project.inputs = [input]; model.project.objects = [display]
    let before = model.project
    let success = await model.relink(input.id, to: replacement)
    XCTAssertTrue(success)
    XCTAssertEqual(model.project.objects[0].text, replacement.path)
    model.undo()
    XCTAssertEqual(model.project, before)
  }
}
