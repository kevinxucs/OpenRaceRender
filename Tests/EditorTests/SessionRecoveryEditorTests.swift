import Foundation
import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class SessionRecoveryEditorTests:XCTestCase {
  func directory() throws -> URL {let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url}
  func preferences() -> UserDefaults {UserDefaults(suiteName:"OpenRaceRenderRecoveryTests."+UUID().uuidString)!}
  @MainActor func testAutosaveStartupRestoreKeepsOriginalAndRequiresSaveAs() async throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let original = root.appendingPathComponent("original.orrp"),store = RecoveryStore(directory:root.appendingPathComponent("Recovery"))
    var project = RaceProject();project.name = "Recovery fixture";project.rangeStart = 1;project.rangeEnd = 10
    project.lastExport = ExportDestination(path:root.appendingPathComponent("render.mp4").path,start:1,duration:9)
    try project.save(original);let originalBytes = try Data(contentsOf:original)
    let model = EditorModel(preferences:preferences(),recoveryStore:store)
    model.open(original);await model.openTask?.value
    XCTAssertFalse(model.dirty)
    model.project.notes = "Unsaved fixture notes";model.time = 4
    await model.recoveryTask?.value
    XCTAssertNotNil(model.lastRecoverySaved)
    model.recoverySession?.close(removeSnapshot:false);model.recoverySession = nil
    let recovered = EditorModel(preferences:preferences(),recoveryStore:store,diagnostics:DiagnosticLog())
    recovered.beginStartupRecovery(allowReopen:true);await recovered.startupRecoveryTask?.value
    XCTAssertTrue(recovered.showRecovery)
    let candidate = try XCTUnwrap(recovered.recoveryCandidates.first)
    let restored = await recovered.restoreRecovery(candidate);XCTAssertTrue(restored)
    XCTAssertTrue(recovered.dirty);XCTAssertNil(recovered.fileURL)
    XCTAssertEqual(recovered.project.notes,"Unsaved fixture notes");XCTAssertEqual(recovered.project.rangeEnd,10);XCTAssertEqual(recovered.project.lastExport,project.lastExport);XCTAssertEqual(recovered.time,4)
    XCTAssertEqual(try Data(contentsOf:original),originalBytes)
    XCTAssertTrue(try store.listing(includeArchived:true).candidates.contains{$0.archived})
    recovered.finishCleanShutdown();model.dirty = false
  }
  @MainActor func testSuccessfulSaveAndCleanExitRemoveOnlyActiveCopy() async throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root.appendingPathComponent("Recovery")),log = DiagnosticLog()
    let model = EditorModel(preferences:preferences(),recoveryStore:store,diagnostics:log)
    model.project.notes = "First edit";model.fileURL = root.appendingPathComponent("saved.orrp")
    let saved = await model.persistRecoveryNow();XCTAssertTrue(saved)
    model.save();await model.recoveryTask?.value
    XCTAssertFalse(model.dirty);XCTAssertTrue(try store.listing().candidates.isEmpty)
    XCTAssertEqual(try RaceProject.read(model.fileURL!).notes,"First edit")
    model.project.notes = "Second edit";let next = await model.persistRecoveryNow();XCTAssertTrue(next)
    model.finishCleanShutdown();await model.recoveryTask?.value
    XCTAssertTrue(try store.listing().candidates.isEmpty);XCTAssertTrue(log.entries().contains{$0.kind == .cleanExit})
  }
  @MainActor func testExternalOpenWinsAndLastSavedReopenRequiresOptIn() async throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("external.orrp");var project = RaceProject();project.name = "Explicit external document";try project.save(url)
    let prefs = preferences();prefs.set(url.path,forKey:"lastProjectPath")
    let store = RecoveryStore(directory:root.appendingPathComponent("Recovery")),model = EditorModel(preferences:prefs,recoveryStore:store)
    XCTAssertFalse(model.reopenLastProject)
    model.beginStartupRecovery(allowReopen:true);await model.startupRecoveryTask?.value
    XCTAssertEqual(model.project.name,"Untitled Session")
    prefs.set(true,forKey:"reopenLastProject")
    let reopened = EditorModel(preferences:prefs,recoveryStore:store);reopened.beginStartupRecovery(allowReopen:true);await reopened.startupRecoveryTask?.value;await reopened.openTask?.value
    XCTAssertEqual(reopened.project.name,project.name)
    let previous = try store.newSession();try previous.persist(project:project,originalURL:nil,playhead:0,revision:1);previous.close(removeSnapshot:false)
    let external = EditorModel(preferences:prefs,recoveryStore:store),delegate = AppDelegate();delegate.model = external
    delegate.openExternalURLs([url]);external.beginStartupRecovery(allowReopen:false)
    await external.startupRecoveryTask?.value;await external.openTask?.value
    XCTAssertEqual(external.project.name,project.name);XCTAssertFalse(external.showRecovery)
    XCTAssertEqual(external.recoveryCandidates.count,1)
  }
  @MainActor func testRecoveryWriteFailureRetainsEditsAndReportsWithoutRawPath() async throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let blocked = root.appendingPathComponent("blocked"),bytes = Data("Existing file".utf8);try bytes.write(to:blocked)
    let log = DiagnosticLog(),model = EditorModel(preferences:preferences(),recoveryStore:RecoveryStore(directory:blocked),diagnostics:log)
    model.project.notes = "Retain these edits";let before = model.project
    let saved = await model.persistRecoveryNow();XCTAssertFalse(saved)
    XCTAssertEqual(model.project,before);XCTAssertTrue(model.dirty);XCTAssertNotNil(model.recoveryProblem)
    XCTAssertEqual(try Data(contentsOf:blocked),bytes);XCTAssertFalse(log.report().contains(root.path))
    model.dirty = false
  }
  @MainActor func testContinuousEditsStillCheckpointBeforeTypingStops() async throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let model = EditorModel(preferences:preferences(),recoveryStore:RecoveryStore(directory:root))
    // Keep editing more often than the quiet-period debounce for over three seconds.
    for i in 0..<18 {model.project.notes = "Typing \(i)";try await Task.sleep(nanoseconds:200_000_000)}
    XCTAssertNotNil(model.lastRecoverySaved,"Continuous editing must not indefinitely postpone recovery")
    await model.recoveryTask?.value
    model.recoverySession?.close(removeSnapshot:false);model.recoverySession = nil
    let candidate = try XCTUnwrap(model.recoveryStore?.listing().candidates.first)
    XCTAssertEqual(try model.recoveryStore?.read(candidate).project.notes,"Typing 17")
    model.dirty = false
  }
}
