import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class NetworkReceiveEditorTests:XCTestCase {
  @MainActor func testCompletedTransferAddsToCurrentProjectAndUndoKeepsFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("received.csv");try Data("Time,Speed\n0,10\n1,20\n".utf8).write(to:url)
    let model = EditorModel();var caption = DisplayObject(name:"Keep this caption",kind:.text);caption.text = "Existing work"
    model.project.objects = [caption];model.project.rangeStart = 0.1;model.project.rangeEnd = 0.9
    let revision = model.documentRevision
    XCTAssertTrue(model.importReceivedFiles([url],newSession:false))
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertEqual(model.documentRevision,revision);XCTAssertTrue(model.project.objects.contains{$0.id == caption.id})
    XCTAssertEqual(model.project.rangeStart,0.1);XCTAssertEqual(model.project.rangeEnd,0.9)
    let input = try XCTUnwrap(model.project.inputs.first)
    XCTAssertEqual(input.path,url.path);XCTAssertEqual(model.telemetry[input.legacyIndex]?.value("speed",at:0),10)
    model.undo();XCTAssertTrue(model.project.inputs.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
  }
  @MainActor func testNewSessionImportAndMissingReceiptValidation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("received.csv");try Data("Time,Speed\n0,10\n1,20\n".utf8).write(to:url)
    let model = EditorModel();model.dirty = false;let revision = model.documentRevision
    XCTAssertTrue(model.importReceivedFiles([url],newSession:true))
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertNotEqual(model.documentRevision,revision);XCTAssertFalse(model.showProjectSetup)
    XCTAssertEqual(model.project.inputs.count,1)
    let before = model.project
    XCTAssertFalse(model.importReceivedFiles([root.appendingPathComponent("missing.csv")],newSession:false))
    XCTAssertEqual(model.project,before)
  }
}
