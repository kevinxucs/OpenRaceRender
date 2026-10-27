import RaceCore
import XCTest
@testable import OpenRaceRender

final class TelemetrySmoothingEditorTests:XCTestCase {
  @MainActor func testSourceSmoothingEditsAreUndoableAndNotTemplateState() throws {
    let model = EditorModel(); var input = MediaInput(name:"GPS",path:"",kind:"data"); input.duration = 10
    model.project.inputs = [input]; var object = DisplayObject(name:"Map",kind:.map); object.inputIndex = 0; model.project.objects = [object]
    let before = model.project
    var settings = DataSettings(); settings.detectGPSUpdates = true; settings.smoothCurves = true; input.dataSettings = settings
    model.inputBinding(input.id).wrappedValue = input
    XCTAssertEqual(model.project.inputs[0].dataSettings,settings)
    let layout = try model.project.reusableLayout(); XCTAssertNil(layout.inputs[0].dataSettings)
    model.undo(); XCTAssertEqual(model.project,before); model.redo(); XCTAssertEqual(model.project.inputs[0].dataSettings,settings)
  }
}
