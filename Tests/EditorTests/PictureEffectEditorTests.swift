import RaceCore
import SwiftUI
import XCTest
@testable import OpenRaceRender

final class PictureEffectEditorTests:XCTestCase {
  @MainActor func testKeyRGBAndPercentFieldsClampPreserveTimingAndUndo() {
    let model = EditorModel(); var input = MediaInput(name:"Camera",path:"",kind:"video"); input.duration = 10; input.offset = 2
    var p = PictureSettings(); p.chromaKey = ChromaKeySettings(); input.picture = p; model.project.inputs = [input]; let before = model.project
    let binding = model.inputBinding(input.id)
    let picture = Binding<PictureSettings>(get:{binding.wrappedValue.picture ?? PictureSettings()},set:{var value = binding.wrappedValue; value.picture = $0; binding.wrappedValue = value})
    let controls = PictureEffectControls(settings:picture)
    controls.component(16).wrappedValue = 300; XCTAssertEqual(model.project.inputs[0].picture?.chromaKey?.color,"#FFFF00")
    controls.keyValue(\.colorTolerance).wrappedValue = 150; XCTAssertEqual(model.project.inputs[0].picture?.chromaKey?.colorTolerance,1)
    XCTAssertEqual(model.project.inputs[0].offset,2); XCTAssertEqual(model.project.inputs[0].duration,10)
    model.undo(); model.undo(); XCTAssertEqual(model.project,before)
  }
  @MainActor func testDisplayEffectsUseTimelineInheritanceAndExplicitReset() {
    let model = EditorModel(); let object = DisplayObject(name:"Image",kind:.image); model.project.objects = [object]
    var picture = PictureSettings(); var tint = ColorizeSettings(); tint.mode = .spectrum; picture.colorize = tint
    var edited = object; edited.picture = picture; model.objectBinding(object.id).wrappedValue = edited
    model.editingSegment = 2; edited.picture = nil; model.objectBinding(object.id).wrappedValue = edited
    XCTAssertNotNil(model.project.objects[0].resolved(at:1).picture?.colorize)
    XCTAssertNil(model.project.objects[0].resolved(at:3).picture)
    model.undo(); XCTAssertEqual(model.project.objects[0].picture,picture)
  }
}
