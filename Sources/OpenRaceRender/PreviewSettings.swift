import AVFoundation
import RaceCore
import SwiftUI

extension EditorModel {
  enum PreviewOwner { case editor,synchronization,fullScreen }
  var previewOwner:PreviewOwner { synchronizationPreviewActive ? .synchronization : fullScreenPreviewActive ? .fullScreen : .editor }
  var previewOptions:RenderOptions {
    var options = previewSettings.options(for:project,seeking:previewSeeking)
    if previewMuted { options.audio = .disabled }
    return options
  }
  func refreshPreviewOwnership() {
    let surfaces = previewSurfaces.allObjects
    // Detach the old player surface before another AVPlayerLayer claims it.
    for view in surfaces where !view.ownsPreview { view.compositionLayer.player = nil }
    for view in surfaces { view.refresh() }
  }
  func setPreviewSeeking(_ active:Bool) {
    guard active != previewSeeking else { return }
    previewSeeking = active
    if previewSettings.reduceWhileSeeking { schedulePreview() }
  }
  func openCompositionWindow() {
    guard !synchronizationPreviewActive else { status = "Close synchronization before opening the full-screen composition"; return }
    guard fullScreenPreview == nil else { fullScreenPreview?.showWindow(nil); return }
    fullScreenPreviewActive = true; refreshPreviewOwnership()
    let controller = CompositionWindowController(model:self)
    fullScreenPreview = controller
    controller.showWindow(nil)
    controller.window?.toggleFullScreen(nil)
  }
}

struct PreviewSettingsSheet:View {
  @ObservedObject var model:EditorModel
  @Environment(\.dismiss) var dismiss
  @State var draft = PreviewSettings()
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Preview settings").font(.title2.bold())
      Text("Saved on this Mac. The project canvas, frame rate and export settings stay independent.").foregroundStyle(muted)
      Form {
        Picker("Picture height",selection:$draft.height) {
          Text("Project resolution").tag(0)
          ForEach([180,360,540,720,1080,1440,2160],id:\.self) { Text("\($0) px").tag($0) }
        }
        Picker("Target frame rate",selection:$draft.fps) {
          Text("Project frame rate").tag(0)
          ForEach([15,24,30,60],id:\.self) { Text("\($0) fps").tag($0) }
        }
        Picker("Scaling",selection:$draft.scaling) {
          Text("High (Lanczos downscaling)").tag(RenderOptions.Scaling.high)
          Text("Linear").tag(RenderOptions.Scaling.linear)
          Text("Minimal (nearest)").tag(RenderOptions.Scaling.nearest)
        }
        Toggle("Reduce quality while dragging the seek control",isOn:$draft.reduceWhileSeeking)
        Picker("Preview audio",selection:$draft.audio) {
          Text("Stereo").tag(RenderOptions.Audio.stereo)
          Text("Mono").tag(RenderOptions.Audio.mono)
          Text("Disabled").tag(RenderOptions.Audio.disabled)
        }
        Picker("Audio rate",selection:$draft.audioSampleRate) {
          Text("Source").tag(0)
          ForEach([22050,44100,48000],id:\.self) { Text("\($0) Hz").tag($0) }
        }.disabled(draft.audio == .disabled)
        Picker("Audio precision",selection:$draft.audioBits) {
          Text("Full precision").tag(0); Text("16 bit").tag(16); Text("8 bit").tag(8)
        }.disabled(draft.audio == .disabled)
      }
      Text("Size and FPS are caps. Seeking uses at most 360p/15 fps and nearest scaling, then restores your choices. Audio is resampled into a reusable cache on first use; mono/precision apply after each source's display mix. Playback hardware may use a different output format.").font(.caption).foregroundStyle(muted)
      HStack {
        Button("Defaults") { draft = PreviewSettings() }
        Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") { model.previewSettings = draft; dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width:520).onAppear{draft = model.previewSettings}
  }
}

@MainActor final class CompositionWindowController:NSWindowController,NSWindowDelegate {
  weak var model:EditorModel?
  init(model:EditorModel) {
    self.model = model
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:600),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    window.title = "OpenRaceRender — Composition"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenPrimary]
    window.contentView = NSHostingView(rootView:CompositionScreen(model:model))
    super.init(window:window); window.delegate = self; window.center()
  }
  required init?(coder:NSCoder) { fatalError() }
  func windowWillClose(_ notification:Notification) {
    model?.setPreviewSeeking(false)
    model?.fullScreenPreviewActive = false
    model?.fullScreenPreview = nil
    model?.refreshPreviewOwnership()
  }
  func windowDidExitFullScreen(_ notification:Notification) { window?.close() }
}

struct CompositionScreen:View {
  @ObservedObject var model:EditorModel
  var body:some View {
    VStack(spacing:0) {
      GeometryReader { geometry in
        let aspect = Double(max(1,model.project.width))/Double(max(1,model.project.height))
        let width = min(geometry.size.width,geometry.size.height*aspect)
        Preview(model:model,interactive:false,fullScreen:true).frame(width:width,height:width/aspect).frame(maxWidth:.infinity,maxHeight:.infinity)
      }
      HStack {
        Button(model.playing ? "Pause" : "Play",action:model.togglePlayback).keyboardShortcut(.space,modifiers:[])
        Slider(value:Binding(get:{model.time},set:{model.seek($0)}),in:0...max(0.001,model.project.duration),onEditingChanged:model.setPreviewSeeking)
        Text(clockText(model.time)).monospacedDigit()
        Button("Close") { model.fullScreenPreview?.close() }.keyboardShortcut(.cancelAction)
      }.padding(12)
    }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
  }
}
