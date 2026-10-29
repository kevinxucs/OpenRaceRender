import AVFoundation
import AppKit
import CoreImage
import Foundation

final class SceneInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
  var timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = true
  let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
  let requiredSourceTrackIDs: [NSValue]?
  let scene: RenderScene
  let tracks: [Int: CMPersistentTrackID]
  let transforms: [Int: CGAffineTransform]
  let options:RenderOptions
  init(
    scene: RenderScene, tracks: [Int: CMPersistentTrackID], transforms: [Int: CGAffineTransform],
    duration: Double, clockTrackID:CMPersistentTrackID? = nil, options:RenderOptions = RenderOptions()
  ) {
    self.scene = scene
    self.options = options
    self.tracks = tracks
    self.transforms = transforms
    self.timeRange = CMTimeRange(
      start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 60000))
    self.requiredSourceTrackIDs = (Array(tracks.values)+(clockTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
  }
}

final class RaceCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
  let queue = DispatchQueue(label: "org.openracerender.compositor")
  let ci = PictureProcessor.context()
  private let cancellationLock = NSLock()
  private var cancellationGeneration:UInt64 = 0
  private func generation() -> UInt64 {cancellationLock.lock();defer {cancellationLock.unlock()};return cancellationGeneration}
  var sourcePixelBufferAttributes: [String: any Sendable]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
  }
  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    // Every request carries its own context. Do not synchronously drain old
    // renders when AVFoundation changes contexts during a seek/resize.
  }
  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    let generation = generation()
    queue.async {
      autoreleasepool {
        guard generation == self.generation() else {request.finishCancelledRequest();return}
        guard let instruction = request.videoCompositionInstruction as? SceneInstruction,
          let output = request.renderContext.newPixelBuffer()
        else {
          request.finish(with: RaceError.invalid("Could not allocate export frame."))
          return
        }
        let outputSize = request.renderContext.size
        let viewport = instruction.options.viewport(project:instruction.scene.project,size:outputSize)
        let size = viewport.size
        let time = request.compositionTime.seconds
        let objects = instruction.scene.project.resolvedObjects(at: time).filter { $0.visible && time >= $0.start && time < $0.end }
        // Most sessions place one camera under all HUD layers. Render that camera
        // directly into the destination surface rather than reading a 4K CGImage
        // back to the CPU and then copying it into another full-size bitmap.
        var baseVideo: UUID?
        if let first = objects.first,first.kind == .video,(first.colorChannels?.bits ?? 7) != 0,
          let placement = instruction.scene.project.media(for:first.inputIndex,at:time),
          let track = instruction.tracks[placement.input.legacyIndex],let frame = request.sourceFrame(byTrackID:track) {
          let image = PictureProcessor.source(frame,settings:placement.input.picture).transformed(by:instruction.transforms[placement.input.legacyIndex] ?? .identity)
          let rect = OverlayRenderer.rect(first,size:size,project:instruction.scene.project).offsetBy(dx:viewport.minX,dy:viewport.minY)
          let layer = PictureProcessor.positioned(image,in:rect,opacity:first.opacity,input:placement.input.picture,object:first.picture,scaling:instruction.options.scaling).cropped(to:viewport)
          let bounds = CGRect(origin:.zero,size:outputSize)
          let background = CIImage(color:CIColor(red:0,green:0,blue:0)).cropped(to:bounds)
          self.ci.render(RGBChannelCompositor.overBlack(layer,mask:first.colorChannels).composited(over:background),to:output,bounds:bounds,colorSpace:OverlayRenderer.colorSpace)
          baseVideo = first.id
        }
        do {
          CVPixelBufferLockBaseAddress(output, [])
          defer { CVPixelBufferUnlockBaseAddress(output, []) }
          guard
            let c = CGContext(
              data: CVPixelBufferGetBaseAddress(output), width: CVPixelBufferGetWidth(output),
              height: CVPixelBufferGetHeight(output), bitsPerComponent: 8,
              bytesPerRow: CVPixelBufferGetBytesPerRow(output), space: OverlayRenderer.colorSpace,
              bitmapInfo: OverlayRenderer.bitmapInfo)
          else {
            request.finish(with: RaceError.invalid("Could not create export canvas."))
            return
          }
          c.interpolationQuality = instruction.options.scaling == .nearest ? .none : instruction.options.scaling == .linear ? .low : .high
          if baseVideo == nil { c.setFillColor(CGColor(gray:0,alpha:1));c.fill(CGRect(origin:.zero,size:outputSize)) }
          c.clip(to:viewport)
          c.translateBy(x:viewport.minX,y:viewport.minY)
          for o in objects where o.id != baseVideo {
            if o.kind == .video, let placement = instruction.scene.project.media(for: o.inputIndex, at: time),
              let track = instruction.tracks[placement.input.legacyIndex],
              let frame = request.sourceFrame(byTrackID: track)
            {
              let image = PictureProcessor.source(frame,settings:placement.input.picture).transformed(
                by: instruction.transforms[placement.input.legacyIndex] ?? .identity)
              RGBChannelCompositor.draw(c,mask:o.colorChannels) {
              PictureProcessor.draw(c, image: image, in: OverlayRenderer.rect(o, size: size,project:instruction.scene.project), opacity: o.opacity, input: placement.input.picture, object: o.picture, context: self.ci)
              }
            } else if o.kind == .image {
              OverlayRenderer.draw(
                c,
                scene: RenderScene(
                  project: Self.single(instruction.scene.project, o),
                  telemetry: instruction.scene.telemetry), time: time, size: size)
            } else if ![.audio, .group].contains(o.kind) {
              OverlayRenderer.draw(
                c,
                scene: RenderScene(
                  project: Self.single(instruction.scene.project, o),
                  telemetry: instruction.scene.telemetry), time: time, size: size)
            }
          }
          c.flush()
        }
        // Finish only after CPU drawing has released its pixel-buffer lock.
        if generation == self.generation() {request.finish(withComposedVideoFrame: output)}
        else {request.finishCancelledRequest()}
      }
    }
  }
  static func single(_ p: RaceProject, _ o: DisplayObject) -> RaceProject {
    var p = p
    var o = o; o.parentID = nil; o.parentIndex = -1; o.segments = nil
    p.objects = [o]
    return p
  }
  static func drawVideo(_ c: CGContext, cg: CGImage, in r: CGRect, opacity: Double) {
    let scale = min(r.width / Double(cg.width), r.height / Double(cg.height))
    let w = Double(cg.width) * scale
    let h = Double(cg.height) * scale
    c.saveGState()
    c.setAlpha(opacity)
    c.clip(to: r)
    c.draw(cg, in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
    c.restoreGState()
  }
  func cancelAllPendingVideoCompositionRequests() {
    cancellationLock.lock();cancellationGeneration &+= 1;cancellationLock.unlock()
  }
}

public final class VideoExporter: @unchecked Sendable {
  public private(set) var session: AVAssetExportSession?
  private let stateLock = NSLock()
  private var reader: AVAssetReader?
  private var writer: AVAssetWriter?
  private var completedProgress: Float = 0
  private var cancelled = false
  private var exporting = false
  public var progress: Float { stateLock.lock();defer { stateLock.unlock() };return completedProgress }
  func setProgress(_ value: Float) { stateLock.lock();completedProgress = max(0,min(1,value));stateLock.unlock() }
  func setPipeline(reader: AVAssetReader?,writer: AVAssetWriter?) {
    stateLock.lock();self.reader = reader;self.writer = writer;stateLock.unlock()
  }
  func checkCancellation() throws {
    stateLock.lock();let value = cancelled;stateLock.unlock()
    if value { throw RaceError.invalid("Export cancelled.") }
  }
  private func beginExport() throws {
    stateLock.lock();defer { stateLock.unlock() }
    guard !exporting else { throw RaceError.invalid("This exporter is already rendering a video.") }
    exporting = true;cancelled = false;completedProgress = 0
  }
  private func endExport() { stateLock.lock();exporting = false;stateLock.unlock() }
  public init() {}
  public func cancel() { stateLock.lock();cancelled = true;stateLock.unlock();session?.cancelExport() }
  public func export(scene: RenderScene, to url: URL, start: Double, duration: Double) async throws
  {
    try beginExport();defer { endExport() }
    let p = scene.project
    let settings = p.exportSettings ?? ExportSettings()
    try settings.validate(project:p)
    guard p.width > 0, p.height > 0,p.width <= 16384,p.height <= 16384,p.fps > 0, p.fps <= 240, p.fps.isFinite, start.isFinite, start >= 0,
      duration.isFinite, duration > 0
    else { throw RaceError.invalid("Invalid export dimensions, frame rate or time range.") }
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw RaceError.invalid("Output already exists. Choose a new filename.")
    }
    try p.validateExportAssets(start: start, duration: min(duration, p.duration - start),telemetry:scene.telemetry)
    let options = try (settings.output ?? OutputSettings()).renderOptions(project:p)
    let prepared = try await Self.prepare(scene: scene,options:options)
    let composition = prepared.composition
    let fullDuration = min(p.duration, composition.duration.seconds)
    guard start < fullDuration else { throw RaceError.invalid("Export start is beyond the project duration.") }
    let range = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 60000),
      duration: CMTime(seconds: min(duration, fullDuration - start), preferredTimescale: 60000))
    try await write(prepared:prepared,project:p,to:url,range:range)
    if settings.sphericalMetadata ?? (p.sphericalWorkspace == true) {
      try checkCancellation();try SphericalMetadata.updateOwnedOutput(url,enabled:true)
    }
  }

  public struct PreparedScene {
    public let composition: AVMutableComposition
    public let video: AVMutableVideoComposition
    public let audio: AVMutableAudioMix
  }
  /// Used by both the editor player and file export, including layers, source changes and picture effects.
  public static func prepare(scene: RenderScene, options:RenderOptions = RenderOptions()) async throws -> PreparedScene {
    let p = scene.project
    try options.validate()
    let size = options.size ?? CGSize(width:p.width,height:p.height),fps = options.fps ?? p.fps
    guard p.width > 0,p.height > 0,p.width <= 16384,p.height <= 16384,p.fps.isFinite,p.fps > 0,p.fps <= 240,
      size.width >= 2,size.height >= 2,size.width <= 7680,size.height <= 4320,fps.isFinite,fps > 0,fps <= 120 else {
      throw RaceError.invalid("Invalid canvas dimensions or frame rate.")
    }
    let composition = AVMutableComposition()
    var tracks: [Int: CMPersistentTrackID] = [:]
    var transforms: [Int: CGAffineTransform] = [:]
    var audioParameters: [AVMutableAudioMixInputParameters] = []
    var clockSource:(AVURLAsset,AVAssetTrack,CMTimeRange)?
    var videoEnd = 0.0
    for placement in p.placements where ["video", "audio"].contains(placement.input.kind) && placement.input.isTimeFiller != true && placement.input.exists && placement.end > placement.start {
      let input = placement.input
      let asset = AVURLAsset(url: URL(fileURLWithPath: input.path))
      let sourceDuration = try await asset.load(.duration).seconds
      let sourceLength = min(sourceDuration - placement.sourceStart, (placement.end-placement.start)*placement.rate)
      guard sourceLength > 0 else { continue }
      let range = CMTimeRange(start: CMTime(seconds: placement.sourceStart, preferredTimescale: 60000), duration: CMTime(seconds: sourceLength, preferredTimescale: 60000))
      let destination = CMTime(seconds: placement.start, preferredTimescale: 60000)
      let inserted = CMTimeRange(start: destination, duration: range.duration)
      let scaled = CMTime(seconds: sourceLength / placement.rate, preferredTimescale: 60000)
      if input.kind == "video" {
        guard let source = try await asset.loadTracks(withMediaType:.video).first else {throw RaceError.invalid("‘\(input.name)’ has no readable video track. Relink or remove that camera input.")}
        guard let track = tracks[input.legacyIndex].flatMap({ composition.track(withTrackID: $0) }) ?? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {throw RaceError.invalid("Cannot allocate a camera video track.")}
        try track.insertTimeRange(range, of: source, at: destination)
        track.scaleTimeRange(inserted, toDuration: scaled)
        tracks[input.legacyIndex] = track.trackID
        transforms[input.legacyIndex] = try await source.load(.preferredTransform)
        videoEnd = max(videoEnd,placement.start+sourceLength/placement.rate)
        if clockSource == nil { clockSource = (asset,source,range) }
      }
      if options.audio != .disabled,let source = try await asset.loadTracks(withMediaType: .audio).first,
        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        let stereo = try await StereoAudioSource.shared.source(asset:asset,track:source,url:URL(fileURLWithPath:input.path),sampleRate:options.audioSampleRate)
        try withExtendedLifetime(stereo.asset) { try track.insertTimeRange(range,of:stereo.track,at:destination) }
        track.scaleTimeRange(inserted, toDuration: scaled)
        let parameter = AVMutableAudioMixInputParameters(track: track)
        // Use the same sample-accurate gate for ordinary and routed audio. Discrete
        // setVolume(at:) points alone can interpolate across a hidden group interval.
        parameter.setVolume(1, at: .zero)
        parameter.audioTapProcessor = try AudioProcessing.tap(project: p, placement: placement,mono:options.audio == .mono,bits:options.audioBits)
        audioParameters.append(parameter)
      }
    }
    var generatedClockID:CMPersistentTrackID?
    if tracks.isEmpty {
      let (asset,source,range) = try await GeneratedVideoClock.shared.source()
      guard let clock = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else {throw RaceError.invalid("Cannot allocate the generated render clock.")}
      let length = min(range.duration.seconds,p.duration)
      let frame = CMTimeRange(start:range.start,duration:CMTime(seconds:length,preferredTimescale:60000))
      try withExtendedLifetime(asset) {
        try clock.insertTimeRange(frame,of:source,at:.zero)
        clock.scaleTimeRange(CMTimeRange(start:.zero,duration:frame.duration),toDuration:CMTime(seconds:p.duration,preferredTimescale:60000))
      }
      generatedClockID = clock.trackID
    }
    // AVAssetReader stops video composition at the last real video sample, even
    // when the composition has an empty tail. A hidden source-frame track at the
    // requested end keeps the compositor clock alive for trailing gaps/overlays.
    var clockTrackID:CMPersistentTrackID? = generatedClockID
    if videoEnd+1e-8 < p.duration, let (asset,source,range) = clockSource,
      let clock = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) {
      let length = min(1/p.fps,range.duration.seconds,p.duration)
      let frame = CMTimeRange(start:range.start,duration:CMTime(seconds:length,preferredTimescale:60000))
      try withExtendedLifetime(asset) {
        try clock.insertTimeRange(frame,of:source,at:CMTime(seconds:p.duration-length,preferredTimescale:60000))
      }
      clockTrackID = clock.trackID
    }
    if composition.duration.seconds < p.duration {
      composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: CMTime(seconds: p.duration-composition.duration.seconds, preferredTimescale: 60000)))
    }
    let vc = AVMutableVideoComposition()
    vc.customVideoCompositorClass = RaceCompositor.self
    vc.instructions = [SceneInstruction(scene: scene, tracks: tracks, transforms: transforms, duration: composition.duration.seconds,clockTrackID:clockTrackID,options:options)]
    vc.renderSize = options.size ?? CGSize(width: p.width, height: p.height)
    vc.frameDuration = CMTime(seconds: 1/(options.fps ?? p.fps), preferredTimescale: 60000)
    let mix = AVMutableAudioMix(); mix.inputParameters = audioParameters
    return PreparedScene(composition: composition, video: vc, audio: mix)
  }

  public static func snapshot(scene: RenderScene, time: Double, to url: URL) throws {
    let p = scene.project
    let size = CGSize(width: p.width, height: p.height)
    guard p.width > 0, p.width <= 16384, p.height > 0, p.height <= 16384, time.isFinite else {
      throw RaceError.invalid("Invalid snapshot settings.")
    }
    try p.validateExportAssets(start: time, duration: max(1e-12, time.nextUp - time),telemetry:scene.telemetry)
    guard
      let c = CGContext(
        data: nil, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: OverlayRenderer.colorSpace,
        bitmapInfo: OverlayRenderer.bitmapInfo)
    else { throw RaceError.invalid("Cannot allocate snapshot canvas.") }
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    c.fill(CGRect(origin: .zero, size: size))
    let ci = PictureProcessor.context()
    for o in p.resolvedObjects(at: time) where o.visible && time >= o.start && time < o.end {
      if o.kind == .video, let placement = p.media(for: o.inputIndex, at: time),
        placement.input.exists && placement.input.isTimeFiller != true
      {
        let input = placement.input
        let sourceTime = placement.sourceTime(at: time)
        if sourceTime >= 0 {
          let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: input.path)))
          gen.appliesPreferredTrackTransform = true
          gen.maximumSize = size
          gen.requestedTimeToleranceBefore = .zero
          gen.requestedTimeToleranceAfter = .zero
          let cg = try gen.copyCGImage(
            at: CMTime(seconds: sourceTime, preferredTimescale: 60000), actualTime: nil)
          RGBChannelCompositor.draw(c,mask:o.colorChannels) {
          PictureProcessor.draw(c, image: PictureProcessor.source(cg,settings:input.picture), in: OverlayRenderer.rect(o, size: size,project:scene.project), opacity: o.opacity, input: input.picture, object: o.picture, context: ci)
          }
        }
      } else if ![.audio, .group].contains(o.kind) {
        OverlayRenderer.draw(
          c, scene: RenderScene(project: RaceCompositor.single(p, o), telemetry: scene.telemetry),
          time: time, size: size)
      }
    }
    guard let cg = c.makeImage() else { throw RaceError.invalid("Cannot create snapshot image.") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw RaceError.invalid("Cannot encode PNG.")
    }
    try png.write(to: url, options: .atomic)
  }
}
