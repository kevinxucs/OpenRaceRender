import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

extension EditorModel {
  func beginYouTubeUpload(file:URL? = nil) {
    let candidate = file ?? project.lastExport.map{URL(fileURLWithPath:$0.path)}
    let available = candidate.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0 : nil}
    youTubeUploadRequest = YouTubeUploadRequest(file:available,title:project.name)
  }
}
struct YouTubeUploadSheet:View {
  @StateObject private var upload:YouTubeUploadModel
  @State private var tagsText = ""
  @Environment(\.dismiss) private var dismiss
  init(request:YouTubeUploadRequest) {_upload = StateObject(wrappedValue:YouTubeUploadModel(request:request))}
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Upload video to YouTube").font(.title2.bold())
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          Text("Google Desktop OAuth client").font(.headline)
          Text(upload.client?.id ?? "Import your Desktop app client JSON from Google Cloud Console with YouTube Data API v3 enabled.").font(.caption).textSelection(.enabled)
          HStack {
            Button("Import client JSON…",action:chooseClient).disabled(upload.working || upload.pending != nil)
            Button(upload.connected ? "Sign in again…" : "Sign in with Google…",action:upload.signIn).disabled(upload.client == nil || upload.working)
            if upload.connected {Button("Disconnect locally",action:upload.disconnect).disabled(upload.working)}
          }
          Text("Sign-in opens your system browser and requests YouTube upload access. Tokens and resume state stay in your Mac’s Keychain. Choose the intended Google/YouTube account in the browser.").font(.caption).foregroundStyle(.secondary)
          Divider()
          HStack {
            Text(upload.file?.path ?? "No completed video selected").font(.caption).textSelection(.enabled)
            Spacer();Button("Choose video…",action:chooseVideo).disabled(upload.working || upload.pending != nil)
          }
          Group {
            TextField("Title",text:$upload.draft.title)
            Text("Description").font(.caption)
            TextEditor(text:$upload.draft.description).font(.body).frame(height:100)
            TextField("Tags (comma separated)",text:$tagsText)
              .onChange(of:tagsText) {value in upload.draft.tags = value.split(separator:",",omittingEmptySubsequences:true).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}}
            HStack {
              Picker("Visibility",selection:$upload.draft.privacy) {ForEach(YouTubePrivacy.allCases,id:\.rawValue) {Text($0.rawValue.capitalized).tag($0)}}
              Picker("Category",selection:$upload.draft.categoryID) {Text("Autos & vehicles").tag("2");Text("Sports").tag("17");Text("People & blogs").tag("22")}
            }
            Picker("Audience",selection:Binding(get:{upload.draft.madeForKids.map{$0 ? 1 : 0} ?? -1},set:{upload.draft.madeForKids = $0 < 0 ? nil : $0 == 1})) {
              Text("Choose audience").tag(-1);Text("Not made for kids").tag(0);Text("Made for kids").tag(1)
            }
            Toggle("Notify subscribers",isOn:$upload.draft.notifySubscribers)
          }.disabled(upload.working || upload.pending != nil || upload.videoID != nil)
          if upload.pending != nil {
            Text("The saved upload retains its original file and metadata. Resume asks YouTube for its acknowledged position. Discarding local resume state does not remove anything already accepted by YouTube.").font(.caption).foregroundStyle(.secondary)
            Button("Discard local resume state",action:upload.discardResume).disabled(upload.working)
          }
          if let validation = upload.validationMessage {Text(validation).font(.caption).foregroundStyle(.orange)}
          Text(upload.message).textSelection(.enabled)
          if upload.working || upload.progress > 0 {ProgressView(value:upload.progress)}
          if let id = upload.videoID,let url = URL(string:"https://youtu.be/"+id) {Link("Open uploaded video on YouTube",destination:url)}
        }.padding(.trailing,8)
      }
      Text("Upload sends the selected video and the details above to YouTube. Visibility starts as Private. No upload starts when you sign in or open this screen.").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Close") {upload.pause();dismiss()}.keyboardShortcut(.cancelAction)
        Spacer()
        if upload.working {Button("Pause / cancel",action:upload.pause)}
        else {
          Button(upload.pending == nil ? "Upload selected video" : "Resume upload",action:upload.upload)
            .buttonStyle(.borderedProminent).disabled(!upload.connected || upload.file == nil || (try? upload.draft.validate()) == nil || upload.videoID != nil)
        }
      }
    }.padding(24).frame(width:780,height:800).textFieldStyle(.roundedBorder)
      .task {upload.restore();tagsText = upload.draft.tags.joined(separator:", ")}.onDisappear {upload.pause()}
  }
  func chooseClient() {
    let panel = NSOpenPanel();panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK,let url = panel.url else {return}
    do {
      let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
      guard size <= 65_536 else {throw RaceError.invalid("Google Desktop client JSON must be below 64 KiB.")}
      try upload.installClient(Data(contentsOf:url))
    } catch {upload.message = error.localizedDescription}
  }
  func chooseVideo() {
    let panel = NSOpenPanel();panel.allowedContentTypes = [.movie]
    if let file = upload.file {panel.directoryURL = file.deletingLastPathComponent()}
    if panel.runModal() == .OK,let url = panel.url {upload.file = url}
  }
}
