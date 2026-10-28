import Foundation
import XCTest
@testable import RaceCore

final class SessionRecoveryTests:XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
  }
  func testDurableRecoveryLocksArchiveAndOriginalPreservation() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root.appendingPathComponent("Recovery")),session = try store.newSession()
    let original = root.appendingPathComponent("original.orrp"),sentinel = Data("Original remains unchanged".utf8);try sentinel.write(to:original)
    var project = RaceProject();project.name = "Original fixture";project.rangeStart = 3;project.rangeEnd = 20;project.notes = "Unsaved changes"
    var input = MediaInput(name:"Camera",path:"/example/video.mp4",kind:"video");input.picture = PictureSettings();input.picture?.hue = -30;input.offset = 0.25
    project.inputs = [input];project.lastExport = ExportDestination(path:"/example/output.mp4",start:3,duration:17)
    try session.persist(project:project,originalURL:original,playhead:12,revision:1)
    XCTAssertTrue(try store.listing().candidates.isEmpty,"Live editor snapshots must not be offered to another instance")
    let active = RecoveryCandidate(id:session.id,name:project.name,savedAt:Date(),originalURL:original,archived:false)
    XCTAssertThrowsError(try store.read(active));XCTAssertThrowsError(try store.archive(active))
    session.close(removeSnapshot:false)
    let candidate = try XCTUnwrap(store.listing().candidates.first),snapshot = try store.read(candidate)
    XCTAssertEqual(snapshot.project,project);XCTAssertEqual(snapshot.playhead,12);XCTAssertEqual(snapshot.originalURL,original)
    XCTAssertEqual(try Data(contentsOf:original),sentinel)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:store.file(session.id).path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:store.directory.path)[.posixPermissions] as? NSNumber)?.intValue,0o700)
    try store.archive(candidate);XCTAssertTrue(try store.listing().candidates.isEmpty)
    let archived = try XCTUnwrap(store.listing(includeArchived:true).candidates.first)
    XCTAssertTrue(archived.archived);XCTAssertEqual(try store.read(archived).project,project)
  }
  func testOversizedAndUnreadableCopiesRetainPreviousSnapshot() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root,maximumBytes:4096),session = try store.newSession()
    var p = RaceProject();p.name = "Last good"
    try session.persist(project:p,originalURL:nil,playhead:0,revision:1)
    p.notes = String(repeating:"x",count:10000)
    XCTAssertThrowsError(try session.persist(project:p,originalURL:nil,playhead:0,revision:2))
    session.close(removeSnapshot:false)
    let candidate = try XCTUnwrap(store.listing().candidates.first)
    XCTAssertNil(try store.read(candidate).project.notes)
    let corrupt = store.file(UUID());try Data("broken".utf8).write(to:corrupt)
    let oversized = store.file(UUID());try Data(repeating:0,count:4097).write(to:oversized)
    XCTAssertEqual(try store.listing().unreadableCount,2)
    XCTAssertTrue(FileManager.default.fileExists(atPath:corrupt.path));XCTAssertTrue(FileManager.default.fileExists(atPath:oversized.path))
  }
  func testRevisionOrderingAndCleanClosePreventLateSnapshotResurrection() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root),session = try store.newSession()
    var p = RaceProject();p.name = "Latest"
    try session.persist(project:p,originalURL:nil,playhead:0,revision:2)
    p.name = "Stale";try session.persist(project:p,originalURL:nil,playhead:0,revision:1)
    XCTAssertEqual(try store.decode(session.id,archived:false).project.name,"Latest")
    session.close(removeSnapshot:true)
    try session.persist(project:p,originalURL:nil,playhead:0,revision:3)
    XCTAssertFalse(FileManager.default.fileExists(atPath:store.file(session.id).path))
    XCTAssertTrue(try store.listing().candidates.isEmpty)
  }
  func testUnexpectedProcessExitReleasesLiveRecoveryLock() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root),session = try store.newSession()
    try session.persist(project:RaceProject(),originalURL:nil,playhead:0,revision:1)
    session.close(removeSnapshot:false)
    let child = Process(),ready = Pipe();child.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    child.arguments = ["python3","-u","-c","import fcntl,sys,time; f=open(sys.argv[1],'a'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); time.sleep(30)",root.appendingPathComponent(session.id.uuidString+".lock").path]
    child.standardOutput = ready
    try child.run();defer {if child.isRunning {child.terminate();child.waitUntilExit()}}
    XCTAssertEqual(try ready.fileHandleForReading.read(upToCount:6),Data("ready\n".utf8))
    XCTAssertTrue(try store.listing().candidates.isEmpty)
    child.terminate();child.waitUntilExit()
    XCTAssertEqual(try store.listing().candidates.count,1)
  }
  func testDiagnosticsBoundedPersistenceExcludesPrivateErrorAndMetricContent() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("Diagnostics/events.json"),log = DiagnosticLog(file:file,capacity:3)
    let privateText = "/Users/example/Documents/private.csv?access_token=secret&latitude=37.1"
    log.record(.launch)
    log.record(.projectOpened,metrics:[.inputs:2])
    log.record(.previewFailed,metrics:[.fps:.nan],error:NSError(domain:privateText,code:42,userInfo:[NSLocalizedDescriptionKey:privateText]))
    log.record(.recoverySaved);log.flush()
    let report = log.report();XCTAssertFalse(report.contains(privateText));XCTAssertFalse(report.contains("access_token"));XCTAssertFalse(report.contains("latitude"))
    XCTAssertEqual(log.entries().count,3);XCTAssertEqual(log.entries()[1].errorDomain,"OtherError");XCTAssertEqual(log.entries()[1].errorCode,42)
    XCTAssertTrue(log.entries()[1].metrics.isEmpty)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    let reopened = DiagnosticLog(file:file,capacity:3);XCTAssertEqual(reopened.entries(),log.entries())
    var injected = reopened.entries();injected[0].metrics[privateText] = 1;injected[0].errorDomain = privateText
    try JSONEncoder().encode(injected).write(to:file)
    XCTAssertFalse(DiagnosticLog(file:file).report().contains(privateText))
  }
  func testStandaloneRecoveryExportNeverOverwritesOrChangesFolderPermissions() throws {
    let root = try directory();defer {try? FileManager.default.removeItem(at:root)}
    let store = RecoveryStore(directory:root),session = try store.newSession()
    var p = RaceProject();p.notes = "Retained";p.rangeStart = 1;p.rangeEnd = 10
    try session.persist(project:p,originalURL:nil,playhead:0,revision:1)
    let source = store.file(session.id),destination = root.appendingPathComponent("recovered.orrp")
    XCTAssertThrowsError(try RecoveryStore.exportCopy(from:source,to:destination))
    session.close(removeSnapshot:false)
    try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
    let input = try Data(contentsOf:source)
    try RecoveryStore.exportCopy(from:source,to:destination)
    XCTAssertEqual(try RaceProject.read(destination).notes,p.notes);XCTAssertEqual(try RaceProject.read(destination).rangeEnd,10)
    XCTAssertEqual(try Data(contentsOf:source),input)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:root.path)[.posixPermissions] as? NSNumber)?.intValue,0o755)
    let saved = try Data(contentsOf:destination);XCTAssertThrowsError(try RecoveryStore.exportCopy(from:source,to:destination));XCTAssertEqual(try Data(contentsOf:destination),saved)
  }
}
