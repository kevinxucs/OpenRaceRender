import RaceCore
import XCTest
@testable import OpenRaceRender

final class BackgroundEditorTests: XCTestCase {
  @MainActor func testBackgroundDraftAndSingleApplyUndoDoNotLeakUnappliedEdits() throws {
    let model = EditorModel(); model.addObject(.map)
    let id = try XCTUnwrap(model.selected), before = model.project
    var draft = BackgroundDraft(image:Data([1,2,3])); draft.zoom = 2; draft.offsetX = 10
    XCTAssertEqual(model.project,before,"Draft/Cancel must not change the session")
    model.objectBinding(id).wrappedValue = WidgetBackground.replacing(draft.image,in:model.objectBinding(id).wrappedValue)
    XCTAssertEqual(model.project.objects[0].artwork,draft.image)
    model.undo(); XCTAssertEqual(model.project,before)
    model.editingSegment = 2
    model.objectBinding(id).wrappedValue = WidgetBackground.replacing(draft.image,in:model.objectBinding(id).wrappedValue)
    XCTAssertNil(model.project.objects[0].artwork)
    XCTAssertEqual(model.project.objects[0].resolved(at:2).artwork,draft.image)
    model.undo(); XCTAssertEqual(model.project,before)
  }
}
