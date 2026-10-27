import AVFoundation
import RaceCore
import XCTest
@testable import OpenRaceRender

final class ProjectSetupEditorTests: XCTestCase {
  @MainActor func testPreferredUnitsAndNewSessionSetupPersistWithoutChangingOpenedProjectUnits() throws {
    let suite = "ProjectSetup-"+UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName:suite)); defer { preferences.removePersistentDomain(forName:suite) }
    let first = EditorModel(preferences:preferences)
    first.setPreferredSpeedUnit("km/h"); first.setupOnNewProjects = true
    first.setPreferredSpeedUnit("invalid"); XCTAssertEqual(first.preferredSpeedUnit,"km/h")
    let next = EditorModel(preferences:preferences)
    XCTAssertEqual(next.project.speedUnit,"km/h"); XCTAssertFalse(next.dirty)
    next.newProject(); XCTAssertTrue(next.showProjectSetup); XCTAssertEqual(next.project.speedUnit,"km/h")
    var existing = RaceProject(); existing.speedUnit = "knots"; next.project = existing
    XCTAssertEqual(next.project.speedUnit,"knots"); XCTAssertEqual(next.preferredSpeedUnit,"km/h")
  }
  @MainActor func testLengthAndNotesUndoAndBoundSourceRemovalRestoreCompleteState() {
    let model = EditorModel(); var input = MediaInput(name:"Camera",path:"",kind:"video",legacyIndex:7); input.duration = 8
    model.project.inputs = [input]
    let before = model.project
    model.matchProjectLength(to:7); XCTAssertEqual(model.project.lengthInputIndex,7)
    model.removeInput(input.id); XCTAssertNil(model.project.lengthInputIndex)
    model.undo(); XCTAssertEqual(model.project.lengthInputIndex,7); XCTAssertEqual(model.project.inputs,[input])
    model.undo(); XCTAssertEqual(model.project,before)
    model.time = 7; model.playing = true
    model.setProjectLength(4); XCTAssertEqual(model.project.duration,4)
    XCTAssertEqual(model.time,4-1.0/30,accuracy:1e-9); XCTAssertFalse(model.playing)
    model.undo(); XCTAssertEqual(model.project,before)
    model.setProjectNotes("First session\nCheck the second lap")
    XCTAssertEqual(model.project.notes,"First session\nCheck the second lap")
    model.undo(); XCTAssertEqual(model.project,before)
    model.setProjectLength(.nan); XCTAssertEqual(model.project,before); XCTAssertNotNil(model.error)
  }
  @MainActor func testSetupDataSelectionControlsTemplateMappingAndKeepsExplicitNone() {
    let model = EditorModel()
    var first = MediaInput(name:"First data",path:"",kind:"data",legacyIndex:3); first.duration = 10
    var second = first; second.id = UUID(); second.legacyIndex = 8; second.name = "Selected data"
    model.project.inputs = [first,second]
    var layout = RaceProject(); var role = first; role.legacyIndex = 0; layout.inputs = [role]
    var display = DisplayObject(name:"Speed",kind:.speed); display.inputIndex = 0; layout.objects = [display]
    let browser = TemplateBrowser(model:model,preferredDataIndex:8)
    XCTAssertEqual(browser.defaultInput(for:role),8)
    let mapping = browser.resolvedMapping(layout)
    model.apply(layout,replace:true,mapping:mapping)
    XCTAssertEqual(model.project.objects[0].inputIndex,8)
    model.undo(); XCTAssertTrue(model.project.objects.isEmpty)
    let unavailable = TemplateBrowser(model:model,preferredDataIndex:999)
    XCTAssertEqual(unavailable.defaultInput(for:role),3)
    let explicitNone = TemplateBrowser(model:model,preferredDataIndex:8,mapping:[0:-1])
    XCTAssertEqual(explicitNone.resolvedMapping(layout)[0],-1)
  }
  @MainActor func testNestedSetupSynchronizationReturnsPlayerToCanvas() {
    let model = EditorModel(), player = AVPlayer()
    model.previewPlayer = player
    let canvas = PreviewView(), wizard = PreviewView()
    canvas.model = model; wizard.model = model; wizard.interactive = false
    model.setupSyncActive = true; canvas.refresh(); wizard.refresh()
    XCTAssertNil(canvas.compositionLayer.player); XCTAssertTrue(wizard.compositionLayer.player === player)
    model.setupSyncActive = false; wizard.refresh(); canvas.refresh()
    XCTAssertTrue(canvas.compositionLayer.player === player); XCTAssertNil(wizard.compositionLayer.player)
    wizard.disconnect(); canvas.disconnect()
  }
}
