import AppKit
import XCTest
import RaceCore
@testable import OpenRaceRender

final class LoggerSessionEditorTests:XCTestCase {
  @MainActor func testImportOffersSessionAndApplyPersistsUndoAndTiming() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("multi.csv")
    try Data("Time,Speed\n0,10\n1,20\n0,30\n1,40\n".utf8).write(to:url)
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    let request = try XCTUnwrap(model.dataSetupRequest)
    XCTAssertEqual(model.project.inputs.count,1);XCTAssertFalse(model.project.objects.contains{$0.kind == .video})
    let id = try XCTUnwrap(request.original?.id)
    model.project.inputs[0].offset = 0.25;model.project.rangeStart = 0.1;model.project.rangeEnd = 0.9
    // Reopen after independent timing edits, just as the stale-request guard requires.
    model.dataSetupRequest = nil;model.configureData(model.project.inputs[0])
    let fresh = try XCTUnwrap(model.dataSetupRequest)
    let preview = try await DataSetupPreview.load(url,settings:DataSettings(),session:2)
    XCTAssertTrue(model.applyDataSetup(fresh,preview:preview))
    XCTAssertEqual(model.project.inputs[0].id,id);XCTAssertEqual(model.project.inputs[0].dataSession,2)
    XCTAssertEqual(model.project.inputs[0].offset,0.25);XCTAssertEqual(model.project.rangeStart,0.1);XCTAssertEqual(model.project.rangeEnd,0.9)
    XCTAssertEqual(model.telemetry[model.project.inputs[0].legacyIndex]?.value("speed",at:0),30)
    let saved = root.appendingPathComponent("saved.orrp");try model.project.save(saved)
    let loaded = try RaceProject.read(saved),tables = try Telemetry.loadSources(loaded.inputs)
    XCTAssertEqual(tables[loaded.inputs[0].legacyIndex]?.value("speed",at:0),30)
    model.undo();XCTAssertNil(model.project.inputs[0].dataSession)
  }
  @MainActor func testUnsupportedLoggerIsExplainedInsteadOfAddedAsVideo() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".prr")
    try Data("not a verified PRR format".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<100 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertTrue(model.project.inputs.isEmpty);XCTAssertTrue(model.error?.contains("Export a timestamped") == true)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App",url.path]),url)
  }
}
