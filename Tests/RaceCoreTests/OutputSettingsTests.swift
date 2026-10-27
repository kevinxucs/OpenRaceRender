import AVFoundation
import XCTest
@testable import RaceCore

final class OutputSettingsTests:XCTestCase {
  func testOldSettingsDecodeAndNewSettingsUseIndependentEncoderSizeAndClock() throws {
    let old = try JSONDecoder().decode(ExportSettings.self,from:Data("{\"videoBitRate\":1000000,\"audioBitRate\":128000}".utf8))
    XCTAssertNil(old.output); XCTAssertNil(old.profileID); XCTAssertEqual(old.audioBitRate,128000)
    var p = RaceProject(); p.width = 3840; p.height = 2160; p.fps = 60
    var output = OutputSettings(); output.width = 640; output.height = 480; output.fps = 24; output.audioChannels = 1; output.audioSampleRate = 44100; output.border = 0.05
    var settings = ExportSettings(); settings.output = output; p.exportSettings = settings
    try settings.validate(project:p)
    let video = settings.videoSettings(project:p)
    XCTAssertEqual(video[AVVideoWidthKey] as? Int,640); XCTAssertEqual(video[AVVideoHeightKey] as? Int,480)
    let compression = try XCTUnwrap(video[AVVideoCompressionPropertiesKey] as? [String:Any])
    XCTAssertEqual(compression[AVVideoExpectedSourceFrameRateKey] as? Double,24)
    XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int,2_000_000)
    XCTAssertEqual(p.width,3840); XCTAssertEqual(p.height,2160); XCTAssertEqual(p.fps,60)
    XCTAssertEqual(PreviewSettings().options(for:p).size,CGSize(width:1280,height:720))
    XCTAssertEqual(try JSONDecoder().decode(ExportSettings.self,from:JSONEncoder().encode(settings)),settings)
  }
  func testViewportFitsOrReshapesEntireCanvasWithinBorder() throws {
    var p = RaceProject(); p.width = 1920; p.height = 1080
    var output = OutputSettings(); output.width = 640; output.height = 480; output.border = 0.05
    var options = try output.renderOptions(project:p)
    var rect = options.viewport(project:p,size:CGSize(width:640,height:480))
    XCTAssertEqual(rect.minX,32,accuracy:1e-9); XCTAssertEqual(rect.minY,78,accuracy:1e-9)
    XCTAssertEqual(rect.width,576,accuracy:1e-9); XCTAssertEqual(rect.height,324,accuracy:1e-9)
    output.workspace = .output; options = try output.renderOptions(project:p)
    rect = options.viewport(project:p,size:CGSize(width:640,height:480))
    XCTAssertEqual(rect,CGRect(x:32,y:24,width:576,height:432))
    output.audioChannels = 0; XCTAssertEqual(try output.renderOptions(project:p).audio,.disabled)
  }
  func testInvalidOutputIsRejectedBeforeMediaAndCreatesNoFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    var p = RaceProject(),settings = ExportSettings(),output = OutputSettings()
    output.width = 641; settings.output = output; p.exportSettings = settings
    XCTAssertThrowsError(try settings.validate(project:p))
    do {try await VideoExporter().export(scene:RenderScene(project:p,telemetry:[:]),to:root,start:0,duration:1); XCTFail("Invalid output accepted")} catch {XCTAssertTrue(error.localizedDescription.contains("even dimensions"))}
    XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    output.width = 640; output.height = 480; output.border = .nan; settings.output = output; XCTAssertThrowsError(try settings.validate(project:p))
    output.border = 0.05; output.audioChannels = 3; settings.output = output; XCTAssertThrowsError(try settings.validate(project:p))
    output.audioChannels = 2; output.audioSampleRate = 22050; settings.output = output; XCTAssertThrowsError(try settings.validate(project:p))
  }
  func testPresetsAndNativePersistenceKeepOutputAndTemplatesRemoveIt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer {try? FileManager.default.removeItem(at:root)}
    var p = RaceProject(); p.objects = [DisplayObject(name:"Label",kind:.text)]; p.rangeStart = 2; p.rangeEnd = 5
    for profile in OutputProfile.builtins {try profile.settings.validate(project:p)}
    let tv = try XCTUnwrap(OutputProfile.builtins.first{$0.id == "television-1080"})
    XCTAssertEqual(tv.settings.output?.border,0.05)
    p.exportSettings = tv.settings; p.exportSettings?.profileID = tv.id
    try p.save(root); XCTAssertEqual(try RaceProject.read(root).exportSettings,p.exportSettings)
    XCTAssertNil(try p.reusableLayout().exportSettings); XCTAssertEqual(p.rangeStart,2); XCTAssertEqual(p.rangeEnd,5)
  }
}
