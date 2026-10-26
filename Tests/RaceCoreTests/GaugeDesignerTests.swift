import XCTest
import AppKit
@testable import RaceCore

final class GaugeDesignerTests: XCTestCase {
  func fixture() throws -> (DisplayObject, Telemetry) {
    var o = DisplayObject(name: "RPM", kind: .rpm)
    o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.maximum = 8000
    var g = GaugeSettings(); g.rotation = -135; g.design = GaugeDesign(); o.gauge = g
    return (o, try Telemetry(text: "Time,RPM\n0,800\n1,6000\n2,2000\n3,7500"))
  }
  func render(_ o: DisplayObject, data: Telemetry, time: Double = 1) throws -> Data {
    let c = try XCTUnwrap(CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8,
      bytesPerRow: 1200, space: OverlayRenderer.colorSpace, bitmapInfo: OverlayRenderer.bitmapInfo))
    XCTAssertTrue(GaugeDesignerRenderer.draw(c, object: o, rect: CGRect(x: 0, y: 0, width: 300, height: 300), data: data, time: time, unit: "mph"))
    return Data(bytes: try XCTUnwrap(c.data), count: 360000)
  }
  func testScaleEndpointsAndNonlinearSplitInBothHalves() {
    var d = GaugeDesign(); d.splitValue = 3000; d.splitAngle = 90
    XCTAssertEqual(d.fraction(0, minimum: 0, maximum: 9000, sweep: 270), 0)
    XCTAssertEqual(d.fraction(1500, minimum: 0, maximum: 9000, sweep: 270), 1.0 / 6, accuracy: 1e-9)
    XCTAssertEqual(d.fraction(3000, minimum: 0, maximum: 9000, sweep: 270), 1.0 / 3, accuracy: 1e-9)
    XCTAssertEqual(d.fraction(6000, minimum: 0, maximum: 9000, sweep: 270), 2.0 / 3, accuracy: 1e-9)
    XCTAssertEqual(d.fraction(9000, minimum: 0, maximum: 9000, sweep: 270), 1)
    XCTAssertEqual(d.fraction(-1, minimum: 0, maximum: 9000, sweep: 270), 0)
    XCTAssertEqual(d.fraction(.nan, minimum: 0, maximum: 9000, sweep: 270), 0)
  }
  func testModesGeometryTicksAndThresholdsAffectRenderedOutput() throws {
    var (o, data) = try fixture()
    let needle = try render(o, data: data)
    o.gauge?.design?.mode = .dualNeedle
    let dual = try render(o, data: data)
    XCTAssertNotEqual(needle, dual)
    o.gauge?.design?.mode = .filled
    XCTAssertNotEqual(try render(o, data: data), dual)
    o.gauge?.design?.mode = .needle
    o.gauge?.design?.tip = 65; o.gauge?.design?.tail = -5; o.gauge?.design?.taper = 4
    o.gauge?.design?.majorStyle = .triangle; o.gauge?.design?.minorStyle = .dot; o.gauge?.design?.pins = true
    o.gauge?.design?.needleChange.enabled = true; o.gauge?.design?.needleChange.threshold = 5000
    o.gauge?.design?.needleChange.gradient = true; o.gauge?.design?.needleChange.start = 3000
    o.gauge?.design?.valueStyle.automaticPosition = false; o.gauge?.design?.valueStyle.y = 15
    XCTAssertNotEqual(try render(o, data: data), needle)
    let decoded = try JSONDecoder().decode(DisplayObject.self, from: JSONEncoder().encode(o))
    XCTAssertEqual(decoded.gauge, o.gauge)
    XCTAssertEqual(try render(decoded, data: data), try render(o, data: data))
  }
  func testSmoothingAndAutomaticRangeAreSeekIndependent() throws {
    var (o, data) = try fixture()
    let normal = try render(o, data: data)
    o.gauge?.design?.smoothing = 0.6; o.gauge?.design?.automaticMaximum = true
    let smooth = try render(o, data: data)
    XCTAssertNotEqual(normal, smooth)
    _ = try render(o, data: data, time: 2.5)
    XCTAssertEqual(try render(o, data: data), smooth)
  }
}
