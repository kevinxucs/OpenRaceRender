import XCTest
import AppKit
@testable import RaceCore

final class DrawingTests: XCTestCase {
  func render(_ object: DisplayObject, width: Int = 400, height: Int = 160) throws -> Data {
    var p = RaceProject(); p.width = width; p.height = height; p.objects = [object]
    let c = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: OverlayRenderer.colorSpace, bitmapInfo: OverlayRenderer.bitmapInfo))
    OverlayRenderer.draw(c, scene: RenderScene(project: p, telemetry: [:]), time: 0, size: CGSize(width: width, height: height))
    return Data(bytes: try XCTUnwrap(c.data), count: width * height * 4)
  }
  func object(_ kind: ObjectKind) -> DisplayObject {
    var o = DisplayObject(name: "Drawing", kind: kind)
    o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.color = "#FFFFFF"
    return o
  }
  func testTypographyChangesPixelsAndPreservesMultilineTextAndStyles() throws {
    var o = object(.text); o.text = "Session title\nLap 2"
    var t = TextSettings(); t.size = 28; t.referenceHeight = 160; o.typography = t
    let left = try render(o)
    XCTAssertTrue(left.contains { $0 != 0 })
    t.alignment = .right; o.typography = t
    XCTAssertNotEqual(try render(o), left)
    t.bold = true; t.italic = true; t.underline = true; t.strikethrough = true
    t.outline = true; t.outlineColor = "#FF0000"; t.outlineWidth = 3; o.typography = t
    let styled = try render(o)
    XCTAssertNotEqual(styled, left)
    let decoded = try JSONDecoder().decode(DisplayObject.self, from: JSONEncoder().encode(o))
    XCTAssertEqual(decoded.typography, t); XCTAssertEqual(decoded.text, o.text)
    XCTAssertEqual(try render(decoded), styled)
    t.fitToBox = true; t.size = 250; o.typography = t
    XCTAssertTrue(try render(o).contains { $0 != 0 })
  }
  func testShapeKindsGradientAndOutlineProduceDistinctPixels() throws {
    var o = object(.shape), s = ShapeSettings(); s.referenceHeight = 160
    var images = Set<Data>()
    for kind in ShapeSettings.Kind.allCases {
      s.kind = kind; o.shape = s
      let pixels = try render(o)
      XCTAssertTrue(pixels.contains { $0 != 0 }, kind.rawValue)
      XCTAssertTrue(images.insert(pixels).inserted, kind.rawValue)
    }
    s.kind = .ellipse; s.fill = false; s.stroke = true; s.strokeWidth = 5; o.shape = s
    let outlined = try render(o)
    XCTAssertFalse(images.contains(outlined))
    s.fill = true; s.gradient = true; s.gradientColor = "#FF0000"; o.shape = s
    XCTAssertNotEqual(try render(o), outlined)
    let decoded = try JSONDecoder().decode(DisplayObject.self, from: JSONEncoder().encode(o))
    XCTAssertEqual(decoded.shape, s)
  }
  func testActualLegacyTextAndShapeRecordTypes() throws {
    var text = object(.text); text.legacyType = 13
    var d = Data(repeating: 0, count: 808)
    d.putU32(0x112233, 0); d.putUTF16("Title\nSecond line", 4, 512); d.putUTF16("Helvetica", 516, 128)
    d.putFloat(41, 644); d[648] = 3; d[649] = 2; d[651] = 1; d.putU32(0x445566, 652)
    text.legacyPayload = d; LegacyReader.inferDetails(&text)
    XCTAssertEqual(LegacyReader.kind(13, name: "Title"), .text)
    XCTAssertEqual(text.text, "Title\nSecond line"); XCTAssertEqual(text.color, "#112233")
    XCTAssertEqual(text.typography?.size, 41); XCTAssertEqual(text.typography?.alignment, .right)
    XCTAssertEqual(text.typography?.bold, true); XCTAssertEqual(text.typography?.italic, true)
    var shape = object(.shape); shape.legacyType = 12
    d = Data(repeating: 0, count: 20); d.putU32(0xffffff, 0); d.putU32(0x00ff00, 4); d[8] = 3; d[9] = 4; d.putU32(0xff000000, 12)
    shape.legacyPayload = d; LegacyReader.inferDetails(&shape)
    XCTAssertEqual(LegacyReader.kind(12, name: "Circle"), .shape)
    XCTAssertEqual(shape.shape?.kind, .ellipse); XCTAssertEqual(shape.shape?.strokeWidth, 4)
    XCTAssertEqual(shape.shape?.gradient, false); XCTAssertEqual(shape.color, "#00FF00")
  }
}
