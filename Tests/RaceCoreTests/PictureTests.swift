import CoreImage
import XCTest
@testable import RaceCore

final class PictureTests: XCTestCase {
  let context = PictureProcessor.context()
  func pixel(_ image: CIImage) -> [UInt8] {
    var result = [UInt8](repeating:0,count:4)
    result.withUnsafeMutableBytes { bytes in
      context.render(image,toBitmap:bytes.baseAddress!,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:OverlayRenderer.colorSpace)
    }
    return Array(result.prefix(3))
  }
  func requireCoreImage() throws {
    try XCTSkipIf(pixel(sample([255,0,0])) != [255,0,0],"Core Image rendering is unavailable on this host; run media acceptance on a graphics-capable Mac.")
  }
  func sample(_ values: [Double]) -> CIImage {
    CIImage(color:CIColor(red:values[0]/255,green:values[1]/255,blue:values[2]/255)).cropped(to:CGRect(x:0,y:0,width:1,height:1))
  }
  func testNativePictureControlReferenceSamples() throws {
    try requireCoreImage()
    // RGB triples observed in the native app's neutral and adjusted BMP snapshots.
    // No reference artwork or footage is needed by the test.
    let source = sample([110,167,236])
    for (controls,expected) in [([0.9,1,1],[99,150,212]),([1,1.1,1],[109,171,246]),
      ([1,1,1.25],[78,149,236]),([0.9,1.1,1.25],[65,134,220])] {
      var settings = PictureSettings();settings.brightness = controls[0];settings.contrast = controls[1];settings.saturation = controls[2]
      let actual = pixel(PictureProcessor.apply(source,settings:settings))
      for i in 0..<3 { XCTAssertEqual(Double(actual[i]),Double(expected[i]),accuracy:2) }
    }
  }
  func testLegacyDecoderMatrixPreservesGrayAndMatches709Reference() throws {
    try requireCoreImage()
    let gray = pixel(PictureProcessor.legacy601(sample([128,128,128])))
    XCTAssertEqual(gray,[128,128,128])
    let rgb = pixel(PictureProcessor.legacy601(sample([104,167,242])))
    for (value,expected) in zip(rgb,[110,169,239]) { XCTAssertEqual(Double(value),Double(expected),accuracy:2) }
  }
  func testHueRotatesColorsAndPreservesGray() throws {
    try requireCoreImage()
    var settings = PictureSettings(); settings.hueAdjustment = 120
    XCTAssertEqual(pixel(PictureProcessor.apply(sample([255,0,0]), settings: settings)), [0,255,0])
    settings.hueAdjustment = -120
    XCTAssertEqual(pixel(PictureProcessor.apply(sample([255,0,0]), settings: settings)), [0,0,255])
    XCTAssertEqual(pixel(PictureProcessor.apply(sample([128,128,128]), settings: settings)), [128,128,128])
    settings.hueAdjustment = 0
    XCTAssertEqual(pixel(PictureProcessor.apply(sample([110,167,236]), settings: settings)), [110,167,236])
  }
  func testSharpnessChangesEdgesWithoutResizingOrTransparentBorders() throws {
    try requireCoreImage()
    let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
    let background = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: extent)
    let foreground = CIImage(color: CIColor(red: 0.75, green: 0.75, blue: 0.75)).cropped(to: CGRect(x: 16, y: 0, width: 16, height: 32))
    let source = foreground.composited(over: background)
    func at(_ image: CIImage, x: Double) -> [UInt8] {
      pixel(image.transformed(by: CGAffineTransform(translationX: -x, y: -16)))
    }
    var s = PictureSettings(); s.sharpnessAdjustment = -100
    let blurred = PictureProcessor.apply(source, settings: s)
    XCTAssertEqual(blurred.extent, extent)
    XCTAssertGreaterThan(at(blurred, x: 15)[0], at(source, x: 15)[0])
    XCTAssertLessThan(at(blurred, x: 16)[0], at(source, x: 16)[0])
    XCTAssertEqual(at(blurred, x: 0), at(source, x: 0))
    s.sharpnessAdjustment = 100
    let sharp = PictureProcessor.apply(source, settings: s)
    XCTAssertEqual(sharp.extent, extent)
    XCTAssertLessThan(at(sharp, x: 15)[0], at(source, x: 15)[0])
    XCTAssertGreaterThan(at(sharp, x: 16)[0], at(source, x: 16)[0])
    s.sharpnessAdjustment = 0
    XCTAssertEqual(at(PictureProcessor.apply(source, settings: s), x: 15), at(source, x: 15))
  }
  func testExportSettingsRoundTripAndQualityRate() throws {
    let settings = ExportSettings(videoBitRate:98_304_000,audioBitRate:240_000)
    XCTAssertEqual(try JSONDecoder().decode(ExportSettings.self,from:JSONEncoder().encode(settings)),settings)
    XCTAssertGreaterThan(ExportSettings().resolvedVideoBitRate(width:3840,height:2160,fps:60000/1001),98_000_000)
  }
}
