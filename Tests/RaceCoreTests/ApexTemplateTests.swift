import AppKit
import XCTest
@testable import RaceCore

final class ApexTemplateTests: XCTestCase {
  func data() throws -> Telemetry {
    try Telemetry(text: """
      Time,Speed (m/s),RPM,Gear,Accelerator position (%),Brake position (%),Longitudinal acceleration (g),Lateral acceleration (g),Latitude,Longitude,Distance,Steering angle,Yaw rate,Tyre pressure FL (kPa),Tyre temperature FL (°C),Coolant temperature,Intake temperature,Air temperature
      0,0,900,0,0,0,0,0,37,-121,0,0,0,270,27,90,35,24
      1,5,2000,1,20,0,0.2,0.2,37.001,-121,5,10,1,270,27,90,35,24
      2,10,3000,2,40,0,0.4,0.5,37.002,-121,15,20,2,270,27,90,35,24
      3,15,4000,3,50,0,0.3,0.6,37.003,-121,30,30,3,270,27,90,35,24
      4,14.9,3800,3,0,10,-0.2,0.58,37.004,-121,45,20,2,270,27,90,35,24
      5,12,3200,3,0,30,-0.4,0.4,37.005,-121,57,10,1,270,27,90,35,24
      6,8,2200,2,0,50,-0.5,0.03,37.006,-121,65,0,0,270,27,90,35,24
      7,10,3000,2,40,0,0.2,-0.2,37.007,-121,75,-10,-1,270,27,90,35,24
      8,20,4200,3,60,0,0.4,-0.5,37.008,-121,95,-20,-2,270,27,90,35,24
      9,30,6000,4,80,0,0.5,-0.8,37.009,-121,125,-30,-3,270,27,90,35,24
      10,29,5800,4,0,20,-0.3,-0.6,37.01,-121,154,-20,-2,270,27,90,35,24
      """)
  }
  func pixels(_ scene: RenderScene, time: Double) throws -> Data {
    let c = try XCTUnwrap(CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 0,
      space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    OverlayRenderer.draw(c, scene: scene, time: time, size: CGSize(width: 960, height: 540))
    return try XCTUnwrap(c.makeImage()?.dataProvider?.data) as Data
  }
  func testTemplateContainsAllCoreAndAdditionalInstrumentsWithoutVendorAssets() throws {
    let template = try ApexTemplate.make().reusableLayout()
    XCTAssertEqual(template.objects.count, 30)
    XCTAssertEqual(Set(template.objects.compactMap { $0.hud?.role }), Set(HUDSettings.Role.allCases))
    XCTAssertTrue(template.objects.allSatisfy { $0.legacyPayload == nil && $0.embeddedImage == nil && $0.artwork == nil })
    XCTAssertTrue(template.inputs.allSatisfy { $0.path.isEmpty && $0.duration == 0 })
    for object in template.objects {
      XCTAssertGreaterThanOrEqual(object.x, 0); XCTAssertGreaterThanOrEqual(object.y, 0)
      XCTAssertLessThanOrEqual(object.x+object.width, 100); XCTAssertLessThanOrEqual(object.y+object.height, 100)
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrt")
    defer { try? FileManager.default.removeItem(at: file) }
    try template.save(file)
    let reopened = try RaceProject.read(file)
    XCTAssertEqual(reopened.objects.map(\.hud), template.objects.map(\.hud))
    var session = RaceProject(); session.inputs = [MediaInput(name: "Data", path: "", kind: "data", legacyIndex: 8)]
    session.applyLayout(reopened, replace: true)
    XCTAssertTrue(session.objects.allSatisfy { $0.inputIndex == 8 })
    let road = ApexTemplate.make(road: true)
    XCTAssertEqual(road.objects.count, 30)
    XCTAssertFalse(road.objects.first { $0.kind == .lap }!.visible)
    XCTAssertTrue(road.objects.first { $0.name == "Tyres" }!.visible)
    XCTAssertEqual(road.objects.first { $0.name == "Session time" }!.x, 3)
    let oil = template.objects.first { $0.name == "Oil" }!, coolant = template.objects.first { $0.name == "Coolant" }!
    XCTAssertEqual(oil.applyingStyle(coolant).hud?.label, "Oil")
    XCTAssertEqual(oil.applyingStyle(coolant).channel, "oil")
  }
  func testCompletedPeaksAreStableAcrossSeeksAndDoNotUseFutureData() throws {
    let data = try data(), speed = HUDPeaks.get(data, channel: "speed", speed: true), g = HUDPeaks.get(data, channel: "gy", speed: false)
    XCTAssertNil(speed.value(at: 3)); XCTAssertNil(g.value(at: 3))
    XCTAssertEqual(speed.value(at: 5), 15); XCTAssertEqual(g.value(at: 5), 0.6)
    XCTAssertEqual(speed.value(at: 10), 30); XCTAssertEqual(g.value(at: 10), 0.8)
    XCTAssertEqual(speed.value(at: 5), 15); XCTAssertEqual(g.value(at: 5), 0.6)
    XCTAssertNil(speed.value(at: -1)); XCTAssertNil(speed.value(at: 11))
    let minimum = HUDPeaks.get(data, channel: "speed", speed: true, minimum: true)
    XCTAssertNil(minimum.value(at: 6)); XCTAssertEqual(minimum.value(at: 7), 8); XCTAssertEqual(minimum.value(at: 10), 8)
    XCTAssertTrue(speed === HUDPeaks.get(data, channel: "speed", speed: true))
    let missing = HUDPeaks.get(data, channel: "oil", speed: false)
    XCTAssertNil(missing.value(at: 10))
  }
  func testPressureUnitConversionsPreserveRecordedValues() {
    XCTAssertEqual(HUDRenderer.tyrePressure(270, header: "Pressure (kPa)", unit: "psi"), 39.1602, accuracy: 0.0001)
    XCTAssertEqual(HUDRenderer.tyrePressure(270, header: "Pressure (kPa)", unit: "bar"), 2.7, accuracy: 1e-9)
    XCTAssertEqual(HUDRenderer.tyrePressure(39, header: "Pressure (psi)", unit: "psi"), 39, accuracy: 1e-9)
    XCTAssertEqual(HUDRenderer.tyrePressure(2.7, header: "Pressure (bar)", unit: "kPa"), 270, accuracy: 1e-9)
  }
  func testNativeHUDReplaysIdenticallyAndMissingValuesDoNotBecomeZeros() throws {
    var p = ApexTemplate.make(); p.inputs[0].duration = 10
    let data = try data(), scene = RenderScene(project: p, telemetry: [1: data])
    let first = try pixels(scene, time: 5)
    XCTAssertGreaterThan(first.enumerated().filter { $0.offset%4 == 3 && $0.element > 0 }.count, 25000)
    _ = try pixels(scene, time: 10); _ = try pixels(scene, time: 1)
    XCTAssertEqual(try pixels(scene, time: 5), first)
    var oil = try XCTUnwrap(p.objects.first { $0.name == "Oil" }); oil.x = 0; oil.y = 0; oil.width = 100; oil.height = 100
    p.objects = [oil]
    let unavailable = try pixels(RenderScene(project: p, telemetry: [1: data]), time: 5)
    data.configure(DataSettings())
    var settings = DataSettings(), field = CalculatedField(); field.name = "Oil"; field.source = "RPM"; field.multiply = 0; settings.fields = [field]
    data.configure(settings)
    XCTAssertNotEqual(try pixels(RenderScene(project: p, telemetry: [1: data]), time: 5), unavailable)
  }
}
