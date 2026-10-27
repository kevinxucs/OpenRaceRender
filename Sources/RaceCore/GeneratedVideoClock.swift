import AVFoundation

/// A tiny original black clip supplies sample timing only. Its pixels are never
/// drawn by the scene compositor and it is never a saved project dependency.
actor GeneratedVideoClock {
  static let shared = GeneratedVideoClock()
  private var pending:Task<URL,Error>?
  func source(retry:Bool = true) async throws -> (AVURLAsset,AVAssetTrack,CMTimeRange) {
    let task:Task<URL,Error>
    if let pending {task = pending}
    else {
      task = Task.detached {try await Self.create()}; pending = task
    }
    do {
      let url = try await task.value
      let asset = AVURLAsset(url:url)
      guard FileManager.default.fileExists(atPath:url.path),let track = try await asset.loadTracks(withMediaType:.video).first else { throw RaceError.invalid("Generated render clock is unavailable.") }
      let range = try await track.load(.timeRange)
      guard range.duration.seconds > 0 else {throw RaceError.invalid("Generated render clock is empty.")}
      return (asset,track,range)
    } catch {
      pending = nil
      if retry {return try await source(retry:false)}
      throw error
    }
  }
  private nonisolated static func create() async throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenRaceRender-Clock",isDirectory:true)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let file = root.appendingPathComponent(UUID().uuidString+".mov")
    let writer = try AVAssetWriter(outputURL:file,fileType:.mov)
    let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:32,AVVideoHeightKey:32])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:32,kCVPixelBufferHeightKey as String:32])
    guard writer.canAdd(input) else {throw RaceError.invalid("Cannot create the internal video clock.")}
    writer.add(input)
    guard writer.startWriting() else {throw writer.error ?? RaceError.invalid("Cannot start the internal video clock.")}
    writer.startSession(atSourceTime:.zero)
    do {
      for frame in 0..<2 {
        for _ in 0..<500 where !input.isReadyForMoreMediaData {try await Task.sleep(nanoseconds:2_000_000)}
        guard input.isReadyForMoreMediaData,let pool = adaptor.pixelBufferPool else {throw RaceError.invalid("Internal video clock encoder timed out.")}
        var buffer:CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess,let buffer else {throw RaceError.invalid("Cannot allocate the internal video clock.")}
        CVPixelBufferLockBaseAddress(buffer,[])
        if let base = CVPixelBufferGetBaseAddress(buffer) {memset(base,0,CVPixelBufferGetDataSize(buffer))}
        CVPixelBufferUnlockBaseAddress(buffer,[])
        guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:30)) else {throw writer.error ?? RaceError.invalid("Cannot write the internal video clock.")}
      }
      writer.endSession(atSourceTime:CMTime(value:2,timescale:30)); input.markAsFinished(); await writer.finishWriting()
      guard writer.status == .completed else {throw writer.error ?? RaceError.invalid("Cannot finish the internal video clock.")}
      return file
    } catch {writer.cancelWriting();try? FileManager.default.removeItem(at:file);throw error}
  }
}
