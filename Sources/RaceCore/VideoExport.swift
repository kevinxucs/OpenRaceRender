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
  init(
    scene: RenderScene, tracks: [Int: CMPersistentTrackID], transforms: [Int: CGAffineTransform],
    duration: Double
  ) {
    self.scene = scene
    self.tracks = tracks
    self.transforms = transforms
    self.timeRange = CMTimeRange(
      start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 60000))
    self.requiredSourceTrackIDs = tracks.values.map { NSNumber(value: $0) }
  }
}

final class RaceCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
  let queue = DispatchQueue(label: "org.openracerender.compositor")
  let ci = CIContext(options: [.cacheIntermediates: false])
  var renderContext: AVVideoCompositionRenderContext?
  var sourcePixelBufferAttributes: [String: any Sendable]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
  }
  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    queue.sync { renderContext = newRenderContext }
  }
  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    queue.async {
      autoreleasepool {
        guard let instruction = request.videoCompositionInstruction as? SceneInstruction,
          let output = request.renderContext.newPixelBuffer()
        else {
          request.finish(with: RaceError.invalid("Could not allocate export frame."))
          return
        }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        let size = request.renderContext.size
        guard
          let c = CGContext(
            data: CVPixelBufferGetBaseAddress(output), width: CVPixelBufferGetWidth(output),
            height: CVPixelBufferGetHeight(output), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(output), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
              | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else {
          request.finish(with: RaceError.invalid("Could not create export canvas."))
          return
        }
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        c.fill(CGRect(origin: .zero, size: size))
        let time = request.compositionTime.seconds
        for o in instruction.scene.project.objects.map({ $0.resolved(at: time) })
        where o.visible && time >= o.start && time <= o.end {
          if o.kind == .video, let placement = instruction.scene.project.media(for: o.inputIndex, at: time),
            let track = instruction.tracks[placement.input.legacyIndex],
            let frame = request.sourceFrame(byTrackID: track)
          {
            let image = CIImage(cvPixelBuffer: frame).transformed(
              by: instruction.transforms[placement.input.legacyIndex] ?? .identity)
            PictureProcessor.draw(c, image: image, in: OverlayRenderer.rect(o, size: size), opacity: o.opacity, input: placement.input.picture, object: o.picture, context: self.ci)
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
        request.finish(withComposedVideoFrame: output)
      }
    }
  }
  static func single(_ p: RaceProject, _ o: DisplayObject) -> RaceProject {
    var p = p
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
  func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
}

public final class VideoExporter: @unchecked Sendable {
  public private(set) var session: AVAssetExportSession?
  public var progress: Float { session?.progress ?? 0 }
  public init() {}
  public func cancel() { session?.cancelExport() }
  public func export(scene: RenderScene, to url: URL, start: Double, duration: Double) async throws
  {
    let p = scene.project
    guard p.width > 0, p.height > 0, p.width <= 7680, p.height <= 4320, p.width % 2 == 0,
      p.height % 2 == 0, p.fps > 0, p.fps <= 120, p.fps.isFinite, start.isFinite, start >= 0,
      duration.isFinite, duration > 0
    else { throw RaceError.invalid("Invalid export dimensions, frame rate or time range.") }
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw RaceError.invalid("Output already exists. Choose a new filename.")
    }
    let prepared = try await Self.prepare(scene: scene)
    let composition = prepared.composition
    let fullDuration = min(p.duration, composition.duration.seconds)
    guard start < fullDuration else { throw RaceError.invalid("Export start is beyond the project duration.") }
    let preset =
      p.width > 1920 || p.height > 1080
      ? AVAssetExportPreset3840x2160 : AVAssetExportPreset1920x1080
    guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
      throw RaceError.invalid("Could not create H.264 export session.")
    }
    session = export
    export.videoComposition = prepared.video
    export.outputURL = url
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.timeRange = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 60000),
      duration: CMTime(seconds: min(duration, fullDuration - start), preferredTimescale: 60000))
    export.audioMix = prepared.audio
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { continuation.resume() }
    }
    guard export.status == .completed else {
      try? FileManager.default.removeItem(at: url)
      throw export.error
        ?? RaceError.invalid(
          export.status == .cancelled ? "Export cancelled." : "Video export failed.")
    }
  }

  public struct PreparedScene {
    public let composition: AVMutableComposition
    public let video: AVMutableVideoComposition
    public let audio: AVMutableAudioMix
  }
  /// Used by both the editor player and file export, including layers, source changes and picture effects.
  public static func prepare(scene: RenderScene) async throws -> PreparedScene {
    let p = scene.project
    guard p.width > 0, p.height > 0, p.width <= 7680, p.height <= 4320, p.fps.isFinite, p.fps > 0, p.fps <= 120 else {
      throw RaceError.invalid("Invalid canvas dimensions or frame rate.")
    }
    let composition = AVMutableComposition()
    var tracks: [Int: CMPersistentTrackID] = [:]
    var transforms: [Int: CGAffineTransform] = [:]
    var audioParameters: [AVMutableAudioMixInputParameters] = []
    for placement in p.placements where ["video", "audio"].contains(placement.input.kind) && placement.input.exists && placement.end > placement.start {
      let input = placement.input
      let asset = AVURLAsset(url: URL(fileURLWithPath: input.path))
      let sourceDuration = try await asset.load(.duration).seconds
      let sourceLength = min(sourceDuration - placement.sourceStart, (placement.end-placement.start)*placement.rate)
      guard sourceLength > 0 else { continue }
      let range = CMTimeRange(start: CMTime(seconds: placement.sourceStart, preferredTimescale: 60000), duration: CMTime(seconds: sourceLength, preferredTimescale: 60000))
      let destination = CMTime(seconds: placement.start, preferredTimescale: 60000)
      let inserted = CMTimeRange(start: destination, duration: range.duration)
      let scaled = CMTime(seconds: sourceLength / placement.rate, preferredTimescale: 60000)
      if input.kind == "video", let source = try await asset.loadTracks(withMediaType: .video).first,
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try track.insertTimeRange(range, of: source, at: destination)
        track.scaleTimeRange(inserted, toDuration: scaled)
        tracks[input.legacyIndex] = track.trackID
        transforms[input.legacyIndex] = try await source.load(.preferredTransform)
      }
      if let source = try await asset.loadTracks(withMediaType: .audio).first,
        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try track.insertTimeRange(range, of: source, at: destination)
        track.scaleTimeRange(inserted, toDuration: scaled)
        let parameter = AVMutableAudioMixInputParameters(track: track)
        // Audio follows display visibility, its time span and camera/input selection.
        let related = p.objects.filter { [.video, .audio].contains($0.kind) }
        var boundaries: [Double] = [0,placement.start,placement.end]
        for object in related {
          boundaries.append(object.start)
          boundaries.append(object.end)
          for segment in object.segments ?? [] { boundaries.append(segment.time) }
        }
        let uniqueBoundaries = Set(boundaries)
        let times = uniqueBoundaries.filter { $0 >= 0 && $0 <= p.duration }.sorted()
        for t in times {
          let audible = related.map { $0.resolved(at: t) }.contains { $0.visible && t >= $0.start && t < $0.end && $0.inputIndex == placement.rootIndex }
          parameter.setVolume(Float(audible ? input.volume : 0), at: CMTime(seconds: t, preferredTimescale: 60000))
        }
        audioParameters.append(parameter)
      }
    }
    guard !tracks.isEmpty else { throw RaceError.invalid("Preview and export need at least one readable video input.") }
    if composition.duration.seconds < p.duration {
      composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: CMTime(seconds: p.duration-composition.duration.seconds, preferredTimescale: 60000)))
    }
    let vc = AVMutableVideoComposition()
    vc.customVideoCompositorClass = RaceCompositor.self
    vc.instructions = [SceneInstruction(scene: scene, tracks: tracks, transforms: transforms, duration: composition.duration.seconds)]
    vc.renderSize = CGSize(width: p.width, height: p.height)
    vc.frameDuration = CMTime(seconds: 1/p.fps, preferredTimescale: 60000)
    let mix = AVMutableAudioMix(); mix.inputParameters = audioParameters
    return PreparedScene(composition: composition, video: vc, audio: mix)
  }

  public static func snapshot(scene: RenderScene, time: Double, to url: URL) throws {
    let p = scene.project
    let size = CGSize(width: p.width, height: p.height)
    guard p.width > 0, p.width <= 16384, p.height > 0, p.height <= 16384, time.isFinite else {
      throw RaceError.invalid("Invalid snapshot settings.")
    }
    guard
      let c = CGContext(
        data: nil, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw RaceError.invalid("Cannot allocate snapshot canvas.") }
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    c.fill(CGRect(origin: .zero, size: size))
    let ci = CIContext(options: [.cacheIntermediates: false])
    for o in p.objects.map({ $0.resolved(at: time) }) where o.visible && time >= o.start && time <= o.end {
      if o.kind == .video, let placement = p.media(for: o.inputIndex, at: time),
        placement.input.exists
      {
        let input = placement.input
        let sourceTime = placement.sourceTime(at: time)
        if sourceTime >= 0 {
          let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: input.path)))
          gen.appliesPreferredTrackTransform = true
          gen.maximumSize = size
          gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
          gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
          let cg = try gen.copyCGImage(
            at: CMTime(seconds: sourceTime, preferredTimescale: 60000), actualTime: nil)
          PictureProcessor.draw(c, image: CIImage(cgImage: cg), in: OverlayRenderer.rect(o, size: size), opacity: o.opacity, input: input.picture, object: o.picture, context: ci)
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
