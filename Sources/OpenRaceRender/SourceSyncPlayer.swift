import AVFoundation
import RaceCore
import SwiftUI

/// Each side owns an independent raw-source player, never the composition player.
@MainActor final class SourceSyncPlayer: ObservableObject {
  let player = AVPlayer()
  @Published var time:Double = 0
  @Published var duration:Double = 0
  @Published var fps:Double = 30
  @Published var playing = false
  @Published var loading = false
  @Published var seeking = false
  @Published var error:String?
  private var observation:Any?
  private var loadID = UUID()
  private var seekID = UUID()
  init() {
    observation = player.addPeriodicTimeObserver(forInterval:CMTime(value:1,timescale:30),queue:.main) { [weak self] value in
      Task { @MainActor in
        guard let self, !self.seeking, value.seconds.isFinite else { return }
        self.time = value.seconds
        if self.time >= self.duration { self.playing = false }
      }
    }
  }
  deinit { if let observation { player.removeTimeObserver(observation) } }
  func load(_ input:MediaInput, at time:Double, projectFPS:Double) async {
    clear(); let request = UUID(); loadID = request; loading = true
    defer { if loadID == request { loading = false } }
    do {
      let metadata = try await SourceMetadata.load(input,data:nil,fps:projectFPS)
      guard !Task.isCancelled, loadID == request else { return }
      duration = metadata.duration; fps = metadata.fps
      player.replaceCurrentItem(with:AVPlayerItem(url:URL(fileURLWithPath:input.path)))
      seek(time)
    } catch { if !Task.isCancelled, loadID == request { self.error = error.localizedDescription } }
  }
  func seek(_ value:Double) {
    guard value.isFinite else { return }
    pause(); error = nil; time = max(0,min(max(0,duration-1/max(1,fps)),value))
    let request = UUID(); seekID = request; seeking = true
    player.seek(to:CMTime(seconds:time,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self] success in
      Task { @MainActor in
        guard let self, self.seekID == request else { return }
        self.seeking = false
        if !success { self.error = "Could not seek the source frame. Choose another time or relink this file." }
      }
    }
  }
  func play(rate:Double) {
    guard duration > 0, !seeking, !loading, error == nil, rate.isFinite else { return }
    playing = true; player.playImmediately(atRate:Float(max(0.01,min(100,rate))))
  }
  func pause() { player.pause(); playing = false }
  func clear() {
    pause(); loadID = UUID(); seekID = UUID(); seeking = false; loading = false
    player.replaceCurrentItem(with:nil); time = 0; duration = 0; error = nil
  }
}

struct SourceSyncSurface: NSViewRepresentable {
  var player:AVPlayer
  func makeNSView(context:Context) -> PlayerSurfaceView { PlayerSurfaceView() }
  func updateNSView(_ view:PlayerSurfaceView,context:Context) { view.playerLayer.player = player }
  static func dismantleNSView(_ view:PlayerSurfaceView,coordinator:()) { view.playerLayer.player = nil }
}

struct SourceSyncPanel: View {
  @ObservedObject var player:SourceSyncPlayer
  var title:String
  var rate:Double
  @State private var muted = true
  var body:some View {
    VStack(alignment:.leading,spacing:9) {
      Text(title).font(.headline)
      SourceSyncSurface(player:player.player).frame(width:420,height:236).background(.black)
      if player.loading { ProgressView("Loading source…") }
      if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
      Slider(value:Binding(get:{player.time},set:{player.seek($0)}),in:0...max(0.001,player.duration-1/max(1,player.fps)))
        .accessibilityLabel(title+" source time")
      HStack {
        Button("−1 frame") { player.seek(player.time-1/max(1,player.fps)) }
        Button(player.playing ? "Pause" : "Play") { if player.playing { player.pause() } else { player.play(rate:rate) } }
        Button("+1 frame") { player.seek(player.time+1/max(1,player.fps)) }
        Spacer()
        Toggle("Mute",isOn:$muted).onChange(of:muted) { _,value in player.player.isMuted = value }
      }.controlSize(.small)
      NumberSetting("Source seconds",value:Binding(get:{player.time},set:{player.seek($0)}))
      Text(clockText(player.time)+" / "+clockText(player.duration)+" · \(player.fps.formatted()) fps")
        .font(.system(.caption,design:.monospaced)).foregroundStyle(mutedColor)
    }.frame(width:420).onAppear { player.player.isMuted = muted }
  }
  private var mutedColor:Color { Color.secondary }
}
