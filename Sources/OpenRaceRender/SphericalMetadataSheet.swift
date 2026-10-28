import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

struct SphericalMetadataSheet:View {
  @Environment(\.dismiss) private var dismiss
  @State private var source:URL?
  @State private var info:SphericalMetadata.Info?
  @State private var busy = false
  @State private var message = "Choose a flattened, monoscopic video to inspect its spherical markers."
  @State private var output:URL?
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("360° metadata tool").font(.title2.bold())
      Text("Add or clear spherical markers in a new MP4/MOV copy. Encoded video/audio samples are retained. This does not stitch or unwrap the picture.").font(.callout)
      Button("Choose video…",action:choose).disabled(busy)
      if let source {Text(source.path).font(.caption).textSelection(.enabled)}
      if let info {
        Text("\(info.width) × \(info.height) · V1 \(info.hasV1 ? "present" : "absent") · V2 \(info.hasV2 ? "present" : "absent")")
        HStack {
          Button("Add 360 metadata to copy…") {save(true)}.disabled(busy || info.stereo || info.width != info.height*2)
          Button("Clear 360 metadata in copy…") {save(false)}.disabled(busy || !info.marked)
        }
      }
      if busy {ProgressView()}
      Text(message).textSelection(.enabled)
      if let output {Button("Show output in Finder") {NSWorkspace.shared.activateFileViewerSelecting([output])}}
      Spacer();HStack {Spacer();Button("Close") {dismiss()}.disabled(busy).keyboardShortcut(.cancelAction)}
    }.padding(24).frame(width:660,height:380)
  }
  func choose() {
    let panel = NSOpenPanel();panel.allowedContentTypes = [.mpeg4Movie,.quickTimeMovie]
    guard panel.runModal() == .OK,let url = panel.url else {return}
    source = url;info = nil;output = nil;busy = true
    Task {
      defer {busy = false}
      do {info = try await Task.detached {try SphericalMetadata.inspect(url)}.value;message = "Use a 2:1 equirectangular frame for marking. Original input remains unchanged."}
      catch {message = error.localizedDescription}
    }
  }
  func save(_ enabled:Bool) {
    guard let source else {return}
    let panel = NSSavePanel();panel.allowedContentTypes = [.mpeg4Movie,.quickTimeMovie]
    panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent+(enabled ? "-360." : "-flat.")+source.pathExtension
    guard panel.runModal() == .OK,let destination = panel.url else {return}
    busy = true
    Task {defer {busy = false}
      do {try await Task.detached {try SphericalMetadata.copy(source,to:destination,enabled:enabled)}.value;output = destination;message = "Saved a new metadata copy; encoded media was not recompressed."}
      catch {message = error.localizedDescription}
    }
  }
}
