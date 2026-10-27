import RaceCore
import XCTest
@testable import OpenRaceRender

final class OutputSettingsEditorTests:XCTestCase {
  @MainActor func testProfileAndOutputEditsPreserveCanvasPreviewMarksAndUndo() throws {
    let model = EditorModel(); model.project.width = 2560; model.project.height = 1440; model.project.fps = 60; model.project.rangeStart = 2; model.project.rangeEnd = 8
    let before = model.project,preview = model.previewOptions
    let profile = try XCTUnwrap(OutputProfile.builtins.first{$0.id == "television-1080"})
    model.applyOutputProfile(profile)
    XCTAssertEqual(model.project.exportSettings?.output?.width,1920); XCTAssertEqual(model.project.exportSettings?.output?.fps,30)
    XCTAssertEqual(model.project.width,2560); XCTAssertEqual(model.project.height,1440); XCTAssertEqual(model.project.fps,60)
    XCTAssertEqual(model.project.rangeStart,2); XCTAssertEqual(model.project.rangeEnd,8); XCTAssertEqual(model.previewOptions,preview)
    model.undo(); XCTAssertEqual(model.project,before)
    model.setOutputSize(width:640,height:480)
    model.outputBinding(\.audioSampleRate).wrappedValue = 44100; model.outputBinding(\.audioChannels).wrappedValue = 1
    model.outputBinding(\.border).wrappedValue = 0.05
    XCTAssertNil(model.project.exportSettings?.profileID); XCTAssertEqual(model.project.width,2560)
    XCTAssertEqual(model.project.exportSettings?.output?.audioChannels,1)
    let valid = model.project
    model.setOutputSize(width:Int.max,height:480); XCTAssertEqual(model.project,valid); XCTAssertNotNil(model.error)
  }
  @MainActor func testNamedProfilesPersistUpdateAndRemoveWithoutLosingAppliedSettings() throws {
    let suite = "OpenRaceRender.output.test."+UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName:suite)); defer {preferences.removePersistentDomain(forName:suite)}
    let model = EditorModel(preferences:preferences)
    model.setOutputSize(width:640,height:480); model.outputBinding(\.audioSampleRate).wrappedValue = 44100
    model.saveOutputProfile(name:" My road test ")
    let profile = try XCTUnwrap(model.customOutputProfiles.first)
    XCTAssertEqual(profile.name,"My road test"); XCTAssertEqual(model.project.exportSettings?.profileID,profile.id)
    let reloaded = EditorModel(preferences:preferences); XCTAssertEqual(reloaded.customOutputProfiles,[profile])
    model.outputBinding(\.border).wrappedValue = 0.05; model.saveOutputProfile(name:"my ROAD test")
    XCTAssertEqual(model.customOutputProfiles.count,1); XCTAssertEqual(model.customOutputProfiles.first?.id,profile.id)
    let applied = model.project.exportSettings
    model.removeOutputProfile(profile.id); XCTAssertTrue(model.customOutputProfiles.isEmpty)
    XCTAssertEqual(model.project.exportSettings,applied); XCTAssertTrue(EditorModel(preferences:preferences).customOutputProfiles.isEmpty)
  }
}
