import AVFoundation
import XCTest
@testable import RaceCore

final class CameraFreeTests:XCTestCase {
  func testStillImagesDefaultToGraphicsLengthAndRespectExplicitLength() {
    var p = RaceProject(); p.inputs = [MediaInput(name:"Still",path:"original.png",kind:"image")]
    XCTAssertEqual(p.duration,60)
    p.explicitDuration = 5; XCTAssertEqual(p.duration,5)
    p.explicitDuration = nil
    var data = MediaInput(name:"Logger",path:"original.csv",kind:"data"); data.duration = 8
    p.inputs.append(data); XCTAssertEqual(p.duration,8)
  }
  func testGeneratedClockIsReusedAndRecoversAfterItsTemporaryFileDisappears() async throws {
    let clock = GeneratedVideoClock()
    let (first,_,_) = try await clock.source(),(second,_,_) = try await clock.source()
    XCTAssertEqual(first.url,second.url)
    try FileManager.default.removeItem(at:first.url)
    let (recovered,_,range) = try await clock.source()
    XCTAssertNotEqual(recovered.url,first.url); XCTAssertGreaterThan(range.duration.seconds,0)
    try? FileManager.default.removeItem(at:recovered.url)
  }
  func testCameraFreeCompositionRendersContinuousTimedGraphicsWithoutProjectDependencies() async throws {
    var project = RaceProject(); project.width = 64; project.height = 36; project.fps = 15; project.explicitDuration = 2
    var shape = DisplayObject(name:"Timed color",kind:.shape); shape.x = 0; shape.y = 0; shape.width = 100; shape.height = 100; shape.color = "#FF0000"
    var segment = ObjectSegment(time:1); segment.color = "#00FF00"; shape.segments = [segment]; project.objects = [shape]
    let before = project
    let prepared = try await VideoExporter.prepare(scene:RenderScene(project:project,telemetry:[:]))
    let instruction = try XCTUnwrap(prepared.video.instructions.first as? SceneInstruction)
    XCTAssertTrue(instruction.tracks.isEmpty); XCTAssertEqual(instruction.requiredSourceTrackIDs?.count,1)
    let reader = try AVAssetReader(asset:prepared.composition),tracks = try await prepared.composition.loadTracks(withMediaType:.video)
    XCTAssertEqual(tracks.count,1)
    let output = AVAssetReaderVideoCompositionOutput(videoTracks:tracks,videoSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    output.videoComposition = prepared.video; reader.add(output); XCTAssertTrue(reader.startReading())
    var times:[Double] = []
    while let sample = output.copyNextSampleBuffer(),let buffer = CMSampleBufferGetImageBuffer(sample) {
      let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      CVPixelBufferLockBaseAddress(buffer,.readOnly)
      let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to:UInt8.self)
      let index = 18*CVPixelBufferGetBytesPerRow(buffer)+32*4
      XCTAssertEqual(bytes[index],0); XCTAssertEqual(bytes[index+1],time < 1 ? 0 : 255); XCTAssertEqual(bytes[index+2],time < 1 ? 255 : 0)
      CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
      times.append(time)
    }
    XCTAssertEqual(reader.status,.completed); XCTAssertEqual(times.count,30)
    XCTAssertEqual(times.last ?? 0,29.0/15,accuracy:1e-7)
    XCTAssertEqual(project,before); XCTAssertTrue(project.inputs.isEmpty)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer {try? FileManager.default.removeItem(at:file)}
    try project.save(file); XCTAssertTrue(try RaceProject.read(file).inputs.isEmpty)
    XCTAssertFalse(try String(contentsOf:file).contains("OpenRaceRender-Clock"))
  }
}
