import AVFoundation
import RaceCore
import XCTest
@testable import OpenRaceRender

final class CameraFreeEditorTests:XCTestCase {
  @MainActor func testGraphicsOnlyExportSetupAndActualPreviewPreparation() async throws {
    let suite = "OpenRaceRender.camera-free.test."+UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName:suite)); defer {preferences.removePersistentDomain(forName:suite)}
    let model = EditorModel(preferences:preferences)
    model.project.width = 64; model.project.height = 36; model.project.fps = 15; model.project.explicitDuration = 2
    model.project.objects = [DisplayObject(name:"Graphics only",kind:.shape)]
    model.project.rangeStart = 0.5; model.project.rangeEnd = 1.5
    let before = model.project
    model.prepareExport(); XCTAssertTrue(model.showExport); XCTAssertNil(model.error); XCTAssertNil(model.exportRangeError)
    XCTAssertEqual(model.exportStart,0.5); XCTAssertEqual(model.exportDuration,1)
    model.configurePlayers()
    for _ in 0..<120 where model.previewPlayer?.currentItem?.status != .readyToPlay {try await Task.sleep(nanoseconds:50_000_000)}
    let item = try XCTUnwrap(model.previewPlayer?.currentItem)
    XCTAssertEqual(item.status,.readyToPlay); XCTAssertEqual(item.videoComposition?.renderSize,CGSize(width:64,height:36))
    XCTAssertEqual(model.project,before); model.pause()
  }
}
