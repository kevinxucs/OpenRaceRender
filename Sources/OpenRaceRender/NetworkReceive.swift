import AppKit
import RaceCore
import SwiftUI

@MainActor final class NetworkReceiveModel:ObservableObject {
  @Published var destination = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("OpenRaceRender/Received",isDirectory:true)
  @Published var running = false
  @Published var urls:[URL] = []
  @Published var progress:Double = 0
  @Published var message = "Choose where to receive your exported telemetry and video."
  @Published var files:[URL] = []
  private var server:LocalTransferServer?
  private var generation = UUID()
  deinit {server?.stop()}
  func start() {
    guard !running else {return};generation = UUID();let revision = generation
    files = [];urls = [];progress = 0;running = true;message = "Starting local receiver…"
    let server = LocalTransferServer { [weak self] event in Task {@MainActor in
      guard let self,self.generation == revision else {return}
      switch event {
      case let .progress(name,received,total):self.progress = Double(received)/Double(max(1,total));self.message = "Receiving \(name) · \(ByteCountFormatter.string(fromByteCount:received,countStyle:.file)) / \(ByteCountFormatter.string(fromByteCount:total,countStyle:.file))"
      case .fileReceived(let name):self.message = "Received \(name) · waiting for the sender to finish"
      case .complete(let files):self.files = files;self.running = false;self.urls = [];self.message = "\(files.count) files ready to import";self.server = nil
      case .failed(let error):self.message = error;self.running = false;self.urls = [];self.server = nil
      }
    }}
    self.server = server
    Task {
      do {
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let port = try await server.start(destination:destination)
        guard generation == revision else {server.stop();return}
        urls = LocalTransferAddress.urls(port:port,token:server.token)
        message = urls.isEmpty ? "No active IPv4 address found. Connect to WiFi or Ethernet, then restart receiving." : "Open a pairing link in the sending device’s browser on the same local network."
      } catch {if generation == revision {message = error.localizedDescription;running = false;self.server = nil}}
    }
  }
  func stop() {
    generation = UUID();server?.stop();server = nil;running = false;urls = []
    if files.isEmpty {message = "Stopped. Unfinished transfer files were removed."}
  }
  func chooseDestination() {
    let panel = NSOpenPanel();panel.canChooseFiles = false;panel.canChooseDirectories = true;panel.canCreateDirectories = true;panel.directoryURL = destination
    if panel.runModal() == .OK,let url = panel.url {destination = url}
  }
}

extension EditorModel {
  @discardableResult func importReceivedFiles(_ files:[URL],newSession:Bool) -> Bool {
    guard !busy,!files.isEmpty,files.allSatisfy({$0.isFileURL && FileManager.default.fileExists(atPath:$0.path)}) else {error = "The completed transfer files are unavailable.";return false}
    if newSession {
      let revision = documentRevision;newProject()
      guard documentRevision != revision else {return false}
      showProjectSetup = false
    }
    addInputs(files)
    return true
  }
}

struct NetworkReceiveSheet:View {
  @ObservedObject var model:EditorModel
  @StateObject private var transfer = NetworkReceiveModel()
  @Environment(\.dismiss) private var dismiss
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Receive files over WiFi / network").font(.title2.bold())
      Text("Use the sending device’s browser to upload exported CSV/RCZ/MSL and video files. TrackAddict’s automatic WiFi discovery is not supported by this receiver.").font(.callout)
      HStack {Text(transfer.destination.path).font(.caption).textSelection(.enabled);Spacer();Button("Choose folder…",action:transfer.chooseDestination).disabled(transfer.running)}
      Text(transfer.message).textSelection(.enabled)
      if transfer.running {
        Text("Use a trusted local network: this transfer uses HTTP. Anyone with the temporary pairing link can upload while this window is receiving.").font(.caption).foregroundStyle(.secondary)
        ForEach(transfer.urls,id:\.absoluteString) {url in
          HStack {Text(url.absoluteString).font(.system(size:10,design:.monospaced)).textSelection(.enabled);Spacer();Button("Copy link") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(url.absoluteString,forType:.string)}}
        }
        ProgressView(value:transfer.progress)
        Button("Stop receiving",action:transfer.stop)
      } else if transfer.files.isEmpty {
        Button("Start receiving",action:transfer.start).buttonStyle(.borderedProminent)
      } else {
        ScrollView {VStack(alignment:.leading) {ForEach(transfer.files,id:\.path) {Text($0.lastPathComponent)}}}.frame(maxHeight:160)
        Text("Completed files are saved in a new Received folder. Check synchronization after import, then choose a template from the library.").font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("Show files in Finder") {NSWorkspace.shared.activateFileViewerSelecting(transfer.files)}
          Button("Add to current project") {if model.importReceivedFiles(transfer.files,newSession:false) {dismiss()}}.disabled(model.busy)
          Button("Create new session") {if model.importReceivedFiles(transfer.files,newSession:true) {dismiss()}}.disabled(model.busy)
        }
      }
      Spacer()
      HStack {Spacer();Button("Close") {transfer.stop();dismiss()}.keyboardShortcut(.cancelAction)}
    }.padding(24).frame(width:760,height:520).onDisappear {transfer.stop()}
  }
}
