import AVFoundation
import XCTest
@testable import RaceCore

final class PreviewMediaTests:XCTestCase {
  func movie(_ url:URL) async throws {
    let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
    let settings:[String:Any] = [AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:36]
    let input = AVAssetWriterInput(mediaType:.video,outputSettings:settings)
    let attributes:[String:Any] = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:36]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:attributes)
    writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime:.zero)
    for frame in 0..<12 {
      for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:10_000_000) }
      guard input.isReadyForMoreMediaData else { throw RaceError.invalid("Synthetic writer timed out.") }
      var pixel:CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,try XCTUnwrap(adaptor.pixelBufferPool),&pixel),kCVReturnSuccess)
      let buffer = try XCTUnwrap(pixel); CVPixelBufferLockBaseAddress(buffer,[])
      let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to:UInt8.self)
      let row = CVPixelBufferGetBytesPerRow(buffer)
      for y in 0..<36 { for x in 0..<64 {
        let i = y*row+x*4; bytes[i] = 0; bytes[i+1] = frame >= 6 ? 255 : 0; bytes[i+2] = frame < 6 ? 255 : 0; bytes[i+3] = 255
      } }
      CVPixelBufferUnlockBaseAddress(buffer,[])
      XCTAssertTrue(adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:60)))
    }
    writer.endSession(atSourceTime:CMTime(value:12,timescale:60)); input.markAsFinished(); await writer.finishWriting()
    XCTAssertEqual(writer.status,.completed)
  }
  func audio(_ url:URL) throws {
    let frames = 8820
    var bytes = Data("RIFF".utf8)
    func u16(_ value:UInt16) { var value = value.littleEndian; withUnsafeBytes(of:&value){bytes.append(contentsOf:$0)} }
    func u32(_ value:UInt32) { var value = value.littleEndian; withUnsafeBytes(of:&value){bytes.append(contentsOf:$0)} }
    u32(UInt32(36+frames*4)); bytes.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(2); u32(44100); u32(176400); u16(4); u16(16)
    bytes.append(Data("data".utf8)); u32(UInt32(frames*4))
    for _ in 0..<frames {u16(3276);u16(9830)}
    try bytes.write(to:url)
  }
  func testPreparedPreviewRendersAtIndependentSizeAndCadenceWithoutChangingSceneClock() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("camera.mov"); try await movie(file)
    var project = RaceProject(); project.width = 640; project.height = 360; project.fps = 60; project.explicitDuration = 0.2
    var source = MediaInput(name:"Original synthetic camera",path:file.path,kind:"video",legacyIndex:0); source.duration = 0.2
    var camera = DisplayObject(name:"Camera",kind:.video); camera.inputIndex = 0; camera.x = 0; camera.y = 0; camera.width = 100; camera.height = 100
    var shape = DisplayObject(name:"Original blue overlay",kind:.shape); shape.x = 75; shape.y = 0; shape.width = 25; shape.height = 25; shape.color = "#0000FF"
    project.inputs = [source]; project.objects = [camera,shape]
    let before = project; var settings = PreviewSettings(); settings.height = 180; settings.fps = 15; settings.scaling = .nearest
    let scene = RenderScene(project:project,telemetry:[:])
    let prepared = try await VideoExporter.prepare(scene:scene,options:settings.options(for:project))
    XCTAssertEqual(prepared.video.renderSize,CGSize(width:320,height:180)); XCTAssertEqual(prepared.video.frameDuration.seconds,1.0/15,accuracy:1e-8)
    let instruction = try XCTUnwrap(prepared.video.instructions.first as? SceneInstruction)
    XCTAssertEqual(instruction.scene.project,before); XCTAssertEqual(instruction.scene.project.fps,60)
    let reader = try AVAssetReader(asset:prepared.composition)
    let tracks = try await prepared.composition.loadTracks(withMediaType:.video)
    let output = AVAssetReaderVideoCompositionOutput(videoTracks:tracks,videoSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    output.videoComposition = prepared.video; reader.add(output); XCTAssertTrue(reader.startReading())
    var times:[Double] = [],centers:[[UInt8]] = []; var blueCount = 0
    while let sample = output.copyNextSampleBuffer(),let image = CMSampleBufferGetImageBuffer(sample) {
      XCTAssertEqual(CVPixelBufferGetWidth(image),320); XCTAssertEqual(CVPixelBufferGetHeight(image),180)
      CVPixelBufferLockBaseAddress(image,.readOnly)
      let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to:UInt8.self),row = CVPixelBufferGetBytesPerRow(image)
      let index = 90*row+160*4
      centers.append([bytes[index],bytes[index+1],bytes[index+2]])
      if times.isEmpty {
        for y in 0..<180 {for x in 0..<320 {let i = y*row+x*4; if bytes[i] > 240 && bytes[i+1] < 10 && bytes[i+2] < 10 {blueCount += 1}}}
      }
      CVPixelBufferUnlockBaseAddress(image,.readOnly)
      times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
    }
    XCTAssertEqual(reader.status,.completed); XCTAssertEqual(times.count,3)
    guard centers.count == 3 else { return }
    // These are lossy camera color markers, not exact RGB references; host YUV
    // decoding can shift saturated channels. The vector overlay below is exact.
    XCTAssertGreaterThan(centers[0][2],200); XCTAssertLessThan(centers[0][1],50)
    XCTAssertGreaterThan(centers[2][1],200); XCTAssertLessThan(centers[2][2],50)
    XCTAssertEqual(times[1]-times[0],1.0/15,accuracy:1e-6); XCTAssertEqual(blueCount,80*45)
    XCTAssertEqual(project,before)
    let full = try await VideoExporter.prepare(scene:scene)
    XCTAssertEqual(full.video.renderSize,CGSize(width:640,height:360)); XCTAssertEqual(full.video.frameDuration.seconds,1.0/60,accuracy:1e-8)
  }
  func testPreviewMonoAndEightBitAudioAreAudibleMixProcessingAndDisabledSkipsTracks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    let video = root.appendingPathComponent("camera.mov"),wav = root.appendingPathComponent("audio.wav")
    try await movie(video); try audio(wav)
    var p = RaceProject()
    var camera = MediaInput(name:"Camera",path:video.path,kind:"video",legacyIndex:0); camera.duration = 0.2
    var audio = MediaInput(name:"Audio",path:wav.path,kind:"audio",legacyIndex:1); audio.duration = 0.2
    var display = DisplayObject(name:"Sound",kind:.audio); display.inputIndex = 1; p.inputs = [camera,audio]; p.objects = [display]
    var options = RenderOptions(); options.audio = .mono; options.audioBits = 8; options.audioSampleRate = 22050
    let scene = RenderScene(project:p,telemetry:[:]),prepared = try await VideoExporter.prepare(scene:RenderScene(project:p,telemetry:[:]),options:options)
    let reader = try AVAssetReader(asset:prepared.composition),tracks = try await prepared.composition.loadTracks(withMediaType:.audio)
    XCTAssertEqual(tracks.count,1)
    let format:[String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:22050,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false]
    let output = AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:format); output.audioMix = prepared.audio; reader.add(output); XCTAssertTrue(reader.startReading())
    var values:[Float] = []
    while let sample = output.copyNextSampleBuffer(),let block = CMSampleBufferGetDataBuffer(sample) {
      let size = CMBlockBufferGetDataLength(block); var bytes = [Float](repeating:0,count:size/4)
      let result = bytes.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:size,destination:$0.baseAddress!)}
      XCTAssertEqual(result,kCMBlockBufferNoErr); values += bytes
    }
    XCTAssertEqual(reader.status,.completed); XCTAssertGreaterThan(values.count,4000)
    var quantizationError:Float = 0,channelError:Float = 0
    if values.count > 4000 {for i in stride(from:1000,to:2000,by:2) {
      quantizationError = max(quantizationError,abs(values[i]-26.0/128))
      channelError = max(channelError,abs(values[i]-values[i+1]))
    }}
    XCTAssertLessThan(quantizationError,0.0001); XCTAssertLessThan(channelError,0.0001)
    options.audio = .disabled
    let silent = try await VideoExporter.prepare(scene:scene,options:options)
    let silentTracks = try await silent.composition.loadTracks(withMediaType:.audio)
    XCTAssertTrue(silentTracks.isEmpty); XCTAssertTrue(silent.audio.inputParameters.isEmpty)
  }
}
