import AVFoundation
import RaceCore
import XCTest
@testable import OpenRaceRender

final class PreviewSettingsEditorTests:XCTestCase {
  @MainActor func testPreferencesDoNotChangeDocumentOrUndoAndCorruptionFallsBack() throws {
    let suite = "OpenRaceRender.preview.test."+UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName:suite)); defer {defaults.removePersistentDomain(forName:suite)}
    let model = EditorModel(preferences:defaults)
    model.project.width = 3840; model.project.height = 2160; model.project.fps = 60; model.project.rangeStart = 2; model.project.rangeEnd = 5
    model.dirty = false; let before = model.project
    var settings = PreviewSettings(); settings.height = 540; settings.fps = 24; settings.scaling = .linear; settings.audio = .mono; settings.audioBits = 8
    model.previewSettings = settings
    XCTAssertFalse(model.dirty); XCTAssertEqual(model.project,before)
    let reloaded = EditorModel(preferences:defaults); XCTAssertEqual(reloaded.previewSettings,settings)
    model.setPreviewSeeking(true); XCTAssertEqual(model.previewOptions.scaling,.nearest); XCTAssertEqual(model.previewOptions.fps,15)
    model.setPreviewSeeking(false); XCTAssertEqual(model.previewOptions.scaling,.linear); XCTAssertEqual(model.previewOptions.fps,24)
    model.previewMuted = true; XCTAssertEqual(model.previewOptions.audio,.disabled)
    model.previewMuted = false; XCTAssertEqual(model.previewOptions.audio,.mono)
    model.undo(); XCTAssertEqual(model.project,before); XCTAssertFalse(model.dirty)
    defaults.set(Data("broken".utf8),forKey:"previewSettings"); XCTAssertEqual(EditorModel(preferences:defaults).previewSettings,PreviewSettings())
    settings.height = -1; defaults.set(try JSONEncoder().encode(settings),forKey:"previewSettings")
    XCTAssertEqual(EditorModel(preferences:defaults).previewSettings,PreviewSettings())
  }
  @MainActor func testFullscreenSyncAndEditorHaveOneVideoOwnerAndDetachCleanly() {
    let model = EditorModel(),player = AVPlayer(); model.previewPlayer = player
    let editor = PreviewView(),sync = PreviewView(),screen = PreviewView()
    sync.interactive = false; screen.interactive = false; screen.fullScreen = true
    let views = [editor,sync,screen]
    for view in views { view.model = model; model.previewSurfaces.add(view) }
    func expect(_ owner:PreviewView) {
      model.refreshPreviewOwnership()
      for view in views { XCTAssertEqual(view.compositionLayer.player === player,view === owner) }
    }
    expect(editor)
    model.fullScreenPreviewActive = true; expect(screen)
    model.showSync = true; expect(sync)
    model.showSync = false; expect(screen)
    model.setupSyncActive = true; expect(sync)
    model.fullScreenPreviewActive = false; expect(sync)
    model.setupSyncActive = false; expect(editor)
    for view in views { view.disconnect() }
    XCTAssertTrue(model.previewSurfaces.allObjects.isEmpty)
  }
}
