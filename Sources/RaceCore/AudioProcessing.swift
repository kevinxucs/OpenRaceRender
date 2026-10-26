import AVFoundation
import MediaToolbox

struct StereoMatrix: Equatable {
  var ll: Double = 0, lr: Double = 0, rl: Double = 0, rr: Double = 0
  func apply(_ left: Double, _ right: Double) -> (Double, Double) { (left * ll + right * lr, left * rl + right * rr) }
  static func make(source: MediaInput, displays: [DisplayObject]) -> StereoMatrix {
    let settings = source.audio ?? AudioSettings()
    let balance = settings.balance.isFinite ? max(-1, min(1, settings.balance)) : 0
    let sourceLeft = min(1, 1 - balance), sourceRight = min(1, 1 + balance)
    var left = 0.0, right = 0.0
    for display in displays {
      let audio = display.audio ?? AudioSettings()
      let pan = audio.balance.isFinite ? max(-1, min(1, audio.balance)) : 0
      let gain = audio.volume.isFinite ? max(0, min(2, audio.volume)) : 1
      left += gain * min(1, 1 - pan); right += gain * min(1, 1 + pan)
    }
    let volume = source.volume.isFinite ? max(0, min(2, source.volume)) : 1
    left *= sourceLeft * volume; right *= sourceRight * volume
    switch settings.routing {
    case .stereo: return StereoMatrix(ll: left, rr: right)
    case .swap: return StereoMatrix(lr: left, rl: right)
    case .left: return StereoMatrix(ll: left, rl: right)
    case .right: return StereoMatrix(lr: left, rr: right)
    case .mono: return StereoMatrix(ll: left / 2, lr: left / 2, rl: right / 2, rr: right / 2)
    }
  }
}

private final class AudioTapState {
  struct Span { var time: Double; var matrix: StereoMatrix }
  let spans: [Span]
  var format = AudioStreamBasicDescription()
  init(project: RaceProject, placement: InputPlacement) {
    let objects = project.objects.filter { [.video, .audio].contains($0.kind) }
    let boundaries = Set([0, placement.start, placement.end] + objects.flatMap { [$0.start, $0.end] + ($0.segments ?? []).map(\.time) }).sorted()
    spans = boundaries.map { time in
      let displays = objects.map { $0.resolved(at: time) }.filter {
        $0.visible && time >= $0.start && time < $0.end && $0.inputIndex == placement.rootIndex && placement.contains(time)
      }
      return Span(time: time, matrix: StereoMatrix.make(source: placement.input, displays: displays))
    }
  }
  func matrix(at time: Double) -> StereoMatrix {
    var low = 0, high = spans.count
    while low < high { let middle = (low + high) / 2; if spans[middle].time <= time { low = middle + 1 } else { high = middle } }
    return low > 0 ? spans[low - 1].matrix : StereoMatrix()
  }
  func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, range: CMTimeRange) {
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let channels = Int(format.mChannelsPerFrame)
    guard channels > 0, !buffers.isEmpty, frames > 0 else { return }
    let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
    let bits = Int(format.mBitsPerChannel), bytes = bits / 8
    guard bytes > 0, bits == 16 || bits == 32 || (floating && bits == 64) else { return }
    func address(_ frame: Int, _ channel: Int) -> UnsafeMutableRawPointer? {
      let buffer = planar ? channel : 0
      guard buffer < buffers.count, let base = buffers[buffer].mData else { return nil }
      let index = planar ? frame : frame * channels + channel
      guard index * bytes + bytes <= Int(buffers[buffer].mDataByteSize) else { return nil }
      return base.advanced(by: index * bytes)
    }
    func read(_ p: UnsafeMutableRawPointer?) -> Double {
      guard let p else { return 0 }
      if floating { return bits == 64 ? p.load(as: Double.self) : Double(p.load(as: Float.self)) }
      return bits == 16 ? Double(p.load(as: Int16.self)) / 32768 : Double(p.load(as: Int32.self)) / 2147483648
    }
    func write(_ p: UnsafeMutableRawPointer?, _ value: Double) {
      guard let p else { return }
      let value = value.isFinite ? max(-1, min(1, value)) : 0
      if floating {
        if bits == 64 { p.storeBytes(of: value, as: Double.self) } else { p.storeBytes(of: Float(value), as: Float.self) }
      } else if bits == 16 { p.storeBytes(of: Int16(max(-32768, min(32767, value * 32768))), as: Int16.self) }
      else { p.storeBytes(of: Int32(max(-2147483648, min(2147483647, value * 2147483648))), as: Int32.self) }
    }
    let start = range.start.seconds.isFinite ? range.start.seconds : 0
    let step = range.duration.seconds.isFinite && range.duration.seconds > 0 ? range.duration.seconds / Double(frames) : 1 / max(1, format.mSampleRate)
    for frame in 0..<frames {
      let l = address(frame, 0), r = address(frame, min(1, channels - 1))
      let result = matrix(at: start + Double(frame) * step).apply(read(l), read(r))
      if channels == 1 { write(l, (result.0 + result.1) / 2) }
      else { write(l, result.0); write(r, result.1) }
    }
  }
}

enum AudioProcessing {
  static func tap(project: RaceProject, placement: InputPlacement) throws -> MTAudioProcessingTap {
    let context = Unmanaged.passRetained(AudioTapState(project: project, placement: placement)).toOpaque()
    var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: context,
      init: { _, info, storage in storage.pointee = info },
      finalize: { tap in Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
      prepare: { tap, _, format in Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().format = format.pointee },
      unprepare: nil,
      process: { tap, frames, _, buffers, outputFrames, flags in
        var range = CMTimeRange.zero
        let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, &range, outputFrames)
        guard status == noErr else { outputFrames.pointee = 0; return }
        Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(buffers, frames: outputFrames.pointee, range: range)
      })
    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
    guard status == noErr, let tap else {
      Unmanaged<AudioTapState>.fromOpaque(context).release()
      throw RaceError.invalid("Could not configure imported audio routing (\(status)).")
    }
    return tap
  }
}
