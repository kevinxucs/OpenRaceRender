import XCTest
@testable import RaceCore

final class AssetValidationTests: XCTestCase {
  func testExportChecksOnlyVisibleSourcesInSelectedSpanIncludingSwitches() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([0]).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
    var p = RaceProject()
    var camera = MediaInput(name: "Camera", path: file.path, kind: "video", legacyIndex: 0); camera.duration = 20
    var missing = MediaInput(name: "Other camera", path: "/missing/camera.mp4", kind: "video", legacyIndex: 1); missing.duration = 20
    var data = MediaInput(name: "Telemetry", path: "/missing/laps.csv", kind: "data", legacyIndex: 2); data.duration = 20
    p.inputs = [camera, missing, data]
    var video = DisplayObject(name: "Video", kind: .video)
    var switchCamera = ObjectSegment(time: 10); switchCamera.inputIndex = 1
    video.segments = [switchCamera]
    var speed = DisplayObject(name: "Speed", kind: .speed); speed.inputIndex = 2; speed.start = 12
    p.objects = [video, speed]
    XCTAssertNoThrow(try p.validateExportAssets(start: 0, duration: 10))
    XCTAssertThrowsError(try p.validateExportAssets(start: 10, duration: 1)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Other camera"))
      XCTAssertFalse(error.localizedDescription.contains("Telemetry"))
    }
    XCTAssertThrowsError(try p.validateExportAssets(start: 12, duration: 1)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Telemetry"))
    }
    p.objects[0].segments?[0].visible = false; p.objects[1].opacity = 0
    XCTAssertNoThrow(try p.validateExportAssets(start: 12, duration: 1))
  }
  func testJoinedMissingClipIsRequiredOnlyWhenItsSpanIsRendered() {
    var p = RaceProject()
    var first = MediaInput(name: "First", path: "/missing/first.mp4", kind: "video", legacyIndex: 0); first.duration = 5
    var second = MediaInput(name: "Second", path: "/missing/second.mp4", kind: "video", legacyIndex: 1); second.duration = 5; second.joinedTo = 0
    p.inputs = [first, second]; p.objects = [DisplayObject(name: "Camera", kind: .video)]
    XCTAssertThrowsError(try p.validateExportAssets(start: 5, duration: 1)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Second"))
      XCTAssertFalse(error.localizedDescription.contains("First"))
    }
  }
  func testEmbeddedArtworkDoesNotNeedItsOldExternalFile() {
    var p = RaceProject()
    var logo = DisplayObject(name: "Logo", kind: .image); logo.text = "/missing/logo.png"
    var gauge = DisplayObject(name: "Gauge", kind: .speed); gauge.gauge = GaugeSettings(); gauge.gauge?.backgroundPath = "/missing/face.png"
    p.objects = [logo, gauge]
    XCTAssertThrowsError(try p.validateExportAssets(start: 0, duration: 1)) { error in
      XCTAssertTrue(error.localizedDescription.contains("logo.png"))
      XCTAssertTrue(error.localizedDescription.contains("face.png"))
    }
    p.objects[0].embeddedImage = Data([1]); p.objects[1].gauge?.backgroundImage = Data([2])
    XCTAssertNoThrow(try p.validateExportAssets(start: 0, duration: 1))
  }
}
