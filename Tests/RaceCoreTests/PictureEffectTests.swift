import AppKit
import CoreImage
import XCTest
@testable import RaceCore

final class PictureEffectTests:XCTestCase {
  let context = PictureProcessor.context()
  func sample(_ r:Double,_ g:Double,_ b:Double,_ a:Double = 1) -> CIImage {
    CIImage(color:CIColor(red:r,green:g,blue:b,alpha:a)).cropped(to:CGRect(x:0,y:0,width:1,height:1))
  }
  func pixel(_ image:CIImage) -> [UInt8] {
    var bytes = [UInt8](repeating:0,count:4)
    bytes.withUnsafeMutableBytes{context.render(image,toBitmap:$0.baseAddress!,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:OverlayRenderer.colorSpace)}
    return bytes
  }
  func requireCI() throws { try XCTSkipIf(pixel(sample(1,0,0))[0] != 255,"Core Image unavailable on this host.") }
  func testKeyRunsBeforeAdjustmentsAndRetainsOtherColors() throws {
    try requireCI(); var settings = PictureSettings(); var key = ChromaKeySettings(); key.colorTolerance = 0; key.brightnessTolerance = 0.01; settings.chromaKey = key; settings.brightness = 0.5
    XCTAssertEqual(pixel(PictureProcessor.apply(sample(0,1,0),settings:settings)),[0,0,0,0])
    let red = pixel(PictureProcessor.apply(sample(1,0,0),settings:settings)); XCTAssertEqual(red[3],255); XCTAssertEqual(Double(red[0]),128,accuracy:1)
  }
  func testColorBrightnessTolerancesAndSoftAlphaAreIndependent() throws {
    try requireCI(); var settings = PictureSettings(); var key = ChromaKeySettings(); key.colorTolerance = 0.01; key.brightnessTolerance = 0.1; key.softness = 0.2; settings.chromaKey = key
    let softened = pixel(PictureProcessor.apply(sample(0,0.8,0),settings:settings)); XCTAssertEqual(Double(softened[3]),128,accuracy:2)
    settings.chromaKey?.softness = 0; XCTAssertEqual(pixel(PictureProcessor.apply(sample(0,0.8,0),settings:settings))[3],255)
    settings.chromaKey?.brightnessTolerance = 1; XCTAssertEqual(pixel(PictureProcessor.apply(sample(1,1,0),settings:settings))[3],255)
    settings.chromaKey?.colorTolerance = 1; XCTAssertEqual(pixel(PictureProcessor.apply(sample(1,1,0),settings:settings))[3],0)
  }
  func testTintSpectrumAmountAndExistingTransparency() throws {
    try requireCI(); var settings = PictureSettings(); var tint = ColorizeSettings(); tint.color = "#0000FF"; settings.colorize = tint
    XCTAssertEqual(pixel(PictureProcessor.apply(sample(0.5,0.5,0.5),settings:settings)),[0,0,128,255])
    XCTAssertEqual(pixel(PictureProcessor.apply(sample(1,0,0,0.5),settings:settings)),[0,0,128,128])
    settings.colorize?.amount = 0; XCTAssertEqual(pixel(PictureProcessor.apply(sample(1,0,0),settings:settings)),[255,0,0,255])
    settings.colorize?.amount = 1; settings.colorize?.mode = .spectrum; settings.colorize?.color = "unused"
    XCTAssertNoThrow(try settings.validateEffects())
    let spectrum = pixel(PictureProcessor.apply(sample(0.5,0.5,0.5),settings:settings)); XCTAssertGreaterThan(spectrum[1],120); XCTAssertGreaterThan(spectrum[2],120)
    XCTAssertEqual(pixel(PictureProcessor.apply(sample(0,0,0),settings:settings)),[0,0,0,255])
  }
  func testPortablePNGBakeUsesSameEncodedColorKeySpace() throws {
    try requireCI(); let cg = try XCTUnwrap(context.createCGImage(sample(0,128.0/255,0),from:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:OverlayRenderer.colorSpace))
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]))
    var settings = PictureSettings(); var key = ChromaKeySettings(); key.color = "#008000"; key.colorTolerance = 0.01; key.brightnessTolerance = 0.01; settings.chromaKey = key
    let baked = try PictureProcessor.png(png,settings:settings)
    let result = try XCTUnwrap(NSImage(data:baked)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
    XCTAssertEqual(pixel(PictureProcessor.source(result,settings:nil))[3],0)
  }
  func testEffectPersistenceValidationAndConservativeNativeExport() throws {
    var settings = PictureSettings(); settings.chromaKey = ChromaKeySettings(); settings.colorize = ColorizeSettings()
    XCTAssertEqual(try JSONDecoder().decode(PictureSettings.self,from:JSONEncoder().encode(settings)),settings)
    settings.chromaKey?.color = "bad"; XCTAssertThrowsError(try settings.validateEffects()); settings.chromaKey?.color = "#00FF00"
    var p = RaceProject(); var source = MediaInput(name:"Camera",path:"camera.mov",kind:"video"); source.duration = 5; source.picture = settings; p.inputs = [source]
    var object = DisplayObject(name:"Camera",kind:.video); p.objects = [object]
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    p.inputs[0].picture = nil; object.picture = settings; p.objects = [object]; XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
  func testImageDisplayAndPortableBakeShareEncodedRGBEffects() throws {
    try requireCI()
    let bounds = CGRect(x:0,y:0,width:1,height:1)
    let cg = try XCTUnwrap(context.createCGImage(sample(0.5,0.5,0.5),from:bounds,format:.RGBA8,colorSpace:OverlayRenderer.colorSpace))
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]))
    var settings = PictureSettings(); var tint = ColorizeSettings(); tint.mode = .spectrum; settings.colorize = tint
    var object = DisplayObject(name:"Spectrum",kind:.image); object.artwork = png; object.picture = settings
    let canvas = try XCTUnwrap(CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    XCTAssertTrue(ImageRenderer.draw(canvas,object:object,rect:bounds,data:nil,sourceTime:0,projectTime:0))
    let drawn = pixel(PictureProcessor.source(try XCTUnwrap(canvas.makeImage()),settings:nil))
    let baked = try PictureProcessor.png(png,settings:settings)
    let bakedCG = try XCTUnwrap(NSImage(data:baked)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
    XCTAssertEqual(drawn,pixel(PictureProcessor.source(bakedCG,settings:nil)))
    XCTAssertLessThan(drawn[0],5); XCTAssertGreaterThan(drawn[1],120); XCTAssertGreaterThan(drawn[2],120)
  }
}
