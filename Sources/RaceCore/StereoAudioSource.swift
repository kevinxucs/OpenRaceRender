import AVFoundation
import CryptoKit

/// Older audio taps retain a mono track's channel count. Normalize its backing
/// track once so both preview and export can apply a genuine stereo matrix.
actor StereoAudioSource {
  static let shared = StereoAudioSource()
  private var pending:[String:Task<URL,Error>] = [:]
  private let root:URL
  init(root:URL? = nil) {
    self.root = root ?? ProcessInfo.processInfo.environment["OPENRACERENDER_AUDIO_CACHE"].map{URL(fileURLWithPath:$0,isDirectory:true)}
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/OpenRaceRender/StereoAudio")
  }
  func source(asset:AVURLAsset,track:AVAssetTrack,url:URL,sampleRate:Int = 0,retry:Bool = true) async throws -> (asset:AVURLAsset,track:AVAssetTrack) {
    let descriptions = try await track.load(.formatDescriptions)
    guard let description = descriptions.first,let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { throw RaceError.invalid("Cannot read the source audio format.") }
    let isPCM = format.mFormatID == kAudioFormatLinearPCM
    let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
    let nativeBits = floating ? [32,64].contains(format.mBitsPerChannel) : signed && [16,32].contains(format.mBitsPerChannel)
    let nativeEndian = format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
    let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
    let packed = format.mBytesPerFrame == (format.mBitsPerChannel/8)*(planar ? 1 : format.mChannelsPerFrame)
    let rate = sampleRate == 0 ? format.mSampleRate : Double(sampleRate)
    if format.mChannelsPerFrame == 2,abs(rate-format.mSampleRate) < 0.5,(!isPCM || (nativeBits && nativeEndian && packed)) { return (asset,track) }
    let info = try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
    let key = "v2|\(url.standardizedFileURL.path)|\(info.fileSize ?? 0)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(track.trackID)|\(rate)"
    let hash = SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined()
    let target = root.appendingPathComponent(hash+".caf")
    let task:Task<URL,Error>
    if let existing = pending[key] { task = existing }
    else {
      task = Task.detached { [root] in
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:target.path) {
          let cached = AVURLAsset(url:target)
          if let audio = try? await cached.loadTracks(withMediaType:.audio).first,
            let formats = try? await audio.load(.formatDescriptions),let first = formats.first,
            let cachedFormat = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee,
            cachedFormat.mChannelsPerFrame == 2,abs(cachedFormat.mSampleRate-rate) < 0.5 { return target }
          try? FileManager.default.removeItem(at:target)
        }
        try await Self.convert(asset:asset,track:track,to:target,sampleRate:rate)
        return target
      }
      pending[key] = task
    }
    do {
      let converted = try await task.value
      let normalized = AVURLAsset(url:converted)
      let size = (try? converted.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
      if size > 0,
        let audio = try? await normalized.loadTracks(withMediaType:.audio).first,
        let descriptions = try? await audio.load(.formatDescriptions),let first = descriptions.first,
        let cachedFormat = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee,
        cachedFormat.mChannelsPerFrame == 2,abs(cachedFormat.mSampleRate-rate) < 0.5 { return (normalized,audio) }
      if retry {
        pending[key] = nil; try? FileManager.default.removeItem(at:converted)
        return try await source(asset:asset,track:track,url:url,sampleRate:sampleRate,retry:false)
      }
      throw RaceError.invalid("The normalized stereo audio has no readable track.")
    } catch { pending[key] = nil; throw error }
  }
  private nonisolated static func convert(asset:AVURLAsset,track:AVAssetTrack,to target:URL,sampleRate:Double) async throws {
    let temporary = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".partial.caf")
    defer {try? FileManager.default.removeItem(at:temporary)}
    let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48000
    let settings:[String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:2,
      AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false]
    let reader = try AVAssetReader(asset:asset),writer = try AVAssetWriter(outputURL:temporary,fileType:.caf)
    let output = AVAssetReaderTrackOutput(track:track,outputSettings:settings)
    let input = AVAssetWriterInput(mediaType:.audio,outputSettings:settings)
    input.expectsMediaDataInRealTime = false; output.alwaysCopiesSampleData = false
    guard reader.canAdd(output),writer.canAdd(input) else { throw RaceError.invalid("Cannot normalize this audio source to stereo PCM.") }
    reader.add(output); writer.add(input)
    guard reader.startReading(),writer.startWriting() else { throw RaceError.invalid(reader.error?.localizedDescription ?? writer.error?.localizedDescription ?? "Cannot prepare stereo audio.") }
    writer.startSession(atSourceTime:.zero)
    do {
      while let sample = output.copyNextSampleBuffer() {
        try Task.checkCancellation()
        while !input.isReadyForMoreMediaData {
          guard writer.status == .writing else { throw RaceError.invalid(writer.error?.localizedDescription ?? "Stereo audio conversion stopped.") }
          try await Task.sleep(nanoseconds:1_000_000)
        }
        guard input.append(sample) else { throw RaceError.invalid(writer.error?.localizedDescription ?? "Cannot write stereo audio samples.") }
      }
      guard reader.status == .completed else { throw RaceError.invalid(reader.error?.localizedDescription ?? "Cannot decode this audio source.") }
      input.markAsFinished(); await writer.finishWriting()
      guard writer.status == .completed else { throw RaceError.invalid(writer.error?.localizedDescription ?? "Cannot finish stereo audio.") }
      do { try FileManager.default.moveItem(at:temporary,to:target) }
      catch { if !FileManager.default.fileExists(atPath:target.path) { throw error } }
    } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
  }
}
