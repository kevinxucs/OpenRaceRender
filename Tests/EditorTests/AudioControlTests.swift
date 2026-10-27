import RaceCore
import SwiftUI
import XCTest
@testable import OpenRaceRender

final class AudioControlTests:XCTestCase {
  @MainActor func testSourcePercentControlsClampAndPreserveRoutingWithUndo() {
    let model = EditorModel(); var input = MediaInput(name:"Audio",path:"",kind:"audio"); input.volume = 0.7; var audio = AudioSettings(); audio.routing = .swap; input.audio = audio; model.project.inputs = [input]
    let before = model.project,binding = model.inputBinding(input.id)
    let settings = Binding<AudioSettings>(get:{binding.wrappedValue.audio ?? AudioSettings()},set:{var value = binding.wrappedValue; value.audio = $0; binding.wrappedValue = value})
    let controls = AudioControls(settings:settings,source:true,sourceVolume:binding.volume)
    controls.percent.wrappedValue = 125; XCTAssertEqual(model.project.inputs[0].volume,1.25); XCTAssertEqual(model.project.inputs[0].audio?.routing,.swap)
    model.undo(); XCTAssertEqual(model.project,before)
    controls.percent.wrappedValue = -10; XCTAssertEqual(model.project.inputs[0].volume,0)
    controls.percent.wrappedValue = 300; XCTAssertEqual(model.project.inputs[0].volume,2)
  }
  @MainActor func testDisplayAudioRoutingAndMuteGainAreIndependentAndUndoable() {
    let model = EditorModel(); let a = DisplayObject(name:"A",kind:.video),b = DisplayObject(name:"B",kind:.video); model.project.objects = [a,b]; let before = model.project
    let object = model.objectBinding(a.id)
    let settings = Binding<AudioSettings>(get:{object.wrappedValue.audio ?? AudioSettings()},set:{var value = object.wrappedValue; value.audio = $0; object.wrappedValue = value})
    let controls = AudioControls(settings:settings)
    var value = AudioSettings(); value.routing = .right; value.balance = 1; settings.wrappedValue = value
    controls.percent.wrappedValue = 0; XCTAssertEqual(model.project.objects[0].audio?.volume,0); XCTAssertNil(model.project.objects[1].audio)
    model.undo(); XCTAssertEqual(model.project.objects[0].audio?.routing,.right)
    model.undo(); XCTAssertEqual(model.project,before)
  }
}
