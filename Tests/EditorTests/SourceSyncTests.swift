import AVFoundation
import RaceCore
import XCTest
@testable import OpenRaceRender

final class SourceSyncEditorTests: XCTestCase {
  @MainActor func testAlignmentRateAndOffsetApplyTogetherAndUndoRestoresBoth() throws {
    let model = EditorModel()
    var a = MediaInput(name:"Front",path:"a.mov",kind:"video",legacyIndex:0); a.duration = 20
    var b = MediaInput(name:"Rear",path:"b.mov",kind:"video",legacyIndex:1); b.duration = 20
    model.project.inputs = [a,b]; model.project.rangeStart = 1; model.project.rangeEnd = 9
    let before = model.project
    XCTAssertEqual(model.alignSources(target:SourceSyncAnchor(b.id,at:8),reference:SourceSyncAnchor(a.id,at:5),rate:0.5),5)
    XCTAssertEqual(model.project.sourceTime(for:1,at:5),8); XCTAssertEqual(model.project.inputs[1].timing?.rate,0.5)
    model.undo(); XCTAssertEqual(model.project,before)
    XCTAssertNil(model.alignSources(target:SourceSyncAnchor(b.id,at:40),reference:SourceSyncAnchor(a.id,at:5),rate:1))
    XCTAssertEqual(model.project,before); XCTAssertNotNil(model.error)
  }
  @MainActor func testRawPlayerSeeksRealMediaAndClearsOldState() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mov")
    defer { try? FileManager.default.removeItem(at:file) }
    let writer = try AVAssetWriter(outputURL:file,fileType:.mov)
    let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:32,AVVideoHeightKey:32])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:32,kCVPixelBufferHeightKey as String:32])
    writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime:.zero)
    for frame in 0..<6 {
      for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:10_000_000) }
      XCTAssertTrue(input.isReadyForMoreMediaData)
      var buffer:CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,try XCTUnwrap(adaptor.pixelBufferPool),&buffer),kCVReturnSuccess)
      let pixel = try XCTUnwrap(buffer); CVPixelBufferLockBaseAddress(pixel,[])
      memset(try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel)),Int32(frame*30),CVPixelBufferGetDataSize(pixel))
      CVPixelBufferUnlockBaseAddress(pixel,[])
      XCTAssertTrue(adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
    }
    writer.endSession(atSourceTime:CMTime(value:6,timescale:30)); input.markAsFinished(); await writer.finishWriting()
    XCTAssertEqual(writer.status,.completed)
    let player = SourceSyncPlayer()
    let source = MediaInput(name:"Original synthetic video",path:file.path,kind:"video")
    await player.load(source,at:0.1,projectFPS:60)
    for _ in 0..<100 where player.seeking { try await Task.sleep(nanoseconds:50_000_000) }
    XCTAssertNil(player.error); XCTAssertFalse(player.seeking)
    XCTAssertEqual(player.duration,0.2,accuracy:0.01); XCTAssertEqual(player.fps,30,accuracy:0.01)
    XCTAssertEqual(player.time,0.1,accuracy:1.0/30); XCTAssertNotNil(player.player.currentItem)
    player.clear(); XCTAssertNil(player.player.currentItem); XCTAssertEqual(player.duration,0); XCTAssertFalse(player.playing)
    await player.load(MediaInput(name:"Missing",path:file.path+".missing",kind:"video"),at:0,projectFPS:30)
    XCTAssertNotNil(player.error); XCTAssertNil(player.player.currentItem); XCTAssertEqual(player.duration,0)
    player.clear()
  }
}
