import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class CameraTelemetryEditorTests:XCTestCase {
  // Original one-second MP4 metadata index and scaled two-sample camera-axis stream; no video or private data.
  let fixture = Data(base64Encoded:"AAAAOG1kYXRERVZDAAEAKFNUUk0AAQAgU0NBTGwEAAEAAABkQUNDTHMGAAIAZADIASwAyAEsAZAAAADcbW9vdgAAABxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAA+gAAAC4dHJhawAAALBtZGlhAAAAHG1kaGQAAAAAAAAAAAAAAAAAAAPoAAAD6AAAAIxtaW5mAAAAhHN0YmwAAAAgc3RzZAAAAAAAAAABAAAAEGdwbWQAAAAAAAAAAAAAABRzdHN6AAAAAAAAADAAAAABAAAAFHN0Y28AAAAAAAAAAQAAAAgAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAGHN0dHMAAAAAAAAAAQAAAAEAAAPo")!
  @MainActor func testCameraImportIsOptionalLinkedUndoableAndPreservesExternalMapping() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("camera.mp4");try fixture.write(to:url)
    let model = EditorModel()
    var source = MediaInput(name:"Camera",path:url.path,kind:"video",legacyIndex:3);source.duration = 1
    let csv = root.appendingPathComponent("external.csv");try Data("Time,Speed\n0,10\n1,20\n".utf8).write(to:csv)
    var external = MediaInput(name:"Logger",path:csv.path,kind:"data",legacyIndex:9);external.duration = 1
    var widget = DisplayObject(name:"Speed",kind:.speed);widget.inputIndex = 9
    model.project.inputs = [source,external];model.project.objects = [widget]
    model.cameraDataCandidates = [source.id]
    XCTAssertEqual(model.cameraDataOffer?.id,source.id)
    let success = await model.addCameraData(source.id);XCTAssertTrue(success)
    let embedded = try XCTUnwrap(model.project.inputs.first(where:{$0.cameraVideoID != nil}))
    XCTAssertEqual(embedded.path,url.path);XCTAssertEqual(embedded.cameraVideoID,source.id)
    XCTAssertEqual(model.project.objects.first?.inputIndex,9)
    XCTAssertEqual(model.project.inputs.count,3);XCTAssertEqual(model.project.inputs.first(where:{$0.id == external.id})?.path,csv.path)
    XCTAssertNil(model.cameraDataOffer)
    XCTAssertEqual(model.telemetry[embedded.legacyIndex]?.value("Camera acceleration axis 1 (m/s²)",at:0),1)
    let saved = root.appendingPathComponent("camera.orrp");try model.project.save(saved)
    let loaded = try RaceProject.read(saved)
    XCTAssertEqual(loaded.inputs.first(where:{$0.cameraVideoID != nil})?.cameraVideoID,source.id)
    let tables = try Telemetry.loadSources(loaded.inputs)
    XCTAssertEqual(tables[embedded.legacyIndex]?.duration,1)
    model.removeInput(source.id);XCTAssertTrue(model.project.inputs.contains(where:{$0.id == source.id}))
    XCTAssertNotNil(model.error);model.error = nil
    model.undo();XCTAssertFalse(model.project.inputs.contains(where:{$0.cameraVideoID != nil}))
    XCTAssertEqual(model.project.objects.first?.inputIndex,9)
  }
  @MainActor func testFailedExtractionHasNoPartialInput() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    try Data("not a movie".utf8).write(to:root);defer {try? FileManager.default.removeItem(at:root)}
    let model = EditorModel();let input = MediaInput(name:"Bad",path:root.path,kind:"video")
    model.project.inputs = [input];model.dirty = false;let before = model.project
    let success = await model.addCameraData(input.id);XCTAssertFalse(success)
    XCTAssertEqual(model.project,before);XCTAssertFalse(model.dirty);XCTAssertFalse(model.busy);XCTAssertNotNil(model.error)
  }
}
