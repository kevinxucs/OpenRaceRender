import AppKit
import XCTest
@testable import RaceCore

final class WidgetDesignStyleTests: XCTestCase {
  func testImportedGaugeSpeedUnitCaptionTracksProjectUnits() {
    var gauge = GaugeSettings(); gauge.label = "Speed (%su%)"
    XCTAssertEqual(gauge.resolvedLabel(unit: "mph"), "Speed (MPH)")
    XCTAssertEqual(gauge.resolvedLabel(unit: "km/h"), "Speed (km/h)")
    XCTAssertEqual(gauge.label, "Speed (%su%)", "Keep the token in reusable templates")
    gauge.label = "RPM"; XCTAssertEqual(gauge.resolvedLabel(unit: "mph"), "RPM")
  }
  func testScriptStyleSettingsAffectDrawingAndSurviveSave() throws {
    var object = DisplayObject(name: "Synthetic design", kind: .throttle)
    object.legacyType = 50; object.inputIndex = 0
    var payload = Data(repeating: 0, count: 67168)
    payload.putU32(100 | (100 << 16), 280)
    let source = Data("DrawRect(0,0,SizeX*DataFactor,SizeY,ColorA,Filled);".utf8)
    payload.replaceSubrange(34400..<34400+source.count, with: source)
    object.legacyPayload = payload
    object.styleMinimum = 0; object.styleMaximum = 100
    object.setStyleColor("#FF0000", index: 0)
    object.styleLabel = "Coolant °C"; object.styleLabelVisible = false; object.styleLabelSize = 24
    object.styleTrigger = 75
    let data = try Telemetry(text: "Time,Throttle\n0,50\n1,50\n")
    func sample(_ o: DisplayObject, x: Int) throws -> [UInt8] {
      let c = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      XCTAssertTrue(LegacyEnhancedRenderer.draw(c, object: o, rect: CGRect(x: 0, y: 0, width: 100, height: 100), data: data, time: 0.5, unit: "mph"))
      let bytes = try XCTUnwrap(c.data?.assumingMemoryBound(to: UInt8.self))
      return Array(UnsafeBufferPointer(start: bytes+50*c.bytesPerRow+x*4, count: 4))
    }
    XCTAssertEqual(try sample(object, x: 40), [255, 0, 0, 255])
    object.styleMaximum = 200
    XCTAssertEqual(try sample(object, x: 40), [0, 0, 0, 0])
    object.setStyleColor("#00FF00", index: 0)
    XCTAssertEqual(try sample(object, x: 10), [0, 255, 0, 255])
    XCTAssertEqual(object.styleLabel, "Coolant °C"); XCTAssertEqual(object.styleLabelSize, 24); XCTAssertEqual(object.styleTrigger, 75)
    XCTAssertEqual(object.styleColor(0), "#00FF00")
    XCTAssertEqual(object.legacyPayload?.subdata(in: 34400..<34400+source.count), source)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrt")
    defer { try? FileManager.default.removeItem(at: file) }
    var project = RaceProject(); project.objects = [object]
    try project.reusableLayout().save(file)
    XCTAssertEqual(try RaceProject.read(file).objects[0].legacyPayload, object.legacyPayload)
    object.styleMinimum = nil; object.styleMaximum = nil
    XCTAssertNil(object.styleMinimum); XCTAssertNil(object.styleMaximum)
    XCTAssertEqual(object.legacyPayload?.f64(256), 100_000_000)
    XCTAssertEqual(object.legacyPayload?.f64(264), 100_000_000)
  }
  func testImportedBarRangeEditsReachRendererInsteadOfOnlyChangingInspector() throws {
    var object = DisplayObject(name: "Synthetic bar", kind: .bar)
    object.legacyType = 31; object.channel = "Throttle"
    var payload = Data(repeating: 0, count: 640)
    payload.putU32(0x0000ff, 308); payload.putU32(0x0000ff, 632)
    for offset in [304, 316, 332] { payload.putU32(0xff000000, offset) }
    object.legacyPayload = payload
    object.styleMinimum = 0; object.styleMaximum = 100
    let data = try Telemetry(text: "Time,Throttle\n0,50\n1,50\n")
    func filled(_ object: DisplayObject) throws -> Bool {
      let c = try XCTUnwrap(CGContext(data: nil, width: 100, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
        space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      XCTAssertTrue(LegacyStyledRenderer.draw(c, object: object, rect: CGRect(x: 0, y: 0, width: 100, height: 10), data: data, time: 0.5, unit: "mph", canvasHeight: 480))
      return try XCTUnwrap(c.data?.assumingMemoryBound(to: UInt8.self))[40*4+3] > 200
    }
    XCTAssertTrue(try filled(object)); object.styleMaximum = 200; XCTAssertFalse(try filled(object))
  }
}
