import RaceCore
import XCTest
@testable import OpenRaceRender

final class ScriptEditorTests:XCTestCase {
  @MainActor func testPrivateDraftAppliesOneUndoableTimelineEditAndPreservesSourceGeometry() throws {
    let model = EditorModel();var object = DisplayObject(name:"Scripted",kind:.enhanced);object.inputIndex = 5;object.x = 27;model.project.objects = [object]
    let before = model.project;model.beginScriptEditor(object.id)
    let request = try XCTUnwrap(model.scriptEditorRequest)
    var draft = EnhancedScriptDraft(object:request.object);draft.foreground = "DrawRect(0,0,SizeX,SizeY,Red,Filled);"
    XCTAssertEqual(model.project,before)
    try model.applyScript(draft,request:request)
    XCTAssertTrue(model.project.objects[0].hasScriptStyleSettings);XCTAssertEqual(model.project.objects[0].inputIndex,5);XCTAssertEqual(model.project.objects[0].x,27)
    model.undo();XCTAssertEqual(model.project,before)
    model.editingSegment = 2;model.beginScriptEditor(object.id)
    let event = try XCTUnwrap(model.scriptEditorRequest);try model.applyScript(draft,request:event)
    XCTAssertNil(model.project.objects[0].resolved(at:1).legacyPayload)
    XCTAssertEqual(EnhancedScriptDraft(object:model.project.objects[0].resolved(at:3)).foreground,draft.foreground)
    model.undo();XCTAssertEqual(model.project,before)
  }
  @MainActor func testStaleAndInvalidDraftsCannotOverwriteChanges() throws {
    let model = EditorModel();let object = DisplayObject(name:"Scripted",kind:.enhanced);model.project.objects = [object]
    model.beginScriptEditor(object.id);let request = try XCTUnwrap(model.scriptEditorRequest)
    let draft = EnhancedScriptDraft(object:object)
    model.objectBinding(object.id).wrappedValue.name = "Renamed"
    let after = model.project;XCTAssertThrowsError(try model.applyScript(draft,request:request));XCTAssertEqual(model.project,after)
    model.beginScriptEditor(object.id);let fresh = try XCTUnwrap(model.scriptEditorRequest)
    var invalid = draft;invalid.foreground = "UnknownCall();"
    XCTAssertThrowsError(try model.applyScript(invalid,request:fresh));XCTAssertEqual(model.project,after)
    model.editingSegment = 2;XCTAssertThrowsError(try model.applyScript(draft,request:fresh));XCTAssertEqual(model.project,after)
  }
}
