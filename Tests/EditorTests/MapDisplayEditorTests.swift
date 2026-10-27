import RaceCore
import XCTest
@testable import OpenRaceRender

final class MapDisplayEditorTests:XCTestCase {
  @MainActor func testMapEditsResetUndoAndPortableLapCleanup() throws {
    let model = EditorModel(); var input = MediaInput(name:"GPS",path:"",kind:"data"); input.duration = 40
    var map = DisplayObject(name:"Map",kind:.map); model.project.inputs = [input]; model.project.objects = [map]
    let before = model.project
    let controls = MapDisplayControls(object:model.objectBinding(map.id),data:nil)
    var style = MapDisplaySettings(); style.zoom = 2; style.rotation = 90; style.icon = .car; style.trace = .lap; style.lapStart = 10
    controls.settings.wrappedValue = style
    XCTAssertEqual(model.project.objects[0].mapSettings,style)
    let layout = try model.project.reusableLayout(); XCTAssertNil(layout.objects[0].mapSettings?.lapStart); XCTAssertEqual(layout.objects[0].mapSettings?.trace,.all)
    model.undo(); XCTAssertEqual(model.project,before)
    model.redo(); map = model.project.objects[0]; map.mapSettings = nil; model.objectBinding(map.id).wrappedValue = map
    XCTAssertNil(model.project.objects[0].mapSettings); model.undo(); XCTAssertEqual(model.project.objects[0].mapSettings,style)
  }
}
