import AVFoundation
import VideoToolbox

public struct ExportSettings: Codable, Equatable, Sendable {
  /// Bits per second. Nil selects a quality-oriented rate for the canvas and frame rate.
  public var videoBitRate: Int?
  public var audioBitRate: Int = 240_000
  public var output:OutputSettings?
  public var profileID:String?
  public var sphericalMetadata:Bool?
  public init(videoBitRate: Int? = nil, audioBitRate: Int = 240_000) {
    self.videoBitRate = videoBitRate; self.audioBitRate = audioBitRate
  }
  public func resolvedVideoBitRate(width: Int, height: Int, fps: Double) -> Int {
    videoBitRate ?? Int(max(2_000_000, min(120_000_000, Double(width)*Double(height)*fps*0.2)))
  }
  func videoSettings(project p: RaceProject) -> [String: Any] {
    let width = output?.width ?? p.width,height = output?.height ?? p.height,fps = output?.fps ?? p.fps
    return [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
      AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true],
      AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: resolvedVideoBitRate(width:width,height:height,fps:fps),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalDurationKey: 2.0]]
  }
  public func validate(project:RaceProject) throws {
    let value = output ?? OutputSettings(); try value.validate(project:project)
    let size = value.size(for:project),fps = value.fps ?? project.fps
    if sphericalMetadata ?? (project.sphericalWorkspace == true) {
      guard size.width == size.height*2,value.border == 0 else {throw RaceError.invalid("Spherical output requires a 2:1 frame and no border. Choose an equirectangular output size.")}
    }
    let rate = resolvedVideoBitRate(width:Int(size.width),height:Int(size.height),fps:fps)
    guard (100_000...240_000_000).contains(rate),(64_000...320_000).contains(audioBitRate) else { throw RaceError.invalid("Video bitrate must be 100–240000 kbps; audio bitrate must be 64–320 kbps.") }
  }
}

/// Independent audio/video pumps keep the decoder, compositor and hardware encoder busy.
/// Readiness waits suspend the task, and cancellation is checked even under backpressure.
extension VideoExporter {
  func write(prepared: PreparedScene, project: RaceProject, to url: URL, range: CMTimeRange) async throws {
    let settings = project.exportSettings ?? ExportSettings()
    try settings.validate(project:project)
    let audio = settings.output ?? OutputSettings()
    let reader = try AVAssetReader(asset: prepared.composition)
    reader.timeRange = range
    let writer = try AVAssetWriter(outputURL:url,fileType:.mp4)
    writer.shouldOptimizeForNetworkUse = true
    let videoOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks:prepared.composition.tracks(withMediaType:.video),
      videoSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    videoOutput.videoComposition = prepared.video
    videoOutput.alwaysCopiesSampleData = false
    let videoInput = AVAssetWriterInput(mediaType:.video,outputSettings:settings.videoSettings(project:project))
    videoInput.mediaTimeScale = 60_000
    videoInput.expectsMediaDataInRealTime = false
    guard reader.canAdd(videoOutput),writer.canAdd(videoInput) else { throw RaceError.invalid("Unsupported video export settings.") }
    reader.add(videoOutput); writer.add(videoInput)
    var streams: [(AVAssetReaderOutput,AVAssetWriterInput)] = [(videoOutput,videoInput)]
    let tracks = prepared.composition.tracks(withMediaType:.audio)
    if !tracks.isEmpty,audio.audioChannels != 0 {
      let output = AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[
        AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:audio.audioSampleRate,AVNumberOfChannelsKey:audio.audioChannels,
        AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsNonInterleaved:false])
      output.audioMix = prepared.audio; output.alwaysCopiesSampleData = false
      let input = AVAssetWriterInput(mediaType:.audio,outputSettings:[
        AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:audio.audioSampleRate,AVNumberOfChannelsKey:audio.audioChannels,AVEncoderBitRateKey:settings.audioBitRate])
      guard reader.canAdd(output),writer.canAdd(input) else { throw RaceError.invalid("Unsupported audio export settings.") }
      reader.add(output);writer.add(input);streams.append((output,input))
    }
    setPipeline(reader:reader,writer:writer)
    defer { setPipeline(reader:nil,writer:nil) }
    do {
      try checkCancellation()
      guard writer.startWriting(),reader.startReading() else { throw writer.error ?? reader.error ?? RaceError.invalid("Could not start video export.") }
      writer.startSession(atSourceTime:range.start)
      try await withThrowingTaskGroup(of:Void.self) { group in
        for (output,input) in streams {
          group.addTask {
            while true {
              try Task.checkCancellation();try self.checkCancellation()
              if reader.status == .failed { throw reader.error ?? RaceError.invalid("Could not decode media.") }
              if writer.status == .failed { throw writer.error ?? RaceError.invalid("Could not encode media.") }
              guard input.isReadyForMoreMediaData else {
                try await Task.sleep(nanoseconds:2_000_000);continue
              }
              let finished: Bool = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return true }
                guard input.append(sample) else { throw writer.error ?? reader.error ?? RaceError.invalid("Could not append export frame.") }
                if input.mediaType == .video {
                  self.setProgress(Float((CMSampleBufferGetPresentationTimeStamp(sample)-range.start).seconds/range.duration.seconds))
                }
                return false
              }
              if finished { input.markAsFinished();break }
            }
          }
        }
        try await group.waitForAll()
      }
      try checkCancellation()
      if reader.status == .failed { throw reader.error ?? RaceError.invalid("Could not decode media.") }
      writer.endSession(atSourceTime:range.end)
      await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in writer.finishWriting { c.resume() } }
      try checkCancellation()
      guard writer.status == .completed else { throw writer.error ?? RaceError.invalid("Video export failed.") }
      setProgress(1)
    } catch {
      reader.cancelReading();writer.cancelWriting();try? FileManager.default.removeItem(at:url);throw error
    }
  }
}
