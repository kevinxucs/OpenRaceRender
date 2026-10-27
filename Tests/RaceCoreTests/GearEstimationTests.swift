import AppKit
import XCTest
@testable import RaceCore

final class GearEstimationTests:XCTestCase {
  func testAutomaticCalibrationFindsStableRatiosWithNoiseAndDeterministicSeeking() throws {
    let ratios = [200.0,140,100,75]
    let times = (0..<400).map {Double($0)/20}
    let speed = times.map {10+$0/10}
    let rpm = times.indices.map {speed[$0]*ratios[$0/100]*(1+0.01*sin(times[$0]*2))}
    let result = try GearEstimator.estimate(times:times,speed:speed,rpm:rpm)
    XCTAssertEqual(result.calibration.ratios.count,4)
    for (actual,expected) in zip(result.calibration.ratios,ratios) { XCTAssertEqual(actual,expected,accuracy:expected*0.02) }
    for index in [50,150,250,350] { XCTAssertEqual(result.values[index],Double(index/100+1)) }
    let repeated = try GearEstimator.estimate(times:times,speed:speed,rpm:rpm)
    XCTAssertEqual(result.calibration,repeated.calibration)
    XCTAssertEqual(result.values,repeated.values)
  }
  func testManualRatiosRejectSlipStoppedMissingAndLargeTimeGaps() throws {
    var settings = GearEstimationSettings(); settings.ratios = [200,100]; settings.tolerance = 0.05
    let result = try GearEstimator.estimate(times:[0,0.1,0.2,0.3,0.4],speed:[0,10,10,10,10],rpm:[1200,2000,1500,1000,.nan],settings:settings)
    XCTAssertTrue(result.values[0].isNaN); XCTAssertEqual(result.values[1],1); XCTAssertTrue(result.values[2].isNaN)
    XCTAssertEqual(result.values[3],2); XCTAssertTrue(result.values[4].isNaN)
    XCTAssertEqual(result.calibration.matchedSamples,2); XCTAssertEqual(result.calibration.candidateSamples,3)
    let gap = try GearEstimator.estimate(times:[0,0.1,10,10.1],speed:[10,10,10,10],rpm:[2000,2000,1000,1000],settings:settings)
    XCTAssertTrue(gap.values[1].isNaN); XCTAssertEqual(gap.values[2],2)
    XCTAssertEqual(GearEstimator.displayName(nil),"—"); XCTAssertEqual(GearEstimator.displayName(0),"N"); XCTAssertEqual(GearEstimator.displayName(-1),"R")
  }
  func testRecordedPriorityForcedCalculationAdjustmentAndDiscreteOutputs() throws {
    let data = try Telemetry(text:"Time,Speed (m/s),RPM,Gear\n0,10,2000,5\n1,10,1000,6\n2,10,1000,6\n")
    XCTAssertEqual(data.value("gear",at:0.5),5); XCTAssertEqual(data.provenance(for:"gear")?.kind,.recorded)
    var options = GearEstimationSettings(); options.ratios = [200,100]
    var settings = DataSettings(); settings.gearDerivation = .calculate; settings.gearEstimation = options; settings.gearAdjustment = 2
    data.configure(settings)
    XCTAssertEqual(data.value("gear",at:0.5),3); XCTAssertEqual(data.value("gear",at:1),4)
    XCTAssertEqual(data.provenance(for:"gear")?.kind,.gear)
    settings.gearDerivation = .recordedOnly; data.configure(settings)
    XCTAssertEqual(data.value("gear",at:0.5),7,"Adjustment must preserve the recorded gear's step behavior")
    settings.gearAdjustment = nil; data.configure(settings); XCTAssertEqual(data.value("gear",at:0.5),5)
  }
  func testSpeedUnitsCalibrationAtPlayheadAndMissingGearOffset() throws {
    for (header,value) in [("Speed (m/s)",10.0),("Speed (km/h)",36),("Speed (mph)",22.369362921)] {
      let data = try Telemetry(text:"Time,\(header),RPM\n0,\(value),2000\n1000,\(value),2000\n2000,\(value),2000\n")
      var options = GearEstimationSettings(); options.ratios = [300,200,100]
      var settings = DataSettings(); settings.timeUnitsPerSecond = 1000; settings.gearEstimation = options; data.configure(settings)
      XCTAssertEqual(data.value("gear",at:1),2)
      XCTAssertEqual(try XCTUnwrap(data.gearRatio(at:1)),200,accuracy:1e-6)
      settings.gearAdjustment = 1; data.configure(settings); XCTAssertEqual(data.value("gear",at:1),3)
    }
  }
  func testInvalidCalibrationAndAbsentInputsStayUnknownAndCanBeDisabled() throws {
    for ratios in [[],[100,200],[100,100],[Double.nan],[0.0]] {
      var options = GearEstimationSettings(); options.ratios = ratios
      XCTAssertThrowsError(try GearEstimator.estimate(times:[0,1],speed:[10,10],rpm:[2000,2000],settings:options))
    }
    let data = try Telemetry(text:"Time,Gear\n0,2\n1,3\n")
    var settings = DataSettings(); settings.gearDerivation = .calculate; data.configure(settings)
    XCTAssertNil(data.value("gear",at:0.5)); XCTAssertNotNil(data.gearEstimateMessage)
    settings.gearDerivation = .recordedOnly; data.configure(settings); XCTAssertEqual(data.value("gear",at:0.5),2)
    let missing = try Telemetry(text:"Time,Speed (m/s),RPM\n0,10,2000\n1,10,2000\n2,10,2000\n")
    XCTAssertEqual(missing.value("gear",at:1),1)
    missing.configure(settings); XCTAssertNil(missing.channelIndex("gear"))
    let empty = try Telemetry(text:"Time,Speed (m/s),RPM,Gear\n0,10,2000,\n1,10,2000,\n2,10,2000,\n")
    XCTAssertEqual(empty.value("gear",at:1),1); XCTAssertEqual(empty.provenance(for:"gear")?.kind,.gear)
  }
  func testGearSettingsPersistAndLegacyCalculationMarkerIsExplicit() throws {
    var settings = DataSettings(); settings.gearDerivation = .calculate; settings.gearAdjustment = 1
    var input = MediaInput(name:"Engine",path:"data.csv",kind:"data"); input.duration = 10; input.dataSettings = settings
    var project = RaceProject(); project.inputs = [input]
    let bytes = try LegacyWriter.data(project,format:.rrp)
    let restored = try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(restored.inputs[0].dataSettings?.gearDerivation,.calculate)
    XCTAssertEqual(restored.inputs[0].dataSettings?.gearAdjustment,1)
    var options = GearEstimationSettings(); options.ratios = [200,100]; settings.gearEstimation = options
    project.inputs[0].dataSettings = settings
    XCTAssertEqual(try JSONDecoder().decode(DataSettings.self,from:JSONEncoder().encode(settings)),settings)
    XCTAssertThrowsError(try LegacyWriter.data(project,format:.rrp))
  }
  func testNativeAndHUDWidgetsMarkEstimatesAndShowUnknownSeparatelyFromNeutral() throws {
    let estimated = try Telemetry(text:"Time,Speed (m/s),RPM\n0,10,2000\n1,10,2000\n2,10,2000\n")
    let recorded = try Telemetry(text:"Time,Gear\n0,1\n1,1\n2,1\n")
    let neutral = try Telemetry(text:"Time,Gear\n0,0\n1,0\n2,0\n")
    let unknown = try Telemetry(text:"Time,Speed (m/s),RPM\n0,0,1000\n1,0,1000\n2,0,1000\n")
    func render(_ data:Telemetry,_ hud:HUDSettings?,time:Double = 1) throws -> Data {
      var p = RaceProject(); var input = MediaInput(name:"Data",path:"",kind:"data"); input.duration = 2; p.inputs = [input]
      var o = DisplayObject(name:"Gear",kind:.gear); o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.hud = hud; p.objects = [o]
      let c = try XCTUnwrap(CGContext(data:nil,width:160,height:160,bitsPerComponent:8,bytesPerRow:640,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[0:data]),time:time,size:CGSize(width:160,height:160))
      return Data(bytes:try XCTUnwrap(c.data),count:102400)
    }
    var gt = HUDSettings(.gear,label:"Gear"); gt.presentation = "gt"
    for hud in [nil,HUDSettings(.gear,label:"Gear"),gt] {
      XCTAssertNotEqual(try render(estimated,hud),try render(recorded,hud),"Estimated gear should be visibly labeled")
      XCTAssertNotEqual(try render(unknown,hud),try render(neutral,hud),"Unknown must not be rendered as neutral")
      XCTAssertEqual(try render(estimated,hud,time:0.5),try render(estimated,hud,time:1.5))
    }
  }
}
