import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class WidgetDesignTests: XCTestCase {
  @MainActor func testStyleChangeRetainsInstanceAndUndoRestoresIt() throws {
    let model = EditorModel()
    var old = DisplayObject(name: "Coolant", kind: .temperature)
    old.inputIndex = 9; old.channel = "Coolant (C)"; old.x = -2; old.y = 76; old.width = 3; old.height = 12
    old.opacity = 0.6; old.start = 2; old.end = 40; old.visible = false
    var picture = PictureSettings(); picture.rotation = 15; old.picture = picture
    var segment = ObjectSegment(time: 10); segment.x = 20; segment.channel = "Oil (C)"; old.segments = [segment]
    var style = DisplayObject(name: "Thermometer", kind: .temperature)
    style.style = "Synthetic thermometer"; style.maximum = 150; style.legacyType = 50
    style.legacyPayload = Data([1, 2, 3]); style.embeddedImage = Data([4, 5])
    model.project.objects = [old]; model.selected = old.id
    let before = model.project
    var layout = RaceProject(); layout.objects = [style]
    model.applyStyle(layout)
    let changed = try XCTUnwrap(model.project.objects.first)
    XCTAssertEqual(changed, old.applyingStyle(style))
    XCTAssertEqual(changed.x, -2); XCTAssertEqual(changed.y, 76); XCTAssertEqual(changed.width, 3); XCTAssertEqual(changed.height, 12)
    XCTAssertEqual(changed.id, old.id); XCTAssertEqual(changed.name, old.name)
    XCTAssertEqual(changed.inputIndex, 9); XCTAssertEqual(changed.channel, old.channel)
    XCTAssertEqual(changed.segments, old.segments); XCTAssertEqual(changed.picture, old.picture)
    XCTAssertEqual(changed.maximum, 150); XCTAssertEqual(changed.legacyPayload, style.legacyPayload)
    model.undo(); XCTAssertEqual(model.project, before)
    layout.objects[0].kind = .rpm
    model.applyStyle(layout)
    XCTAssertNotNil(model.error); XCTAssertEqual(model.project, before)
    var title = DisplayObject(name: "Title", kind: .text); title.text = "My session"
    var titleStyle = DisplayObject(name: "Title style", kind: .text); titleStyle.text = "Example"
    XCTAssertEqual(title.applyingStyle(titleStyle).text, "My session")
    var image = DisplayObject(name: "Logo", kind: .image); image.embeddedImage = Data([1, 2])
    XCTAssertEqual(image.applyingStyle(DisplayObject(name: "Native", kind: .image)).embeddedImage, image.embeddedImage)
    var video = DisplayObject(name: "Camera", kind: .video); video.inputIndex = 7; video.x = 20; video.width = 30
    var position = DisplayObject(name: "Full screen", kind: .video); position.x = 0; position.width = 100
    model.project.objects = [video]; model.selected = video.id; layout.objects = [position]
    model.applyStyle(layout, preservePlacement: false)
    XCTAssertEqual(model.project.objects[0].x, 0); XCTAssertEqual(model.project.objects[0].width, 100)
    XCTAssertEqual(model.project.objects[0].inputIndex, 7); XCTAssertEqual(model.project.objects[0].id, video.id)
  }
  @MainActor func testStyledPlacementSourceMappingSaveAndApplyToNewSession() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrt")
    defer { try? FileManager.default.removeItem(at: file) }
    let model = EditorModel()
    model.project.inputs = [MediaInput(name: "Data", path: "", kind: "data", legacyIndex: 9)]
    var object = DisplayObject(name: "Peak G", kind: .gforce)
    object.style = "Synthetic peak"; object.inputIndex = 123; object.width = 22; object.height = 3
    object.channel = "gy"; object.start = 8; object.visible = false; object.segments = [ObjectSegment(time: 30)]
    let style = WidgetStyle(id: "peak", name: object.name, object: object)
    model.addWidget(style, at: CGPoint(x: 99, y: 99))
    let added = try XCTUnwrap(model.project.objects.first)
    XCTAssertNotEqual(added.id, object.id); XCTAssertEqual(model.selected, added.id)
    XCTAssertEqual(added.inputIndex, 9); XCTAssertEqual(added.x, 78); XCTAssertEqual(added.y, 97)
    XCTAssertTrue(added.visible); XCTAssertEqual(added.start, 0); XCTAssertNil(added.segments)
    try model.project.reusableLayout().save(file)
    let loaded = try WidgetStyle.read(file)
    XCTAssertEqual(loaded.count, 1); XCTAssertEqual(loaded[0].object.style, object.style)
    let catalog = WidgetCatalog()
    await catalog.load(file.path)
    XCTAssertEqual(catalog.styles.count, 1)
    let cancelled = Task { await catalog.load("") }
    cancelled.cancel(); await cancelled.value
    XCTAssertEqual(catalog.styles.count, 1, "A cancelled palette selection must not erase a newer result")
    XCTAssertFalse(catalog.loading)
    var next = RaceProject(); next.inputs = [MediaInput(name: "Next data", path: "", kind: "data", legacyIndex: 4)]
    next.applyLayout(try RaceProject.read(file), replace: true)
    XCTAssertEqual(next.objects[0].inputIndex, 4); XCTAssertEqual(next.objects[0].x, 78)
    model.undo(); XCTAssertTrue(model.project.objects.isEmpty)
  }
  @MainActor func testDesignSamplesCannotLeakIntoSavedOrExportScene() throws {
    let model = EditorModel(); model.showWidgets = true; model.addObject(.speed)
    let before = model.project
    XCTAssertTrue(model.usesDesignSamples); XCTAssertFalse(model.designScene.telemetry.isEmpty)
    XCTAssertEqual(WidgetDesign.telemetry.value("Engine oil temperature (.C)", at: 18), 105)
    XCTAssertTrue(model.scene.telemetry.isEmpty); XCTAssertEqual(model.scene.project, before)
    XCTAssertTrue(try model.project.reusableLayout().inputs.isEmpty)
    XCTAssertEqual(model.project, before)
    model.showWidgets = false; XCTAssertTrue(model.designScene.telemetry.isEmpty)
    model.showWidgets = true
    model.project.inputs = [MediaInput(name: "Missing CSV", path: "/missing.csv", kind: "data")]
    XCTAssertFalse(model.usesDesignSamples, "Never conceal a missing session's real telemetry with sample values")
  }
  @MainActor func testAlignmentAndPixelNudgeParticipateInUndoAndSegments() {
    let model = EditorModel(); model.project.width = 1920; model.project.height = 1080
    model.addObject(.speed)
    let original = model.project
    model.alignWidget("Right"); XCTAssertEqual(model.project.objects[0].x, 82)
    model.undo(); XCTAssertEqual(model.project, original)
    model.nudgeWidget(x: 1, y: -10)
    XCTAssertEqual(model.project.objects[0].x, 5+100/1920, accuracy: 1e-12)
    XCTAssertEqual(model.project.objects[0].y, 5-1000/1080, accuracy: 1e-12)
    model.undo(); XCTAssertEqual(model.project, original)
    model.editingSegment = 5; model.alignWidget("Top")
    XCTAssertEqual(model.project.objects[0].y, 5)
    XCTAssertEqual(model.project.objects[0].resolved(at: 5).y, 68)
  }
  @MainActor func testCustomizedTemplateCanBeRebuiltFromIndividualWidgetsWhenProvided() throws {
    guard let root = ProcessInfo.processInfo.environment["OPENRACERENDER_LIBRARY"] else { throw XCTSkip("Optional local template check") }
    let file = URL(fileURLWithPath: root).appendingPathComponent("Templates/Customized - 1.rrt")
    guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Customized template not supplied") }
    var original = try RaceProject.read(file)
    original.objects.removeAll { [.video, .audio].contains($0.kind) }
    let styles = try WidgetStyle.read(file)
    XCTAssertEqual(styles.count, 17)
    let model = EditorModel(); model.project.inputs = original.inputs.filter { $0.kind == "data" }
    model.project.name = "Customized - 1 (recreated)"
    for style in styles { model.addWidget(style) }
    XCTAssertEqual(model.project.objects.map(\.style), original.objects.map(\.style))
    XCTAssertTrue(model.project.objects.contains { $0.name.contains("Peak G") })
    let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrt")
    defer { try? FileManager.default.removeItem(at: saved) }
    try model.project.reusableLayout().save(saved)
    let reopened = try RaceProject.read(saved)
    XCTAssertEqual(reopened.duration, 60, "Empty template roles must not collapse the design timeline to one second")
    let output = ProcessInfo.processInfo.environment["OPENRACERENDER_DESIGN_OUTPUT"].map { URL(fileURLWithPath: $0) }
    if let output { try model.project.reusableLayout().save(output.appendingPathComponent("Customized - 1 - Recreated.orrt")) }
    func pixels(_ project: RaceProject, name: String) throws -> Data {
      let c = try XCTUnwrap(CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 0,
        space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      OverlayRenderer.draw(c, scene: WidgetDesign.scene(project), time: 18, size: CGSize(width: 960, height: 540))
      let image = try XCTUnwrap(c.makeImage())
      if let output {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name+".png"))
      }
      let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
      XCTAssertGreaterThan(pixels.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count, 5000, "Comparison must contain rendered overlays")
      return pixels
    }
    XCTAssertEqual(try pixels(reopened, name: "recreated"), try pixels(original, name: "reference"), "Rebuilt and saved overlays must render identically to their source template")
    for style in styles { XCTAssertNotNil(WidgetDesign.thumbnail(style.object), style.name) }
  }
}
