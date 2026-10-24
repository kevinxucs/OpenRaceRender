import AppKit
import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class FileOpeningTests: XCTestCase {
  func fixture(in root: URL, name: String = "Session Zürich 1.RRP") throws -> URL {
    let url = root.appendingPathComponent(name)
    var bytes = Data(repeating: 0, count: 2152 + 2216 + 56 + 348)
    bytes.replaceSubrange(0..<4, with: Data("RRP3".utf8))
    bytes.putU32(2152, 12); bytes.putU32(1, 16); bytes.putU32(2216, 20)
    bytes.putU32(56, 28); bytes.putU32(1, 32)
    bytes.putFloat(1.25, 2128); bytes.putFloat(3.75, 2132)
    bytes.putUTF16("Camera", 2152, 128); bytes.putFloat(10, 2152 + 2184)
    let settings = 2152 + 2216
    bytes[settings + 25] = 90; bytes[settings + 26] = 110; bytes[settings + 27] = 125
    bytes[settings + 30] = 100
    let object = settings + 56
    bytes.putUTF16("Full-screen camera", object, 128)
    bytes.putU32(UInt32.max, object + 256)
    bytes.putFloat(100, object + 268); bytes.putFloat(100, object + 272)
    bytes[object + 280] = 10; bytes[object + 281] = 2
    bytes[object + 284] = 1; bytes[object + 293] = 100
    try bytes.write(to: url)
    return url
  }
  func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  @MainActor func testFinderURLBeforeWindowAppearsLoadsWhenEditorAttaches() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(in: root)
    let delegate = AppDelegate()
    delegate.application(NSApplication.shared, open: [url])
    XCTAssertEqual(delegate.pendingOpenURL, url)
    let model = EditorModel()
    delegate.model = model
    delegate.openLaunchArguments(["OpenRaceRender", "--open", "/missing/old.rrp"])
    await model.openTask?.value
    XCTAssertNil(delegate.pendingOpenURL)
    XCTAssertEqual(model.project.sourcePath, url.path)
    XCTAssertEqual(model.project.objects.map(\.name), ["Full-screen camera"])
    XCTAssertEqual(model.project.inputs.count, 1)
    XCTAssertEqual(model.project.inputs[0].picture?.brightness, 0.9)
    XCTAssertEqual(model.project.defaultExportRange, 1.25...3.75)
    XCTAssertNil(model.fileURL) // RRP imports still save to a new native project.
    XCTAssertFalse(model.busy); XCTAssertFalse(model.dirty); XCTAssertNil(model.error)
  }
  @MainActor func testRunningAppReceivesFilenameAndURLRoutesWithoutDuplicateLoads() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(in: root)
    let model = EditorModel(), delegate = AppDelegate()
    delegate.model = model
    delegate.application(NSApplication.shared, openFiles: [url.path])
    let first = try XCTUnwrap(model.openTask)
    delegate.openExternalURLs([url]) // Repeated request while the same file is loading.
    XCTAssertFalse(first.isCancelled)
    await model.openTask?.value
    XCTAssertEqual(model.project.sourcePath, url.path)
    XCTAssertEqual(model.project.objects.count, 1)
    XCTAssertNil(model.error)
  }
  @MainActor func testNewerOpenAndNewSessionCannotBeOverwrittenByAnOlderLoad() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let firstURL = try fixture(in: root, name: "First.rrp")
    let secondURL = try fixture(in: root, name: "Second.rrp")
    let model = EditorModel()
    model.open(firstURL)
    let first = try XCTUnwrap(model.openTask)
    model.open(secondURL)
    await model.openTask?.value; await first.value
    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(model.project.sourcePath, secondURL.path)
    XCTAssertFalse(model.busy)
    model.open(firstURL)
    let pending = try XCTUnwrap(model.openTask)
    model.newProject()
    await pending.value
    XCTAssertTrue(pending.isCancelled)
    XCTAssertEqual(model.project.name, "Untitled Session")
    XCTAssertTrue(model.project.objects.isEmpty); XCTAssertFalse(model.busy)
  }
  @MainActor func testLaunchArgumentsAreHandledOnceAndIgnoreMacOSOptionValues() async throws {
    XCTAssertNil(AppDelegate.launchProjectURL(["App", "-NSDocumentRevisionsDebugMode", "YES"]))
    XCTAssertNil(AppDelegate.launchProjectURL(["App", "-psn_0_12345"]))
    XCTAssertNil(AppDelegate.launchProjectURL(["App", "--open"]))
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(in: root)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App", url.path]), url)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App", "--open", url.path]), url)
    let model = EditorModel(), delegate = AppDelegate()
    delegate.model = model
    delegate.openLaunchArguments(["App", "--open", url.path])
    await model.openTask?.value
    model.newProject()
    delegate.openLaunchArguments(["App", "--open", url.path])
    XCTAssertEqual(model.project.name, "Untitled Session")
    delegate.openExternalURLs([URL(string: "https://example.com/session.rrp")!])
    XCTAssertEqual(model.project.name, "Untitled Session")
  }
}
