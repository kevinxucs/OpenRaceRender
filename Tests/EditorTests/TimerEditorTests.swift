import RaceCore
import XCTest
@testable import OpenRaceRender

final class TimerEditorTests:XCTestCase {
  @MainActor func testManualTimerControlsUseOneUndoableBindingAndReset() {
    let model = EditorModel(); let o = DisplayObject(name:"Timer",kind:.timer); model.project.objects = [o]; let before = model.project
    let controls = TimerControls(object:model.objectBinding(o.id),model:model)
    var settings = TimerSettings(); settings.mode = .manual; settings.startDelay = 2; settings.stopValue = 10
    controls.settings.wrappedValue = settings
    XCTAssertEqual(model.project.objects[0].timerSettings,settings)
    model.undo(); XCTAssertEqual(model.project,before); model.redo()
    var reset = model.project.objects[0]; reset.timerSettings = nil; model.objectBinding(o.id).wrappedValue = reset
    XCTAssertNil(model.project.objects[0].timerSettings); model.undo(); XCTAssertEqual(model.project.objects[0].timerSettings,settings)
  }
}
