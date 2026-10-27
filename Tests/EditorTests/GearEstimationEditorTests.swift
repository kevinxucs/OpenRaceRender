import RaceCore
import SwiftUI
import XCTest
@testable import OpenRaceRender

final class GearEstimationEditorTests:XCTestCase {
  @MainActor func testPlayheadCalibrationUsesSelectedSynchronizedSourceAndSavesWithoutChangingMarks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("engine.csv")
    try "Time,Speed (m/s),RPM\n0,10,2000\n1,10,2000\n2,10,2000\n3,10,2000\n4,20,2000\n5,20,2000\n6,20,2000\n".write(to:file,atomically:true,encoding:.utf8)
    let model = EditorModel()
    var other = MediaInput(name:"Other logger",path:"",kind:"data",legacyIndex:2); other.duration = 10
    var input = MediaInput(name:"Selected engine",path:file.path,kind:"data",legacyIndex:7); input.duration = 6; input.offset = 2
    model.project.inputs = [other,input]; model.project.rangeStart = 1; model.project.rangeEnd = 4; model.time = 3
    let before = model.project
    let raw = try Telemetry(url:file)
    let sourceTime = try XCTUnwrap(model.project.sourceTime(for:7,at:model.time))
    let ratio = try XCTUnwrap(raw.gearRatio(at:sourceTime)); XCTAssertEqual(ratio,100)
    var options = GearEstimationSettings(); options.ratios = [200,ratio]
    var settings = DataSettings(); settings.gearDerivation = .calculate; settings.gearEstimation = options
    input.dataSettings = settings; model.inputBinding(input.id).wrappedValue = input
    let saved = root.appendingPathComponent("calibrated.orrp"); try model.project.save(saved)
    let reopened = try RaceProject.read(saved), loaded = try await EditorModel.loadTelemetry(reopened)
    XCTAssertEqual(loaded[7]?.value("gear",at:sourceTime),2)
    XCTAssertEqual(reopened.rangeStart,1); XCTAssertEqual(reopened.rangeEnd,4); XCTAssertEqual(reopened.inputs[1].offset,2)
    model.undo(); XCTAssertEqual(model.project,before)
  }
  @MainActor func testManualCalibrationBindingIsAtomicResettableAndExcludedFromTemplates() throws {
    let model = EditorModel(); var input = MediaInput(name:"Data",path:"",kind:"data"); input.duration = 10; model.project.inputs = [input]
    var object = DisplayObject(name:"Gear",kind:.gear); object.inputIndex = 0; model.project.objects = [object]
    let before = model.project
    let settings = Binding<DataSettings>(get:{model.project.inputs[0].dataSettings ?? DataSettings()},set:{value in
      var input = model.project.inputs[0]; input.dataSettings = value; model.inputBinding(input.id).wrappedValue = input
    })
    let controls = GearEstimationControls(settings:settings,data:nil,model:model,inputIndex:0)
    var options = GearEstimationSettings(); options.ratios = [200,140,100]
    controls.options.wrappedValue = options
    XCTAssertEqual(model.project.inputs[0].dataSettings?.gearEstimation?.ratios,[200,140,100])
    let layout = try model.project.reusableLayout(); XCTAssertNil(layout.inputs[0].dataSettings)
    model.undo(); XCTAssertEqual(model.project,before)
    controls.options.wrappedValue = options; controls.options.wrappedValue = GearEstimationSettings()
    XCTAssertNil(model.project.inputs[0].dataSettings?.gearEstimation)
    model.undo(); XCTAssertEqual(model.project.inputs[0].dataSettings?.gearEstimation?.ratios,[200,140,100])
  }
}
