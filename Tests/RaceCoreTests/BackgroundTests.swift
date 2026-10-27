import AppKit
import XCTest
@testable import RaceCore

final class BackgroundTests: XCTestCase {
  func artwork() throws -> Data {
    let c = try XCTUnwrap(CGContext(data:nil,width:20,height:20,bitsPerComponent:8,bytesPerRow:80,
      space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    c.setFillColor(OverlayRenderer.color("#FF0000")); c.fill(CGRect(x:0,y:0,width:10,height:20))
    c.setFillColor(OverlayRenderer.color("#00FF00")); c.fill(CGRect(x:10,y:0,width:10,height:20))
    return try XCTUnwrap(NSBitmapImageRep(cgImage:try XCTUnwrap(c.makeImage())).representation(using:.png,properties:[:]))
  }
  func pixels(_ png:Data) throws -> Data {
    let image = try XCTUnwrap(NSImage(data:png)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
    let c = try XCTUnwrap(CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
      space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    return Data(bytes:try XCTUnwrap(c.data),count:image.width*image.height*4)
  }
  func testTransformAspectPanRotationAndKeyingPreserveAlpha() throws {
    var d = BackgroundDraft(image:try artwork())
    let base = try pixels(XCTUnwrap(d.png(width:40,height:20)))
    XCTAssertEqual(base[(10*40+1)*4+3],0); XCTAssertEqual(base[(10*40+14)*4+3],255)
    d.maintainAspect = false
    let stretched = try pixels(XCTUnwrap(d.png(width:40,height:20)))
    XCTAssertEqual(stretched[(10*40+1)*4+3],255)
    d.keyColor = "#FF0000"; d.keyTolerance = 0.01; d.keySoftness = 0.01
    let keyed = try pixels(XCTUnwrap(d.png(width:40,height:20)))
    XCTAssertEqual(keyed[(10*40+4)*4+3],0); XCTAssertEqual(keyed[(10*40+34)*4+3],255)
    d.resetTransform(); d.zoom = 2
    XCTAssertNotEqual(base,try pixels(XCTUnwrap(d.png(width:40,height:20))))
    d.resetTransform(); d.rotation = 90
    XCTAssertNotEqual(base,try pixels(XCTUnwrap(d.png(width:40,height:20))))
    d.resetTransform(); d.offsetX = 50
    XCTAssertEqual(try pixels(XCTUnwrap(d.png(width:40,height:20)))[(10*40+14)*4+3],0)
    d.image = nil; XCTAssertNil(try d.png(width:40,height:20))
  }
  func testMalformedImagesAndGeometryFailOrClampSafely() throws {
    XCTAssertThrowsError(try BackgroundDraft(image:Data([1,2])).png(width:100,height:100))
    var d = BackgroundDraft(image:try artwork()); d.zoom = .infinity; d.rotation = .nan; d.offsetX = .nan
    XCTAssertNotNil(try d.png(width:40,height:20)); XCTAssertThrowsError(try d.png(width:5000,height:20))
    var o = DisplayObject(name:"Map",kind:.map); o.width = .nan
    XCTAssertEqual(WidgetBackground.canvasSize(for:o,project:RaceProject(),width:100),CGSize(width:100,height:100))
  }
  func testApplyingAndClearingBackgroundsPreserveWidgetAndTimelineState() throws {
    let png = try artwork(); var o = DisplayObject(name:"Speed",kind:.speed); o.inputIndex = 8; o.channel = "mph"
    var g = GaugeSettings(); g.backgroundImage = png; o.gauge = g
    let replaced = WidgetBackground.replacing(png,in:o)
    XCTAssertEqual(replaced.inputIndex,8); XCTAssertEqual(replaced.channel,"mph"); XCTAssertEqual(replaced.id,o.id)
    XCTAssertFalse(replaced.gauge!.showFace); XCTAssertNil(replaced.gauge?.backgroundImage)
    XCTAssertEqual(WidgetBackground.data(for:replaced),png)
    var animated = replaced; let clear = WidgetBackground.replacing(nil,in:replaced)
    animated.editSegment(at:1,from:replaced,to:clear)
    XCTAssertEqual(WidgetBackground.data(for:animated.resolved(at:0)),png)
    XCTAssertNil(WidgetBackground.data(for:animated.resolved(at:1)))
    let native = try JSONDecoder().decode(DisplayObject.self,from:JSONEncoder().encode(animated))
    XCTAssertEqual(native.resolved(at:1).artwork,Data())
    var graph = DisplayObject(name:"Graph",kind:.graph); graph.graph = GraphSettings()
    XCTAssertFalse(WidgetBackground.replacing(png,in:graph).graph!.background)
  }
  func testPortableAndLegacyBackgroundRoundTripAndExplicitTimelineClearRefusal() throws {
    var p = RaceProject(); var o = DisplayObject(name:"Title",kind:.text); o.text = "Label"
    o = WidgetBackground.replacing(try artwork(),in:o); p.objects = [o]
    let portable = try p.reusableLayout(); XCTAssertEqual(portable.objects[0].artwork,o.artwork)
    let reopened = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertNotNil(WidgetBackground.data(for:reopened.objects[0]))
    let cleared = WidgetBackground.replacing(nil,in:o)
    p.objects[0].editSegment(at:1,from:o,to:cleared)
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    p.objects = [cleared]
    XCTAssertNoThrow(try LegacyWriter.data(p,format:.rrp))
  }
}
