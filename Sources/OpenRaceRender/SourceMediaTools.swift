import AVFoundation
import AppKit
import CoreImage
import RaceCore
import SwiftUI

extension EditorModel {
  func sourceTimeAtPlayhead(_ input:MediaInput) -> Double? {
    project.placements.first { $0.input.id == input.id && $0.contains(time) }?.sourceTime(at:time)
  }
}

struct SourceMetadata: Sendable {
  var size = CGSize(width:1,height:1)
  var duration: Double = 0
  var fps: Double = 30
  static func load(_ input:MediaInput, data:Telemetry?, fps:Double) async throws -> Self {
    var result = Self(); result.fps = fps
    if input.kind == "image" {
      guard let image = NSImage(contentsOfFile:input.path)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw RaceError.invalid("Relink the image before cropping.") }
      result.size = CGSize(width:image.width,height:image.height); return result
    }
    if input.kind == "data" { result.duration = data?.duration ?? input.duration; return result }
    let asset = AVURLAsset(url:URL(fileURLWithPath:input.path))
    result.duration = try await asset.load(.duration).seconds
    guard result.duration.isFinite, result.duration > 0 else { throw RaceError.invalid("The media file has no readable duration.") }
    if let track = try await asset.loadTracks(withMediaType:.video).first {
      let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
      let rect = CGRect(origin:.zero,size:size).applying(transform)
      result.size = CGSize(width:abs(rect.width),height:abs(rect.height))
      let nominal = try await track.load(.nominalFrameRate)
      if nominal > 0 { result.fps = Double(nominal) }
    } else if input.kind == "video" { throw RaceError.invalid("The selected file has no video track.") }
    return result
  }
}

struct SourceThumbnail: View {
  var input:MediaInput
  var time:Double
  var data:Telemetry?
  var dataKind:ObjectKind = .speed
  var picture:PictureSettings?
  @State private var image:NSImage?
  @State private var error:String?
  var revision:String { "\(input.path):\(time):\(dataKind):\(String(describing:picture))" }
  var body: some View {
    ZStack {
      Color.black
      if let image { Image(nsImage:image).resizable().scaledToFit() }
      else { Text(error ?? "Loading frame…").foregroundStyle(.secondary).font(.caption) }
    }.task(id:revision) { await load() }
  }
  func load() async {
    guard !Task.isCancelled else { return }; image = nil; error = nil
    do {
      let cg:CGImage
      if input.kind == "data", let data {
        var p = RaceProject(); var source = input; source.legacyIndex = 0; source.offset = 0; source.timing = nil; source.duration = data.duration+1
        p.inputs = [source]
        var o = DisplayObject(name:"Source data",kind:dataKind); o.inputIndex = 0; o.x = 0; o.y = 0; o.width = 100; o.height = 100
        o.maximum = dataKind == .rpm ? 8000 : dataKind == .gforce ? 2 : 160; p.objects = [o]
        let c = CGContext(data:nil,width:640,height:360,bitsPerComponent:8,bytesPerRow:2560,
          space:OverlayRenderer.colorSpace,bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[0:data]),time:time,size:CGSize(width:640,height:360))
        cg = c.makeImage()!
      } else if input.kind == "image" {
        guard let found = NSImage(contentsOfFile:input.path)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw RaceError.invalid("Image unavailable") }; cg = found
      } else if input.kind == "audio" {
        throw RaceError.invalid("Audio input · \(clockText(time))")
      } else {
        let generator = AVAssetImageGenerator(asset:AVURLAsset(url:URL(fileURLWithPath:input.path)))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width:1280,height:720)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let frame = try await withTaskCancellationHandler(operation:{
          try await generator.image(at:CMTime(seconds:max(0,time),preferredTimescale:60000))
        },onCancel:{generator.cancelAllCGImageGeneration()})
        cg = frame.image
      }
      guard !Task.isCancelled else { return }
      if let picture {
        let source = input.kind == "image" ? CIImage(cgImage:cg) : PictureProcessor.source(cg,settings:picture)
        let ci = PictureProcessor.apply(source,settings:picture)
        let context = CIContext()
        guard let output = context.createCGImage(ci,from:ci.extent) else { throw RaceError.invalid("Could not preview crop") }
        image = NSImage(cgImage:output,size:CGSize(width:output.width,height:output.height))
      } else { image = NSImage(cgImage:cg,size:CGSize(width:cg.width,height:cg.height)) }
      error = nil
    } catch { if !Task.isCancelled { self.error = error.localizedDescription; image = nil } }
  }
}

struct SourceMediaTools: View {
  @ObservedObject var model:EditorModel
  @Binding var input:MediaInput
  @State private var trim = false
  @State private var crop = false
  var body:some View {
    HStack {
      if input.kind != "image" { Button("Visual trim…") { model.pause(); trim = true } }
      if ["video","image"].contains(input.kind) { Button("Crop / zoom…") { model.pause(); crop = true } }
    }.sheet(isPresented:$trim) { SourceTrimEditor(model:model,input:$input) }
      .sheet(isPresented:$crop) { SourceCropEditor(model:model,input:$input) }
  }
}

struct SourceTrimEditor: View {
  @ObservedObject var model:EditorModel
  @Binding var input:MediaInput
  @Environment(\.dismiss) var dismiss
  @State private var draft:SourceTrimDraft?
  @State private var kind:ObjectKind = .speed
  @State private var error:String?
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Trim source · \(input.name)").font(.title2)
      Text("These are source-file bounds. Synchronization, playback rate and project export marks are preserved.").font(.caption).foregroundStyle(.secondary)
      if input.kind == "data" {
        Picker("Preview",selection:$kind) { Text("Speed").tag(ObjectKind.speed); Text("RPM").tag(ObjectKind.rpm); Text("G-force").tag(ObjectKind.gforce); Text("Map").tag(ObjectKind.map) }
      }
      if let value = draft {
        HStack {
          trimPanel("First source frame",time:value.start,last:false)
          trimPanel("Last included frame",time:value.endPreviewTime,last:true)
        }
        NumberSetting("First source time (s)",value:Binding(get:{draft?.start ?? 0},set:{draft?.start = $0}))
        NumberSetting("End boundary (s, exclusive)",value:Binding(get:{draft?.end ?? 0},set:{draft?.end = $0}))
        Text("Effective length: \(clockText(value.effectiveLength)) at \(value.rate.formatted())× · source \(clockText(value.duration))")
          .font(.system(size:11,design:.monospaced)).foregroundStyle(muted)
        if value.synchronizationFloor > 0 { Text("Synchronization already excludes frames before \(clockText(value.synchronizationFloor)). Adjust synchronization first to restore earlier frames.").font(.caption).foregroundStyle(.orange) }
      } else { ProgressView("Reading source…") }
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") { apply() }.disabled(draft == nil).keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width:840).textFieldStyle(.roundedBorder)
      .task { do {
        let meta = try await SourceMetadata.load(input,data:model.telemetry[input.legacyIndex],fps:model.project.fps)
        guard !Task.isCancelled else { return }; draft = SourceTrimDraft(input:input,duration:meta.duration,frameRate:meta.fps)
      } catch { self.error = error.localizedDescription } }
  }
  func trimPanel(_ title:String,time:Double,last:Bool) -> some View {
    VStack(spacing:8) {
      Text(title).font(.headline)
      SourceThumbnail(input:input,time:time,data:model.telemetry[input.legacyIndex],dataKind:kind).frame(width:390,height:220)
      Text(clockText(time)).font(.system(.caption,design:.monospaced))
      HStack {
        Button("−1 frame") { adjust(last:last,delta:-(draft?.minimumFrame ?? 0)) }
        Button("+1 frame") { adjust(last:last,delta:draft?.minimumFrame ?? 0) }
        Button("Use playhead") { if let source = model.sourceTimeAtPlayhead(input) {
          if last { draft?.end = min(draft?.duration ?? source,source+(draft?.minimumFrame ?? 0)) } else { draft?.start = source }
        } else { error = "This physical input is inactive at the playhead. Choose a source time or move the playhead." } }
      }.controlSize(.small)
      Slider(value:Binding(get:{last ? draft?.end ?? 0 : draft?.start ?? 0},set:{if last {draft?.end = $0} else {draft?.start = $0}}),
        in:0...max(0.001,draft?.duration ?? 1)).accessibilityLabel(title)
    }
  }
  func adjust(last:Bool,delta:Double) {
    guard let value = draft else { return }
    if last { draft?.end = max(value.start+value.minimumFrame,min(value.duration,value.end+delta)) }
    else { draft?.start = max(value.synchronizationFloor,min(value.end-value.minimumFrame,value.start+delta)) }
  }
  func apply() { do { if let draft { input = try draft.applying(to:input); dismiss() } } catch { self.error = error.localizedDescription } }
}
