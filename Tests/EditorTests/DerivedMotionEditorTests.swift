import RaceCore
import XCTest
@testable import OpenRaceRender

final class DerivedMotionEditorTests:XCTestCase {
  @MainActor func testSourceModesLoadFromSavedProjectAndUndoRestoresRecordedChoice() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let csv = root.appendingPathComponent("source.csv")
    try "Time,Latitude,Longitude,Heading (deg),Speed (m/s)\n0,0,0,30,10\n1,0.0001,0,30,10\n2,0.0002,0,30,10\n".write(to:csv,atomically:true,encoding:.utf8)
    let model = EditorModel(); var input = MediaInput(name:"Logger",path:csv.path,kind:"data"); input.duration = 2
    model.project.inputs = [input]
    let before = model.project
    var settings = DataSettings(); settings.headingDerivation = .calculate; settings.headingAdjustment = 90
    input.dataSettings = settings; model.inputBinding(input.id).wrappedValue = input
    let project = root.appendingPathComponent("session.orrp"); try model.project.save(project)
    let reopened = try RaceProject.read(project)
    let loaded = try await EditorModel.loadTelemetry(reopened)
    XCTAssertEqual(loaded[0]?.value("heading",at:1),90); XCTAssertEqual(loaded[0]?.provenance(for:"heading")?.kind,.gps)
    model.undo(); XCTAssertEqual(model.project,before)
    let recorded = try await EditorModel.loadTelemetry(model.project)
    XCTAssertEqual(recorded[0]?.value("heading",at:1),30); XCTAssertEqual(recorded[0]?.provenance(for:"heading")?.kind,.recorded)
  }
  @MainActor func testRecordedOnlyCanReportMissingAutomaticWidgetChannelAndTemplateDropsSessionModes() throws {
    let data = try Telemetry(text:"Time,Latitude,Longitude\n0,0,0\n1,0.0001,0\n2,0.0002,0\n")
    let model = EditorModel(); var input = MediaInput(name:"GPS",path:"",kind:"data",legacyIndex:3); input.duration = 2
    var settings = DataSettings(); settings.lateralDerivation = .recordedOnly; input.dataSettings = settings
    var object = DisplayObject(name:"G-force",kind:.gforce); object.inputIndex = 3
    model.project.inputs = [input]; model.project.objects = [object]; data.configure(settings); model.telemetry[3] = data
    XCTAssertNil(data.channelIndex(object.resolvedChannel))
    settings.lateralDerivation = nil; data.configure(settings)
    XCTAssertEqual(data.value(object.resolvedChannel,at:1),0)
    XCTAssertEqual(data.provenance(for:object.resolvedChannel)?.kind,.gps)
    let layout = try model.project.reusableLayout()
    XCTAssertNil(layout.inputs[0].dataSettings); XCTAssertEqual(layout.objects[0].resolvedChannel,object.resolvedChannel)
  }
}
