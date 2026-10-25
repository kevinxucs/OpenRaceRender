import AppKit
import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class RCZImportTests: XCTestCase {
  // Python zipfile-produced archive; entirely synthetic clocks and speed samples.
  let bytes = Data(base64Encoded: "UEsDBBQAAAAIAAAAIVA1NFnYHAAAABoAAAAMAAAAc2Vzc2lvbi5qc29uq1YqySzJSVWyUlAKrswryUgtyUxWCHKOUqoFAFBLAwQUAAAACAAAACFQzTGfzw4AAAAQAAAAEgAAAGNoYW5uZWxfMV80Ml8wXzFfMWPIeHq+m5GB4UU2hAYAUEsDBBQAAAAIAAAAIVCk5rXJCgAAAAgAAAASAAAAY2hhbm5lbF8xXzQyXzBfNF8wE1BnYFDwY2AAAFBLAQIUAxQAAAAIAAAAIVA1NFnYHAAAABoAAAAMAAAAAAAAAAAAAACAAQAAAABzZXNzaW9uLmpzb25QSwECFAMUAAAACAAAACFQzTGfzw4AAAAQAAAAEgAAAAAAAAAAAAAAgAFGAAAAY2hhbm5lbF8xXzQyXzBfMV8xUEsBAhQDFAAAAAgAAAAhUKTmtckKAAAACAAAABIAAAAAAAAAAAAAAIABhAAAAGNoYW5uZWxfMV80Ml8wXzRfMFBLBQYAAAAAAwADALoAAAC+AAAAAAA=")!
  @MainActor func waitForImport(_ model: EditorModel) async throws {
    for _ in 0..<200 {
      if !model.busy { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Telemetry import did not finish")
  }
  @MainActor func testFinderRCZImportSavesAndReopensAsData() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("Road test Zürich.RCZ")
    try bytes.write(to: url)
    let model = EditorModel(), delegate = AppDelegate()
    delegate.application(NSApplication.shared, open: [url])
    delegate.model = model
    try await waitForImport(model)
    XCTAssertNil(model.error)
    XCTAssertEqual(model.project.inputs.count, 1)
    let input = try XCTUnwrap(model.project.inputs.first)
    XCTAssertEqual(input.kind, "data"); XCTAssertEqual(input.duration, 1)
    XCTAssertFalse(model.project.objects.contains { $0.kind == .video })
    XCTAssertEqual(model.telemetry[input.legacyIndex]?.speed(at: 0.5, unit: "m/s"), 15)
    XCTAssertEqual(model.telemetry[input.legacyIndex]?.title, "Synthetic RCZ")
    let projectURL = root.appendingPathComponent("session.orrp")
    try model.project.save(projectURL)
    let reopened = EditorModel()
    reopened.open(projectURL); await reopened.openTask?.value
    XCTAssertNil(reopened.error)
    XCTAssertEqual(reopened.project.inputs[0].kind, "data")
    XCTAssertEqual(reopened.telemetry[input.legacyIndex]?.count, 2)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App", url.path]), url)
    XCTAssertTrue(Telemetry.supportedExtensions.contains("rcz"))
  }
  @MainActor func testRCZRelinkFailureAndSuccessRetainDataSettings() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let good = root.appendingPathComponent("replacement.rcz"), bad = root.appendingPathComponent("broken.rcz")
    try bytes.write(to: good); try Data(bytes.dropLast()).write(to: bad)
    let model = EditorModel()
    var input = MediaInput(name: "Data", path: "/missing/old.csv", kind: "data", legacyIndex: 9)
    input.offset = 0.25; input.duration = 20; input.dataSettings = DataSettings()
    model.project.inputs = [input]; model.dirty = false
    let before = model.project
    let failed = await model.relink(input.id, to: bad)
    XCTAssertFalse(failed); XCTAssertEqual(model.project, before); XCTAssertFalse(model.dirty)
    model.error = nil
    let success = await model.relink(input.id, to: good)
    XCTAssertTrue(success)
    XCTAssertEqual(model.project.inputs[0].offset, 0.25)
    XCTAssertEqual(model.project.inputs[0].dataSettings, input.dataSettings)
    XCTAssertEqual(model.project.inputs[0].duration, 1)
    XCTAssertEqual(model.telemetry[9]?.speed(at: 0.5, unit: "m/s"), 15)
    model.undo(); XCTAssertEqual(model.project, before)
  }
}
