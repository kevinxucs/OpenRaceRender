import RaceCore
import XCTest
@testable import OpenRaceRender

final class MapComparisonEditorTests:XCTestCase {
  @MainActor func testDuplicateForMapIsOneUndoableSourceAndWidgetChange() throws {
    let model = EditorModel(); var input = MediaInput(name:"Run",path:"",kind:"data",legacyIndex:1); input.duration = 40
    var map = DisplayObject(name:"Comparison",kind:.map); map.inputIndex = 1
    model.project.inputs = [input]; model.project.objects = [map]; let before = model.project
    let id = try XCTUnwrap(model.duplicateData(input.id,forMap:map.id))
    XCTAssertEqual(model.project.inputs.count,2); XCTAssertEqual(model.project.inputs.last?.id,id)
    XCTAssertEqual(model.project.objects[0].mapComparison?.referenceInputIndex,2)
    XCTAssertEqual(model.project.objects[0].mapComparison?.mode,.timeline)
    model.undo(); XCTAssertEqual(model.project,before)
    model.redo(); XCTAssertEqual(model.project.inputs.count,2)
  }
  @MainActor func testReferenceRemovalClearsBaseAndTimelineReferencesAndUndoRestoresThem() {
    let model = EditorModel(); let a = MediaInput(name:"A",path:"",kind:"data",legacyIndex:1),b = MediaInput(name:"B",path:"",kind:"data",legacyIndex:2)
    var map = DisplayObject(name:"Comparison",kind:.map); map.inputIndex = 1
    var settings = MapComparisonSettings(); settings.referenceInputIndex = 2; map.mapComparison = settings
    var segment = ObjectSegment(time:2); segment.mapComparison = settings; map.segments = [segment]
    model.project.inputs = [a,b]; model.project.objects = [map]; let before = model.project
    model.removeInput(b.id)
    XCTAssertEqual(model.project.objects[0].mapComparison?.referenceInputIndex,-1)
    XCTAssertEqual(model.project.objects[0].segments?[0].mapComparison?.referenceInputIndex,-1)
    model.undo(); XCTAssertEqual(model.project,before)
  }
}
