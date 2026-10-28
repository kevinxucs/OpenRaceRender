import RaceCore
import SwiftUI

extension EditorModel {
  static func live() -> EditorModel {
    let log = DiagnosticLog(file:DiagnosticLog.defaultFile)
    log.record(.launch)
    return EditorModel(recoveryStore:RecoveryStore(directory:RecoveryStore.defaultDirectory),diagnostics:log)
  }
  func scheduleRecovery() {
    guard recoveryStore != nil else {return}
    recoveryTask?.cancel()
    let revision = documentRevision,ticket = UUID();recoveryTicket = ticket
    let now = Date();if recoveryDue == nil {recoveryDue = now.addingTimeInterval(3)}
    let delay = min(0.75,max(0,recoveryDue!.timeIntervalSince(now)))
    recoveryTask = Task{[weak self] in
      do {try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}catch {return}
      guard let self,self.dirty,self.documentRevision == revision else {return}
      self.recoveryDue = Date().addingTimeInterval(3)
      _ = await self.persistRecoveryNow()
      if self.recoveryTicket == ticket {self.recoveryDue = nil;self.recoveryTask = nil}
    }
  }
  @discardableResult func persistRecoveryNow() async -> Bool {
    guard dirty,let recoveryStore else {return false}
    do {
      if recoverySession == nil {recoverySession = try recoveryStore.newSession()}
      guard let session = recoverySession else {return false}
      recoverySequence &+= 1
      let sequence = recoverySequence,copy = project,url = fileURL ?? project.sourcePath.map{URL(fileURLWithPath:$0)},position = time,revision = documentRevision
      try await Task.detached(priority:.utility) {try session.persist(project:copy,originalURL:url,playhead:position,revision:sequence)}.value
      guard dirty,documentRevision == revision,recoverySession?.id == session.id else {return false}
      lastRecoverySaved = Date();recoveryProblem = nil;diagnostics?.record(.recoverySaved)
      return true
    } catch {
      recoveryProblem = "Recovery copy could not be saved. Save your project manually and check available disk space."
      diagnostics?.record(.recoveryFailed,error:error);return false
    }
  }
  func clearActiveRecovery() {
    recoveryTask?.cancel();recoveryTask = nil;recoveryDue = nil;recoveryTicket = UUID()
    recoverySession?.close(removeSnapshot:true);recoverySession = nil;lastRecoverySaved = nil
  }
  func finishCleanShutdown() {clearActiveRecovery();diagnostics?.record(.cleanExit);diagnostics?.flush()}
  func rememberProjectURL(_ url:URL) {preferences.set(url.path,forKey:"lastProjectPath")}
  func refreshRecoveries(includeArchived:Bool = false) async {
    guard let recoveryStore else {return}
    do {
      let listing = try await Task.detached(priority:.utility) {try recoveryStore.listing(includeArchived:includeArchived)}.value
      recoveryCandidates = listing.candidates;recoveryUnreadableCount = listing.unreadableCount
    }catch {recoveryProblem = "Recovery copies could not be listed. Check the recovery folder permissions.";diagnostics?.record(.recoveryFailed,error:error)}
  }
  func beginStartupRecovery(allowReopen:Bool) {
    guard !startupRecoveryStarted else {return};startupRecoveryStarted = true
    let revision = documentRevision
    startupRecoveryTask = Task {
      await refreshRecoveries()
      guard allowReopen,startupReopenAllowed,documentRevision == revision,!dirty,project.objects.isEmpty,project.inputs.isEmpty else {return}
      if !recoveryCandidates.isEmpty || recoveryUnreadableCount > 0 {showRecovery = true}
      else if reopenLastProject,let path = preferences.string(forKey:"lastProjectPath"),FileManager.default.fileExists(atPath:path) {open(URL(fileURLWithPath:path))}
    }
  }
  @discardableResult func restoreRecovery(_ candidate:RecoveryCandidate) async -> Bool {
    guard let recoveryStore else {return false}
    let revision = documentRevision
    do {
      let snapshot = try await Task.detached(priority:.utility) {try recoveryStore.read(candidate)}.value
      guard documentRevision == revision,confirmDiscard() else {return false}
      installRecovery(snapshot)
      recoveryTask?.cancel()
      // Only archive the old copy after the recovered document has its own durable copy.
      if await persistRecoveryNow() {do {try recoveryStore.archive(candidate)}catch {diagnostics?.record(.recoveryFailed,error:error)}}
      diagnostics?.record(.recoveryRestored);showRecovery = false
      await refreshRecoveries();return true
    }catch {recoveryProblem = "This recovery copy could not be restored. It has been retained in the recovery folder.";diagnostics?.record(.recoveryFailed,error:error);return false}
  }
  func archiveRecovery(_ candidate:RecoveryCandidate,includeArchived:Bool = false) async {
    guard let recoveryStore else {return}
    do {try recoveryStore.archive(candidate);await refreshRecoveries(includeArchived:includeArchived)}
    catch {recoveryProblem = "This recovery copy could not be archived.";diagnostics?.record(.recoveryFailed,error:error)}
  }
}

struct RecoverySheet:View {
  @ObservedObject var model:EditorModel
  @Environment(\.dismiss) var dismiss
  @State var archived = false
  @State var working = false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Recover an unsaved session").font(.title2.bold())
      Text("Recovery copies are kept in your Library. Restoring creates an unsaved document; Save As keeps the original project untouched. Media remains in its original location.")
      Toggle("Reopen last saved project on launch",isOn:$model.reopenLastProject)
      Text("Off by default. Opening a saved project may request access to its media folders.").font(.caption).foregroundStyle(.secondary)
      Toggle("Include archived copies",isOn:$archived).onChange(of:archived){_,value in Task{await model.refreshRecoveries(includeArchived:value)}}
      ScrollView {
        VStack(alignment:.leading,spacing:12) {
          if model.recoveryCandidates.isEmpty {Text("No recoverable sessions found.").foregroundStyle(.secondary)}
          ForEach(model.recoveryCandidates) {candidate in
            VStack(alignment:.leading,spacing:6) {
              Text(candidate.name+(candidate.archived ? " · archived" : "")).bold()
              Text(candidate.savedAt.formatted(date:.abbreviated,time:.standard)).font(.caption)
              if let original = candidate.originalURL {Text("Original: "+original.lastPathComponent).font(.caption)}
              HStack {
                Button("Restore copy") {working = true;Task{_ = await model.restoreRecovery(candidate);working = false}}
                if !candidate.archived {Button("Archive") {working = true;Task{await model.archiveRecovery(candidate,includeArchived:archived);working = false}}}
              }.disabled(working)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
          }
        }
      }
      if model.recoveryUnreadableCount > 0 {Text("\(model.recoveryUnreadableCount) unreadable copies were retained for manual inspection.").foregroundStyle(.orange)}
      if let problem = model.recoveryProblem {Text(problem).foregroundStyle(.orange)}
      HStack {
        Button("Show recovery folder") {if let store = model.recoveryStore {NSWorkspace.shared.open(store.directory)}}
        Spacer();Button("Keep for later") {dismiss()}.keyboardShortcut(.cancelAction).disabled(working)
      }
    }.padding(24).frame(width:660,height:540).task {await model.refreshRecoveries()}
  }
}

struct DiagnosticsSheet:View {
  @ObservedObject var model:EditorModel
  @Environment(\.dismiss) var dismiss
  @State var report = ""
  @State var message:String?
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Diagnostic log").font(.title2.bold())
      Text("Local event history for imports, preview preparation, recovery and exports. Source paths, project contents, telemetry samples and credentials are excluded.").font(.callout)
      ScrollView {Text(report).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
      if let message {Text(message).foregroundStyle(.orange)}
      HStack {
        Button("Refresh") {refresh()}
        Button("Export report…",action:export)
        Button("Show log folder") {if let file = model.diagnostics?.file {model.diagnostics?.flush();NSWorkspace.shared.activateFileViewerSelecting([file])}}
        Spacer();Button("Close"){dismiss()}.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width:800,height:560).onAppear{refresh()}
  }
  func refresh() {report = model.diagnostics?.report() ?? "Diagnostic logging is unavailable."}
  func export() {
    refresh();let panel = NSSavePanel();panel.nameFieldStringValue = "OpenRaceRender-Diagnostics.txt"
    guard panel.runModal() == .OK,let url = panel.url else {return}
    do {guard !FileManager.default.fileExists(atPath:url.path) else {throw RaceError.invalid("Choose a new report filename.")};try Data(report.utf8).write(to:url,options:.atomic);message = "Report saved."}
    catch {message = error.localizedDescription}
  }
}
