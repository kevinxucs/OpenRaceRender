import RaceCore
import XCTest
@testable import OpenRaceRender

final class GraphEditorTests: XCTestCase {
  @MainActor func testInspectorBindingsParticipateInUndoTimelineAndTemplateDraft() throws {
    let model = EditorModel()
    model.project.inputs = [MediaInput(name:"Logger",path:"",kind:"data",legacyIndex:9)]
    model.addObject(.graph)
    let id = try XCTUnwrap(model.selected)
    XCTAssertEqual(model.project.objects[0].inputIndex,9)
    XCTAssertNotNil(model.project.objects[0].graph)
    let before = model.project
    let controls = GraphControls(object:model.objectBinding(id),headers:["Speed","Brake"])
    controls.settings.axis.wrappedValue = .channel
    controls.settings.horizontalChannel.wrappedValue = "Brake"
    XCTAssertEqual(model.project.objects[0].graph?.resolvedHorizontalChannel,"Brake")
    model.undo(); model.undo(); XCTAssertEqual(model.project,before)
    model.editingSegment = 2
    controls.settings.timeSpan.wrappedValue = 4
    XCTAssertEqual(model.project.objects[0].graph?.timeSpan,10)
    XCTAssertEqual(model.project.objects[0].resolved(at:2).graph?.timeSpan,4)
    model.undo(); XCTAssertEqual(model.project,before)
    model.editingSegment = nil
    controls.settings.mode.wrappedValue = .centered
    model.beginTemplateDraft(style:false)
    XCTAssertEqual(try model.templateDraft().objects[0].graph?.mode,.centered)
  }
}
