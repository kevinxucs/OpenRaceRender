import AVFoundation
import CoreImage
import XCTest
@testable import RaceCore

final class PreviewSettingsTests:XCTestCase {
  func testIndependentCapsAspectFrameClockAndSeekRestoration() throws {
    var project = RaceProject(); project.width = 3840; project.height = 2160; project.fps = 60000.0/1001
    let before = project; var settings = PreviewSettings()
    let regular = settings.options(for:project)
    XCTAssertEqual(regular.size,CGSize(width:1280,height:720)); XCTAssertEqual(regular.fps,30)
    let seeking = settings.options(for:project,seeking:true)
    XCTAssertEqual(seeking.size,CGSize(width:640,height:360)); XCTAssertEqual(seeking.fps,15); XCTAssertEqual(seeking.scaling,.nearest)
    XCTAssertEqual(settings.options(for:project),regular); XCTAssertEqual(project,before)
    settings.reduceWhileSeeking = false; XCTAssertEqual(settings.options(for:project,seeking:true),regular)
    settings.height = 0; settings.fps = 0
    XCTAssertEqual(settings.options(for:project).size,CGSize(width:3840,height:2160)); XCTAssertEqual(settings.options(for:project).fps,project.fps)
    project.width = 1080; project.height = 1920; project.fps = 24; settings = PreviewSettings()
    XCTAssertEqual(settings.options(for:project).size,CGSize(width:406,height:720)); XCTAssertEqual(settings.options(for:project).fps,24)
    settings.height = 17; XCTAssertThrowsError(try settings.validate())
    XCTAssertEqual(settings.options(for:project),PreviewSettings().options(for:project))
    var invalid = RenderOptions(); invalid.size = CGSize(width:Double.nan,height:10); XCTAssertThrowsError(try invalid.validate())
    invalid.size = nil; invalid.audioSampleRate = 123; XCTAssertThrowsError(try invalid.validate())
    settings = PreviewSettings(); settings.audioBits = 8; settings.audio = .mono; settings.audioSampleRate = 22050
    XCTAssertEqual(try JSONDecoder().decode(PreviewSettings.self,from:JSONEncoder().encode(settings)),settings)
  }
  func testNearestAndLinearAreDistinctAndKeepGeometry() throws {
    let context = PictureProcessor.context(),bounds = CGRect(x:0,y:0,width:2,height:2)
    let red = CIImage(color:CIColor(red:1,green:0,blue:0)).cropped(to:CGRect(x:0,y:0,width:1,height:2))
    let blue = CIImage(color:CIColor(red:0,green:0,blue:1)).cropped(to:bounds)
    let original = red.composited(over:blue)
    func pixels(_ quality:RenderOptions.Scaling) throws -> Data {
      let target = CGRect(x:0,y:0,width:10,height:10)
      let scaled = PictureProcessor.positioned(original,in:target,opacity:1,input:nil,object:nil,scaling:quality)
      XCTAssertEqual(scaled.extent,target)
      var data = Data(count:400)
      data.withUnsafeMutableBytes { context.render(scaled,toBitmap:$0.baseAddress!,rowBytes:40,bounds:target,format:.RGBA8,colorSpace:OverlayRenderer.colorSpace) }
      return data
    }
    let nearest = try pixels(.nearest),linear = try pixels(.linear)
    try XCTSkipIf(nearest.allSatisfy{$0 == 0},"Core Image unavailable on this host.")
    XCTAssertNotEqual(nearest,linear)
    for x in 1...8 { let offset = (5*10+x)*4; XCTAssertEqual(nearest[offset],x < 5 ? 255 : 0); XCTAssertEqual(nearest[offset+2],x < 5 ? 0 : 255) }
    XCTAssertGreaterThan(linear[(5*10+4)*4+2],0)
  }
  func testAudioPreviewPrecisionClampsAndQuantizes() {
    XCTAssertEqual(AudioProcessing.quantize(0.12345,bits:0),0.12345)
    XCTAssertEqual(AudioProcessing.quantize(0.12345,bits:8),16.0/128)
    XCTAssertEqual(AudioProcessing.quantize(0.12345,bits:16),4045.0/32768)
    XCTAssertEqual(AudioProcessing.quantize(2,bits:8),127.0/128)
    XCTAssertEqual(AudioProcessing.quantize(-2,bits:8),-1)
  }
}
