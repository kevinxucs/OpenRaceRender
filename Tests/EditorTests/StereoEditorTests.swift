import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class StereoEditorTests:XCTestCase {
  @MainActor func testStereoPairIsOneUndoAndKeepsBothDisplaysSelected() throws {
    let model = EditorModel()
    model.project.inputs = [MediaInput(name:"L",path:"/tmp/l.mp4",kind:"video",legacyIndex:0),MediaInput(name:"R",path:"/tmp/r.mp4",kind:"video",legacyIndex:1)]
    model.project.objects = [DisplayObject(name:"HUD",kind:.speed)]
    let before = model.project
    try model.addStereoPair(left:0,right:1,layout:.redCyan,convergence:0)
    XCTAssertEqual(model.selectedIDs.count,2);XCTAssertEqual(model.project.objects.count,3)
    model.undo();XCTAssertEqual(model.project,before)
    model.redo();XCTAssertEqual(model.project.objects.count,3)
  }
}
