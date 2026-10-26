import XCTest
@testable import RaceCore

final class WorkflowTests: XCTestCase {
  func session() -> RaceProject {
    var p = RaceProject()
    var video = MediaInput(name: "Camera", path: "", kind: "video", legacyIndex: 4); video.duration = 120
    var data = MediaInput(name: "Laps", path: "", kind: "data", legacyIndex: 9); data.duration = 130
    p.inputs = [video, data]
    return p
  }
  func testLapSynchronizationWorksForEarlierAndLaterDataStarts() throws {
    var p = session()
    try p.synchronize(inputIndex: 9, sourceTime: 40, projectTime: 35)
    XCTAssertEqual(p.sourceTime(for: 9, at: 35), 40)
    try p.synchronize(inputIndex: 9, sourceTime: 30, projectTime: 35)
    XCTAssertEqual(p.sourceTime(for: 9, at: 35), 30)
    XCTAssertNil(p.sourceTime(for: 9, at: 4))
    var timing = InputTiming(); timing.trimStart = 10; timing.rate = 2; timing.projectStart = 3
    p.inputs[1].timing = timing
    try p.synchronize(inputIndex: 9, sourceTime: 30, projectTime: 35)
    XCTAssertEqual(p.sourceTime(for: 9, at: 35), 30)
    let previous = p
    XCTAssertThrowsError(try p.synchronize(inputIndex: 9, sourceTime: 5, projectTime: 35))
    XCTAssertEqual(p, previous)
    XCTAssertThrowsError(try p.synchronize(inputIndex: 9, sourceTime: 30, projectTime: 2))
  }
  func testMarksSurviveRoundTripAndOverrideRememberedCustomRange() throws {
    var p = session()
    p.lastExport = ExportDestination(path: "/tmp/session.mp4", start: 5, duration: 10)
    XCTAssertEqual(p.defaultExportRange, 5...15)
    p.markExportStart(at: 20); p.markExportEnd(at: 80)
    XCTAssertEqual(p.defaultExportRange, 20...80)
    let decoded = try JSONDecoder().decode(RaceProject.self, from: JSONEncoder().encode(p))
    XCTAssertEqual(decoded.defaultExportRange, 20...80)
    XCTAssertEqual(decoded.lastExport?.path, "/tmp/session.mp4")
    p.markExportStart(at: 100)
    XCTAssertNil(p.rangeEnd)
    XCTAssertEqual(p.defaultExportRange, 100...130)
    p.markExportEnd(at: 50)
    XCTAssertNil(p.rangeStart)
    XCTAssertEqual(p.defaultExportRange, 0...50)
    XCTAssertThrowsError(try p.validateExportRange(start: 20, duration: 200))
    XCTAssertThrowsError(try p.validateExportRange(start: .nan, duration: 1))
    XCTAssertNoThrow(try p.validateExportRange(start: 20, duration: 60))
  }
  func testReusableLayoutRemovesSessionStateAndEmbedsArtwork() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("logo.png")
    try Data([1, 2, 3]).write(to: image)
    var p = session()
    p.inputs[1].offset = 5; p.inputs[1].dataSettings = DataSettings()
    p.rangeStart = 10; p.rangeEnd = 20; p.explicitDuration = 100
    p.exportSettings = ExportSettings(videoBitRate: 1_000_000)
    p.lastExport = ExportDestination(path: "/tmp/session.mp4", start: 10, duration: 10)
    var logo = DisplayObject(name: "Logo", kind: .image); logo.text = image.path; logo.inputIndex = -1
    var speed = DisplayObject(name: "Speed", kind: .speed); speed.inputIndex = 9
    speed.gauge = GaugeSettings(); speed.gauge?.backgroundPath = image.path
    var imageSegment = ObjectSegment(time: 5); imageSegment.text = image.path
    logo.segments = [imageSegment]
    var gaugeSegment = ObjectSegment(time: 5); gaugeSegment.gauge = speed.gauge
    speed.segments = [gaugeSegment]
    p.objects = [logo, speed]
    let layout = try p.reusableLayout()
    XCTAssertEqual(layout.objects[0].embeddedImage, Data([1, 2, 3]))
    XCTAssertEqual(layout.objects[0].text, "")
    XCTAssertEqual(layout.objects[1].gauge?.backgroundImage, Data([1, 2, 3]))
    XCTAssertNil(layout.objects[1].gauge?.backgroundPath)
    XCTAssertEqual(layout.objects[0].segments?[0].embeddedImage, Data([1, 2, 3]))
    XCTAssertEqual(layout.objects[0].segments?[0].text, "")
    XCTAssertEqual(layout.objects[1].segments?[0].gauge?.backgroundImage, Data([1, 2, 3]))
    XCTAssertNil(layout.objects[1].segments?[0].gauge?.backgroundPath)
    XCTAssertEqual(layout.inputs.count, 1)
    XCTAssertEqual(layout.inputs[0].path, "")
    XCTAssertEqual(layout.inputs[0].offset, 0)
    XCTAssertNil(layout.inputs[0].dataSettings)
    XCTAssertNil(layout.rangeStart); XCTAssertNil(layout.rangeEnd)
    XCTAssertNil(layout.explicitDuration); XCTAssertNil(layout.exportSettings); XCTAssertNil(layout.lastExport)
    let saved = root.appendingPathComponent("reusable.orrt")
    try layout.save(saved)
    let reopened = try RaceProject.read(saved)
    XCTAssertEqual(reopened.objects[0].embeddedImage, layout.objects[0].embeddedImage)
    XCTAssertEqual(reopened.objects[1].gauge?.backgroundImage, layout.objects[1].gauge?.backgroundImage)
    var next = session(); next.inputs[1].legacyIndex = 22
    next.applyLayout(reopened, replace: true)
    XCTAssertEqual(next.objects[1].inputIndex, 22)
    XCTAssertEqual(next.objects[0].inputIndex, -1)
  }
  func testMovedProjectResolvesImagesAndGaugeBackgroundsBesideMedia() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let original = root.appendingPathComponent("original")
    let moved = root.appendingPathComponent("moved")
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let asset = original.appendingPathComponent("logo.png")
    try Data([1, 2, 3]).write(to: asset)
    var p = session()
    p.inputs[0].path = asset.path
    var logo = DisplayObject(name: "Logo", kind: .image); logo.text = asset.path
    var gauge = DisplayObject(name: "Gauge", kind: .speed); gauge.gauge = GaugeSettings(); gauge.gauge?.backgroundPath = asset.path
    var imageSegment = ObjectSegment(time: 5); imageSegment.text = asset.path
    logo.segments = [imageSegment]
    var gaugeSegment = ObjectSegment(time: 5); gaugeSegment.gauge = gauge.gauge
    gauge.segments = [gaugeSegment]
    p.objects = [logo, gauge]
    try p.save(original.appendingPathComponent("session.orrp"))
    try FileManager.default.moveItem(at: original, to: moved)
    let decoded = try RaceProject.read(moved.appendingPathComponent("session.orrp"))
    let expected = moved.appendingPathComponent("logo.png").resolvingSymlinksInPath().path
    XCTAssertEqual(URL(fileURLWithPath: decoded.inputs[0].path).resolvingSymlinksInPath().path, expected)
    XCTAssertEqual(URL(fileURLWithPath: decoded.objects[0].text).resolvingSymlinksInPath().path, expected)
    XCTAssertEqual(URL(fileURLWithPath: decoded.objects[1].gauge!.backgroundPath!).resolvingSymlinksInPath().path, expected)
    XCTAssertEqual(URL(fileURLWithPath: decoded.objects[0].segments![0].text!).resolvingSymlinksInPath().path, expected)
    XCTAssertEqual(URL(fileURLWithPath: decoded.objects[1].segments![0].gauge!.backgroundPath!).resolvingSymlinksInPath().path, expected)
    XCTAssertEqual(RaceProject.resolvePath("/missing/example.mp4", base: moved), "/missing/example.mp4")
  }
  func testLayoutMappingCannotBindTelemetryToVideoOrIgnoreNone() {
    var target = session()
    var camera = DisplayObject(name: "Video", kind: .video); camera.inputIndex = 4
    target.objects = [camera, DisplayObject(name: "Old overlay", kind: .speed)]
    var layout = RaceProject()
    layout.inputs = [MediaInput(name: "Data", path: "", kind: "data", legacyIndex: 0)]
    var speed = DisplayObject(name: "Speed", kind: .speed)
    var segment = ObjectSegment(time: 10); segment.inputIndex = 0; speed.segments = [segment]
    layout.objects = [speed]
    target.applyLayout(layout, replace: true, mapping: [0: 4])
    XCTAssertEqual(target.objects.count, 2)
    XCTAssertEqual(target.objects[0].kind, .video)
    XCTAssertEqual(target.objects[1].inputIndex, -1)
    XCTAssertEqual(target.objects[1].segments?[0].inputIndex, -1)
    target.applyLayout(layout, replace: true, mapping: [0: -1])
    XCTAssertEqual(target.objects[1].inputIndex, -1)
    target.applyLayout(layout, replace: true)
    XCTAssertEqual(target.objects[1].inputIndex, 9)
  }
}
