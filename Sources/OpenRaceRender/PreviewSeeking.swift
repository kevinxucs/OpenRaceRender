import AVFoundation
import RaceCore

/// AVPlayer must finish one seek before starting the newest requested frame.
/// Scrubbing replaces the pending target rather than piling up cancelled seeks.
@MainActor final class PreviewSeekController {
  typealias Seek = (Double,@escaping @MainActor (Bool)->Void)->Void
  private let seek:Seek
  private let settled:(Bool,Double)->Void
  private var generation = UUID()
  private var active:Double?
  private var desired:Double?
  var isSeeking:Bool {active != nil}
  init(seek:@escaping Seek,settled:@escaping (Bool,Double)->Void) {self.seek = seek;self.settled = settled}
  func request(_ time:Double) {
    guard time.isFinite else {return}
    if let active {desired = abs(active-time) < 0.000001 ? nil : time;return}
    start(time)
  }
  func invalidate() {generation = UUID();active = nil;desired = nil}
  private func start(_ time:Double) {
    active = time;let token = generation
    seek(time) { [weak self] success in
      guard let self,self.generation == token else {return}
      self.active = nil
      if let next = self.desired {self.desired = nil;self.start(next)}
      else {self.settled(success,time)}
    }
  }
}

/// Readiness alone does not guarantee a picture from a custom compositor.
/// Prime a replacement offscreen while the existing player stays visible.
@MainActor enum PreviewFramePreparation {
  private final class Completion {var value:Bool?}
  static func prime(_ player:AVPlayer,at time:Double) async throws {
    guard let item = player.currentItem else {throw RaceError.invalid("Preview has no media item.")}
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    item.add(output)
    defer {item.remove(output)}
    let deadline = Date().addingTimeInterval(15)
    do {
      while item.status != .readyToPlay {
        try Task.checkCancellation()
        if item.status == .failed {throw item.error ?? RaceError.invalid("Preview media could not be loaded.")}
        guard Date() < deadline else {throw RaceError.invalid("Timed out loading preview media.")}
        try await Task.sleep(nanoseconds:10_000_000)
      }
      let target = CMTime(seconds:time,preferredTimescale:60000),completion = Completion()
      player.seek(to:target,toleranceBefore:.zero,toleranceAfter:.zero) {success in
        Task {@MainActor in completion.value = success}
      }
      while true {
        try Task.checkCancellation()
        if completion.value == false {throw RaceError.invalid("Preview frame seek was interrupted.")}
        if completion.value == true,output.copyPixelBuffer(forItemTime:target,itemTimeForDisplay:nil) != nil {return}
        if item.status == .failed {throw item.error ?? RaceError.invalid("Preview frame rendering failed.")}
        guard Date() < deadline else {throw RaceError.invalid("Timed out rendering the preview frame.")}
        try await Task.sleep(nanoseconds:10_000_000)
      }
    } catch {player.pause();item.cancelPendingSeeks();throw error}
  }
}
