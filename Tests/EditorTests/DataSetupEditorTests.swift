import RaceCore
import XCTest
@testable import OpenRaceRender

final class DataSetupEditorTests:XCTestCase {
  func file() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
    try "Ticks,Velocity\n1000,36\n2000,72\n3000,108\n".write(to:url,atomically:true,encoding:.utf8)
    addTeardownBlock{try? FileManager.default.removeItem(at:url)}; return url
  }
  func settings() -> DataSettings {
    var value = DataSettings(); value.assignments = ["time":"Ticks","speed":"Velocity"]
    value.timeUnitsPerSecond = 1000; value.speedConversionEnabled = true; value.speedUnit = "km/h"
    return value
  }
  @MainActor func testUnrecognizedClockImportIsPrivateUntilAppliedAndOneUndoRemovesIt() async throws {
    let model = EditorModel(); let url = try file(); let before = model.project
    model.addInputs([url])
    for _ in 0..<500 { if !model.busy { break }; try await Task.sleep(nanoseconds:10_000_000) }
    let request = try XCTUnwrap(model.dataSetupRequest)
    XCTAssertEqual(model.project,before); XCTAssertFalse(model.dirty); XCTAssertEqual(request.headers,["Ticks","Velocity"])
    let preview = try await DataSetupPreview.load(url,settings:settings())
    XCTAssertTrue(model.applyDataSetup(request,preview:preview)); XCTAssertEqual(model.project.inputs.count,1)
    XCTAssertEqual(model.project.inputs[0].duration,2); XCTAssertEqual(model.activeData?.speed(at:1,unit:"m/s"),20)
    model.undo(); XCTAssertEqual(model.project,before)
    model.redo(); XCTAssertEqual(model.project.inputs[0].dataSettings,settings())
  }
  @MainActor func testExistingSourceConfigurationPreservesTimingMarksAndPersistsOnReload() async throws {
    let url = try file(); let model = EditorModel()
    var input = MediaInput(name:"Logger",path:url.path,kind:"data",legacyIndex:7); input.duration = 2000; input.offset = 4
    model.project.inputs = [input]; model.project.rangeStart = 0.5; model.project.rangeEnd = 1.5
    let before = model.project
    let request = DataSetupRequest(url:url,headers:["Ticks","Velocity"],revision:model.documentRevision,original:input)
    let preview = try await DataSetupPreview.load(url,settings:settings())
    XCTAssertTrue(model.applyDataSetup(request,preview:preview))
    XCTAssertEqual(model.project.inputs[0].id,input.id); XCTAssertEqual(model.project.inputs[0].offset,4)
    XCTAssertEqual(model.project.inputs[0].path,url.path); XCTAssertEqual(model.project.rangeStart,0.5); XCTAssertEqual(model.project.rangeEnd,1.5)
    let save = url.deletingPathExtension().appendingPathExtension("orrp"); defer {try? FileManager.default.removeItem(at:save)}
    try model.project.save(save); let reopened = try RaceProject.read(save); let loaded = try await EditorModel.loadTelemetry(reopened)
    XCTAssertEqual(loaded[7]?.times,[0,1,2]); XCTAssertEqual(loaded[7]?.speed(at:1,unit:"m/s"),20)
    model.undo(); XCTAssertEqual(model.project,before)
  }
  @MainActor func testStaleAndChangedSourcesCannotReceivePreparedProfile() async throws {
    let url = try file(); let model = EditorModel()
    var input = MediaInput(name:"Logger",path:url.path,kind:"data"); input.duration = 2000; model.project.inputs = [input]
    let preview = try await DataSetupPreview.load(url,settings:settings())
    let stale = DataSetupRequest(url:url,headers:[],revision:UUID(),original:input)
    XCTAssertFalse(model.applyDataSetup(stale,preview:preview))
    let request = DataSetupRequest(url:url,headers:[],revision:model.documentRevision,original:input)
    model.project.inputs[0].offset = 10; let before = model.project
    XCTAssertFalse(model.applyDataSetup(request,preview:preview)); XCTAssertEqual(model.project,before)
    model.dataSetupRequest = nil
    model.enqueueDataSetup(stale); XCTAssertNil(model.dataSetupRequest)
  }
}
