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
  func testExportSettingsRoundTripAndQualityRate() throws {
    let settings = ExportSettings(videoBitRate:98_304_000,audioBitRate:240_000)
    XCTAssertEqual(try JSONDecoder().decode(ExportSettings.self,from:JSONEncoder().encode(settings)),settings)
    XCTAssertGreaterThan(ExportSettings().resolvedVideoBitRate(width:3840,height:2160,fps:60000/1001),98_000_000)
  }
}
