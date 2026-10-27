import RaceCore
import XCTest
@testable import OpenRaceRender

final class FinishLineEditorTests:XCTestCase {
  func testMapProjectionRoundtripsCoordinatesAtDifferentSizesAndAcrossDateline() {
    for size in [CGSize(width:450,height:360),CGSize(width:1000,height:500)] {
      let samples = [GPSTrackSample(time:0,latitude:36,longitude:179.999),GPSTrackSample(time:1,latitude:36.001,longitude:-179.999)]
      let projection = TrackPlotProjection(samples:samples,size:size)
      for sample in samples {
        let pixel = projection.point(latitude:sample.latitude,longitude:sample.longitude),point = projection.coordinate(pixel)
        XCTAssertEqual(point.latitude,sample.latitude,accuracy:1e-9); XCTAssertEqual(point.longitude,sample.longitude,accuracy:1e-9)
      }
    }
  }
  @MainActor func testFinishLineDraftDoesNotMutateUntilPreviewedApplyAndUndoPreservesMarks() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
    try "Time,Latitude,Longitude\n0,35.9999,-121\n2,36.0001,-121\n10,36.0001,-121.01\n20,35.9999,-121.01\n30,35.9999,-121\n32,36.0001,-121\n40,36.0002,-121\n".write(to:url,atomically:true,encoding:.utf8)
    defer {try? FileManager.default.removeItem(at:url)}
    let model = EditorModel(); var input = MediaInput(name:"Track",path:url.path,kind:"data",legacyIndex:4); input.duration = 40; input.offset = 3
    model.project.inputs = [input]; model.project.rangeStart = 2; model.project.rangeEnd = 10; model.telemetry[4] = try Telemetry(url:url)
    let before = model.project; model.editFinishLine(input)
    let editor = FinishLineEditor(model:model,input:input); XCTAssertEqual(model.project,before)
    var settings = DataSettings(); var line = FinishLine(latitude:36,longitude:-121,heading:0)
    line.precision = .sample; line.headingTolerance = 60; line.eastTolerance = 10; settings.finishLine = line
    let preview = try await DataSetupPreview.load(url,settings:settings)
    XCTAssertTrue(model.applyDataSetup(editor.request,preview:preview)); XCTAssertEqual(model.telemetry[4]?.laps[1].start,2)
    XCTAssertEqual(model.project.inputs[0].offset,3); XCTAssertEqual(model.project.rangeStart,2); XCTAssertEqual(model.project.rangeEnd,10)
    let file = url.deletingPathExtension().appendingPathExtension("orrp"); defer {try? FileManager.default.removeItem(at:file)}
    try model.project.save(file); let reopened = try RaceProject.read(file); XCTAssertEqual(reopened.inputs[0].dataSettings,settings)
    let loaded = try await EditorModel.loadTelemetry(reopened); XCTAssertEqual(loaded[4]?.laps[1].start,2)
    model.undo(); XCTAssertEqual(model.project,before)
  }
}
