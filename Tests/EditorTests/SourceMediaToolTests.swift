import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class SourceMediaToolTests: XCTestCase {
  @MainActor func testPhysicalPlayheadUsesSelectedJoinedClipRatherThanStreamRoot() {
    let model = EditorModel()
    var a = MediaInput(name:"First",path:"/tmp/a.mov",kind:"video",legacyIndex:1); a.duration = 3
    var b = MediaInput(name:"Second",path:"/tmp/b.mov",kind:"video",legacyIndex:2); b.duration = 3; b.joinedTo = 1
    model.project.inputs = [a,b]; model.time = 4
    XCTAssertNil(model.sourceTimeAtPlayhead(a)); XCTAssertEqual(model.sourceTimeAtPlayhead(b),1)
  }
  @MainActor func testTrimAndCropApplyAsSingleUndoableInputEdits() throws {
    let model = EditorModel(); var input = MediaInput(name:"Camera",path:"",kind:"video"); input.duration = 10
    model.project.inputs = [input]; model.project.rangeStart = 2; model.project.rangeEnd = 8
    let before = model.project
    var draft = SourceTrimDraft(input:input,duration:10,frameRate:60); draft.start = 1; draft.end = 9
    XCTAssertEqual(model.project,before)
    model.inputBinding(input.id).wrappedValue = try draft.applying(to:input)
    XCTAssertEqual(model.project.inputs[0].timing?.trimStart,1)
    XCTAssertEqual(model.project.rangeStart,2); XCTAssertEqual(model.project.rangeEnd,8)
    model.undo(); XCTAssertEqual(model.project,before)
    var crop = CropSelection(size:CGSize(width:1920,height:1080)); crop.zoom(2)
    var edited = input; edited.picture = crop.picture(from:input.picture)
    model.inputBinding(input.id).wrappedValue = edited
    XCTAssertEqual(model.project.inputs[0].picture?.left,0.25)
    model.undo(); XCTAssertEqual(model.project,before)
  }
}
