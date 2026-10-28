import AppKit
import AVFoundation
import CryptoKit
import RaceCore
import SwiftUI

struct YouTubeUploadRequest:Identifiable {let id = UUID();var file:URL?;var title:String}
@MainActor final class YouTubeUploadModel:ObservableObject {
  @Published var client:GoogleDesktopClient?
  @Published var connected = false
  @Published var draft:YouTubeVideoDraft
  @Published var file:URL?
  @Published var pending:YouTubePendingUpload?
  @Published var working = false
  @Published var progress:Double = 0
  @Published var message = "Choose a completed video and review its YouTube details."
  @Published var videoID:String?
  var validationMessage:String? {do {try draft.validate();return nil} catch {return error.localizedDescription}}
  private var token:GoogleOAuthToken?
  private let store:any YouTubeCredentialStore
  private let transport:any YouTubeHTTPTransport
  private var operation:Task<Void,Never>?
  private var callback:GoogleOAuthCallback?
  private var generation = UUID()
  init(file:URL?,title:String,store:any YouTubeCredentialStore,transport:any YouTubeHTTPTransport) {
    self.file = file;draft = YouTubeVideoDraft(title:String(title.prefix(100)));self.store = store;self.transport = transport
  }
  convenience init(request:YouTubeUploadRequest) {self.init(file:request.file,title:request.title,store:YouTubeKeychainStore(),transport:GoogleHTTPTransport())}
  deinit {operation?.cancel();callback?.cancel()}
  private var account:String {
    "account-"+SHA256.hash(data:Data((client?.id ?? "").utf8)).map{String(format:"%02x",$0)}.joined()
  }
  struct SavedConnection:Codable {var token:GoogleOAuthToken?;var pending:YouTubePendingUpload?}
  func restore() {
    do {
      if let data = try store.read("desktop-client") {client = try JSONDecoder().decode(GoogleDesktopClient.self,from:data);try client?.validate()}
      if client != nil,let data = try store.read(account) {
        let saved = try JSONDecoder().decode(SavedConnection.self,from:data)
        token = saved.token;pending = saved.pending;connected = token != nil
        if let pending {file = URL(fileURLWithPath:pending.file.path);draft = pending.draft;message = "A saved YouTube upload is available. Resume checks its server position first."}
      }
    } catch {message = error.localizedDescription}
  }
  private func persist() throws {try store.write(try JSONEncoder().encode(SavedConnection(token:token,pending:pending)),account:account)}
  func installClient(_ data:Data) throws {
    guard !working,pending == nil else {throw RaceError.invalid("Pause and discard the current local upload state before changing Google clients.")}
    let value = try GoogleDesktopClient.read(data)
    try store.write(try JSONEncoder().encode(value),account:"desktop-client")
    client = value;token = nil;connected = false;pending = nil;restore()
  }
  func signIn() {
    guard !working,let client else {message = "Import Google Desktop OAuth client JSON first.";return}
    working = true;message = "Complete Google sign-in in your system browser.";generation = UUID();let revision = generation
    operation = Task {
      do {
        let pkce = try GooglePKCE(),receiver = GoogleOAuthCallback(state:pkce.state);callback = receiver
        defer {receiver.cancel()}
        let redirect = try await receiver.start()
        try Task.checkCancellation()
        let url = try GoogleOAuth.authorizationURL(client:client,redirect:redirect,pkce:pkce)
        guard NSWorkspace.shared.open(url) else {throw RaceError.invalid("Could not open the system browser for Google sign-in.")}
        let code = try await receiver.code()
        let value = try await GoogleOAuth.exchange(code:code,client:client,redirect:redirect,pkce:pkce,transport:transport)
        guard revision == generation else {return}
        token = value;try persist();connected = true;message = "Google authorization saved. Review the video details, then choose Upload."
      } catch is CancellationError {} catch {if revision == generation {message = error.localizedDescription}}
      if revision == generation {working = false;callback = nil;operation = nil}
    }
  }
  func accessToken() async throws -> String {
    guard let client,var value = token else {throw RaceError.invalid("Sign in to Google before uploading.")}
    if value.needsRefresh {value = try await GoogleOAuth.refresh(value,client:client,transport:transport);token = value;try persist()}
    return value.accessToken
  }
  func disconnect() {
    pause()
    do {try store.write(nil,account:account);token = nil;pending = nil;connected = false;message = "Local authorization and resume state removed. Google permissions can also be removed in your Google Account."}
    catch {message = error.localizedDescription}
  }
  func discardResume() {
    guard !working else {return}
    let previous = pending;pending = nil
    do {try persist();message = "Local resume state removed. This does not delete any video already accepted by YouTube."}
    catch {pending = previous;message = error.localizedDescription}
  }
  /// Exact file/draft are captured at the explicit Upload action; later edits cannot change the request.
  func upload() {
    guard !working,connected,let file else {return}
    let selected = file,snapshot = draft;generation = UUID();let revision = generation
    working = true;videoID = nil;message = pending == nil ? "Preparing YouTube upload…" : "Checking saved YouTube upload…"
    operation = Task {
      do {
        try snapshot.validate()
        let uploader = YouTubeUploader(transport:transport)
        if pending == nil {
          // Inspect the final asset before sending metadata or creating a remote session.
          let asset = AVURLAsset(url:selected),tracks = try await asset.loadTracks(withMediaType:.video)
          guard !tracks.isEmpty,try await asset.load(.duration).seconds > 0 else {throw RaceError.invalid("Choose a completed, playable video before uploading.")}
          let created = try await uploader.begin(file:selected,draft:snapshot,token:try await accessToken())
          guard revision == generation else {return}
          pending = created;try persist()
        }
        guard let current = pending else {throw CancellationError()}
        let id = try await uploader.upload(current,token:{[weak self] in
          guard let self else {throw CancellationError()};return try await self.accessToken()
        },progress:{[weak self] sent,total in Task {@MainActor in
          guard let self,self.generation == revision else {return};self.progress = Double(sent)/Double(max(1,total));self.message = "Uploading · \(Int(self.progress*100))%"
        }})
        guard revision == generation else {return}
        videoID = id;pending = nil;try persist();progress = 1;message = "Upload accepted by YouTube. Processing may continue on YouTube."
      } catch is CancellationError {} catch {if revision == generation {message = error.localizedDescription}}
      if revision == generation {working = false;operation = nil}
    }
  }
  func pause() {generation = UUID();operation?.cancel();operation = nil;callback?.cancel();callback = nil;working = false;message = pending == nil ? "Operation cancelled." : "Paused. Resume will check YouTube’s acknowledged position."}
}
