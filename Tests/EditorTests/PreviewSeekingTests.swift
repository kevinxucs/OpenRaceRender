import AVFoundation
import RaceCore
import XCTest
@testable import OpenRaceRender

final class PreviewSeekingTests:XCTestCase {
  @MainActor func testScrubbingCoalescesAndSettlesOnlyTheNewestFrame() {
    var targets:[Double] = [],callbacks:[@MainActor (Bool)->Void] = [],settled:[Double] = []
    let queue = PreviewSeekController(seek:{time,done in targets.append(time);callbacks.append(done)},settled:{_,time in settled.append(time)})
    queue.request(1);queue.request(2);queue.request(3)
    XCTAssertEqual(targets,[1]);XCTAssertTrue(queue.isSeeking)
    callbacks[0](false) // superseded/aborted seeks still chase the newest target
    XCTAssertEqual(targets,[1,3]);XCTAssertTrue(settled.isEmpty)
    queue.request(3);callbacks[1](true)
    XCTAssertEqual(settled,[3]);XCTAssertFalse(queue.isSeeking)
    queue.request(.nan);XCTAssertEqual(targets,[1,3])
  }
  @MainActor func testReplacedPlayerCannotResumeFromAnOldSeekCompletion() {
    var callbacks:[@MainActor (Bool)->Void] = [],settled:[Double] = []
    let queue = PreviewSeekController(seek:{_,done in callbacks.append(done)},settled:{_,time in settled.append(time)})
    queue.request(1);queue.request(2);queue.invalidate();queue.request(4)
    callbacks[0](true);XCTAssertTrue(settled.isEmpty);XCTAssertTrue(queue.isSeeking)
    callbacks[1](true);XCTAssertEqual(settled,[4]);XCTAssertFalse(queue.isSeeking)
  }
  @MainActor func wait(_ condition:@escaping @MainActor ()->Bool) async throws {
    for _ in 0..<500 {if condition() {return};try await Task.sleep(nanoseconds:10_000_000)}
    XCTFail("Preview did not finish composing the requested frame")
    throw RaceError.invalid("Preview test timed out")
  }
  @MainActor func testPausedRapidAndEndSeeksProduceComposedPixelsAndPauseWins() async throws {
    let suite = "OpenRaceRender.seek.test."+UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName:suite));defer {defaults.removePersistentDomain(forName:suite)}
    let model = EditorModel(preferences:defaults)
    var project = RaceProject();project.width = 320;project.height = 180;project.fps = 30;project.explicitDuration = 3
    var background = DisplayObject(name:"Frame marker",kind:.shape);background.shape = ShapeSettings();background.x = 0;background.y = 0;background.width = 100;background.height = 100;background.color = "#FF0000"
    var change = ObjectSegment(time:1);change.color = "#00FF00";background.segments = [change]
    var badge = background;badge.id = UUID();badge.name = "HUD";badge.width = 20;badge.height = 20;badge.color = "#0000FF";badge.segments = nil
    project.objects = [background,badge];model.project = project;model.dirty = false
    var settings = PreviewSettings();settings.height = 180;settings.fps = 15;model.previewSettings = settings
    try await wait {model.previewPlayer?.currentItem?.status == .readyToPlay}
    let player = try XCTUnwrap(model.previewPlayer),item = try XCTUnwrap(player.currentItem)
    XCTAssertTrue(item.seekingWaitsForVideoCompositionRendering)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]);item.add(output)
    defer {model.pause();item.remove(output);model.previewPlayer = nil}
    func frame(at target:Double) async throws -> CVPixelBuffer {
      var result:CVPixelBuffer?
      try await wait {
        guard abs(player.currentTime().seconds-target) < 0.002 else {return false}
        result = output.copyPixelBuffer(forItemTime:CMTime(seconds:target,preferredTimescale:60000),itemTimeForDisplay:nil)
        return result != nil
      }
      return try XCTUnwrap(result)
    }
    func pixel(_ buffer:CVPixelBuffer,_ x:Int,_ y:Int) -> [UInt8] {
      CVPixelBufferLockBaseAddress(buffer,.readOnly);defer {CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
      let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self),i = y*CVPixelBufferGetBytesPerRow(buffer)+x*4
      return [bytes[i],bytes[i+1],bytes[i+2]]
    }
    for target in [0.5,1.5,0.25,2.5] {
      model.seek(target);let buffer = try await frame(at:target)
      XCTAssertEqual(pixel(buffer,160,90),target < 1 ? [0,0,255] : [0,255,0])
      XCTAssertEqual(pixel(buffer,10,170),[255,0,0],"HUD must survive paused seeks too")
    }
    model.seek(2.5);model.seek(0.5);model.seek(1.5)
    let chased = try await frame(at:1.5);XCTAssertEqual(pixel(chased,160,90),[0,255,0])
    model.play();model.seek(0.5);model.pause()
    _ = try await frame(at:0.5);XCTAssertFalse(model.playing);XCTAssertEqual(player.rate,0)
    model.seek(3);_ = try await frame(at:3-1.0/15)
    XCTAssertEqual(model.time,3);XCTAssertEqual(model.project,project);XCTAssertFalse(model.dirty)
    model.seek(1.5);_ = try await frame(at:1.5)
    model.setPreviewSeeking(true)
    XCTAssertTrue(model.previewPlayer === player,"Retain the visible player until replacement composition is primed")
    try await wait {model.previewPlayer !== player && model.previewPlayer?.currentItem?.status == .readyToPlay}
    model.setPreviewSeeking(false)
    model.pause()
  }
}
