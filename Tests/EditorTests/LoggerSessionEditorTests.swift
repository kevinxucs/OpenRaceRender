import AppKit
import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class LoggerSessionEditorTests:XCTestCase {
  @MainActor func testSonyMOFFIsImportedAsTelemetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("original.moff")
    let text = "MOFF8\0@Sonygps/ver5.0/wgs-84/20260101120000.000/\n$GPRMC,120000,A,1000,N,02000,E,10,90,010126,,,A\n$GPRMC,120001,A,1000,N,02000,E,10,90,010126,,,A\n"
    try Data(text.utf8).write(to:url);let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertNil(model.error);XCTAssertEqual(model.project.inputs.first?.kind,"data")
    XCTAssertEqual(model.telemetry[0]?.count,2);XCTAssertFalse(model.project.objects.contains{$0.kind == .video})
    XCTAssertEqual(AppDelegate.launchProjectURL(["App",url.path]),url);model.dataSetupRequest = nil
  }
  @MainActor func testOlympusSensorImportSaveAndReload() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("original.SNS")
    try Data("$OLTIM,20260101,120000\n$OLTMP,68,1,0\n$OLTIM,20260101,120002\n$OLTMP,21,0,0\n".utf8).write(to:url)
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertNil(model.error);XCTAssertEqual(model.project.inputs.count,1);XCTAssertEqual(model.project.inputs.first?.kind,"data")
    XCTAssertEqual(model.telemetry[0]?.value("Ambient temperature (C)",at:0),20)
    let saved = root.appendingPathComponent("saved.orrp");try model.project.save(saved)
    let tables = try Telemetry.loadSources(RaceProject.read(saved).inputs)
    XCTAssertEqual(tables[0]?.value("Ambient temperature (C)",at:2),21)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App",url.path]),url);model.dataSetupRequest = nil
  }
  @MainActor func testSpeedAngleImportsAsDataAndKeepsManualAssignmentsPortable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("original.sa")
    try Data("#V=4.0.0=\n<timer #unit=KM/h>\n</timer>\n<trace #pt=2>\n10,20,1,2,3,4,36,-255,10,1,0\n10.001,20.001,2,3,4,5,40,-255,10,1,0\n</trace>\n".utf8).write(to:url)
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertEqual(model.project.inputs.count,1);XCTAssertEqual(model.project.inputs[0].kind,"data")
    XCTAssertFalse(model.project.objects.contains{$0.kind == .video});XCTAssertNil(model.error)
    XCTAssertEqual(model.telemetry[0]?.speed(at:0,unit:"km/h"),36)
    let saved = root.appendingPathComponent("saved.orrp");try model.project.save(saved)
    let reopened = try RaceProject.read(saved),tables = try Telemetry.loadSources(reopened.inputs)
    XCTAssertEqual(tables[0]?.value("Lean angle (deg)",at:0),1)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App",url.path]),url)
    model.dataSetupRequest = nil
  }
  @MainActor func testInternalFITSelectionOffersPreviewAndUndo() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    func word(_ value:UInt32) -> Data {var n = value.littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
    var body = Data([0x40,0,0,20,0,2,253,4,0x86,6,2,0x84,0x41,0,0,18,0,2,2,4,0x86,7,4,0x86])
    for time:UInt32 in [0,1,3,4] {body.append(0);body.append(word(1_000_000_000+time));body.append(contentsOf:time < 3 ? [0xe8,3] : [0x88,0x13])}
    for time:UInt32 in [0,3] {body.append(1);body.append(word(1_000_000_000+time));body.append(word(1000))}
    var bytes = Data([14,0x20,0,0])+word(UInt32(body.count))+Data(".FIT".utf8)
    let head = FITReader.crc(bytes);bytes.append(contentsOf:[UInt8(truncatingIfNeeded:head),UInt8(truncatingIfNeeded:head>>8)]);bytes.append(body)
    let crc = FITReader.crc(bytes);bytes.append(contentsOf:[UInt8(truncatingIfNeeded:crc),UInt8(truncatingIfNeeded:crc>>8)])
    let url = root.appendingPathComponent("multi.fit");try bytes.write(to:url)
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    let request = try XCTUnwrap(model.dataSetupRequest),preview = try await DataSetupPreview.load(url,settings:DataSettings(),session:2)
    XCTAssertEqual(preview.data.fileSessions.count,2);XCTAssertEqual(preview.data.firstSampleUnixTime,1_631_065_603)
    XCTAssertTrue(model.applyDataSetup(request,preview:preview));XCTAssertEqual(model.project.inputs[0].dataSession,2)
    XCTAssertEqual(model.telemetry[0]?.speed(at:0,unit:"m/s"),5)
    model.undo()
    for _ in 0..<100 {if model.telemetry[0]?.speed(at:0,unit:"m/s") == 1 {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertNil(model.project.inputs[0].dataSession);XCTAssertEqual(model.telemetry[0]?.speed(at:0,unit:"m/s"),1)
    model.dataSetupRequest = nil
  }
  @MainActor func testImportOffersSessionAndApplyPersistsUndoAndTiming() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("multi.csv")
    try Data("Time,Speed\n0,10\n1,20\n0,30\n1,40\n".utf8).write(to:url)
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<200 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    let request = try XCTUnwrap(model.dataSetupRequest)
    XCTAssertEqual(model.project.inputs.count,1);XCTAssertFalse(model.project.objects.contains{$0.kind == .video})
    let id = try XCTUnwrap(request.original?.id)
    model.project.inputs[0].offset = 0.25;model.project.rangeStart = 0.1;model.project.rangeEnd = 0.9
    // Reopen after independent timing edits, just as the stale-request guard requires.
    model.dataSetupRequest = nil;model.configureData(model.project.inputs[0])
    let fresh = try XCTUnwrap(model.dataSetupRequest)
    let preview = try await DataSetupPreview.load(url,settings:DataSettings(),session:2)
    XCTAssertTrue(model.applyDataSetup(fresh,preview:preview))
    XCTAssertEqual(model.project.inputs[0].id,id);XCTAssertEqual(model.project.inputs[0].dataSession,2)
    XCTAssertEqual(model.project.inputs[0].offset,0.25);XCTAssertEqual(model.project.rangeStart,0.1);XCTAssertEqual(model.project.rangeEnd,0.9)
    XCTAssertEqual(model.telemetry[model.project.inputs[0].legacyIndex]?.value("speed",at:0),30)
    let saved = root.appendingPathComponent("saved.orrp");try model.project.save(saved)
    let loaded = try RaceProject.read(saved),tables = try Telemetry.loadSources(loaded.inputs)
    XCTAssertEqual(tables[loaded.inputs[0].legacyIndex]?.value("speed",at:0),30)
    model.undo();XCTAssertNil(model.project.inputs[0].dataSession)
    for _ in 0..<100 {if model.telemetry[model.project.inputs[0].legacyIndex]?.value("speed",at:0) == 10 {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertEqual(model.telemetry[model.project.inputs[0].legacyIndex]?.value("speed",at:0),10)
  }
  @MainActor func testUnsupportedLoggerIsExplainedInsteadOfAddedAsVideo() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".prr")
    try Data("not a verified PRR format".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
    let model = EditorModel();model.addInputs([url])
    for _ in 0..<100 {if !model.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
    XCTAssertTrue(model.project.inputs.isEmpty);XCTAssertTrue(model.error?.contains("Export a timestamped") == true)
    XCTAssertEqual(AppDelegate.launchProjectURL(["App",url.path]),url)
  }
}
