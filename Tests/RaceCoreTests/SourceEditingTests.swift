import AppKit
import XCTest
@testable import RaceCore

final class SourceEditingTests: XCTestCase {
  func testPixelCropEdgesRoundTripAndClampWithoutMovingOppositeEdge() {
    var p = PictureSettings(); p.left = 0.1; p.right = 0.2; p.top = 0.15; p.bottom = 0.25
    var crop = CropSelection(size:CGSize(width:1000,height:1000),picture:p)
    XCTAssertEqual(crop.rect,CGRect(x:100,y:150,width:700,height:600))
    XCTAssertEqual(crop.picture().left,0.1); XCTAssertEqual(crop.picture().bottom,0.25)
    crop.edges(left:-10); XCTAssertEqual(crop.left,0); XCTAssertEqual(crop.right,200)
    crop.edges(right:10000); XCTAssertEqual(crop.rect.width,50)
    crop.nudge(x:-10000,y:10000); XCTAssertEqual(crop.left,0); XCTAssertEqual(crop.bottom,0)
    crop.set(CGRect(x:0,y:0,width:CGFloat.nan,height:20)); XCTAssertTrue(crop.rect.width.isFinite)
  }
  func testCropDragRespectsLetterboxingAndZoomPreservesCenterAndAspect() {
    var crop = CropSelection(size:CGSize(width:1920,height:1080))
    let fit = CropSelection.fit(crop.sourceSize,in:CGSize(width:600,height:400))
    XCTAssertEqual(fit.height,337.5); XCTAssertEqual(fit.minY,31.25)
    crop.drag(from:CGPoint(x:150,y:fit.minY+fit.height/4),to:CGPoint(x:450,y:fit.minY+fit.height*3/4),imageRect:fit)
    XCTAssertEqual(crop.rect,CGRect(x:480,y:270,width:960,height:540))
    crop.zoom(2); XCTAssertEqual(crop.rect,CGRect(x:720,y:405,width:480,height:270))
    crop.zoom(0.5); XCTAssertEqual(crop.rect,CGRect(x:480,y:270,width:960,height:540))
  }
  func testCropRetainsPictureControlsAndMinimumVisibleArea() {
    var p = PictureSettings(); p.rotation = 25; p.hue = -30; p.brightness = 1.2; p.flipX = true
    var crop = CropSelection(size:CGSize(width:1920,height:1080)); crop.zoom(100)
    let edited = crop.picture(from:p)
    XCTAssertEqual(edited.rotation,25); XCTAssertEqual(edited.hue,-30); XCTAssertEqual(edited.brightness,1.2); XCTAssertTrue(edited.flipX)
    XCTAssertGreaterThanOrEqual(crop.rect.width,96); XCTAssertGreaterThanOrEqual(crop.rect.height,54)
    XCTAssertEqual(CropSelection(size:CGSize(width:CGFloat.nan,height:0)).rect,CGRect(x:0,y:0,width:1,height:1))
  }
  func testTrimUsesPhysicalBoundsAndPreservesSyncRateDelayLoopAndMarks() throws {
    var input = MediaInput(name:"Video",path:"/tmp/video.mp4",kind:"video"); input.duration = 20; input.offset = 3
    var timing = InputTiming(); timing.trimStart = 2; timing.trimEnd = 15; timing.rate = 0.5; timing.projectStart = 4; timing.loop = true; input.timing = timing
    var draft = SourceTrimDraft(input:input,duration:20,frameRate:60)
    XCTAssertEqual(draft.start,5); XCTAssertEqual(draft.end,15); XCTAssertEqual(draft.effectiveLength,20)
    XCTAssertEqual(draft.endPreviewTime,15-1.0/60,accuracy:1e-9)
    draft.start = 6; draft.end = 12
    let edited = try draft.applying(to:input)
    XCTAssertEqual(edited.offset,3); XCTAssertEqual(edited.timing?.trimStart,3); XCTAssertEqual(edited.timing?.rate,0.5)
    XCTAssertEqual(edited.timing?.projectStart,4); XCTAssertEqual(edited.timing?.loop,true)
    var project = RaceProject(); project.inputs = [input]; project.rangeStart = 1; project.rangeEnd = 19
    project.inputs[0] = edited
    XCTAssertEqual(project.placements[0].sourceStart,6); XCTAssertEqual(project.placements[0].end-project.placements[0].start,12)
    XCTAssertEqual(project.rangeStart,1); XCTAssertEqual(project.rangeEnd,19)
  }
  func testInvalidTrimCannotOverwriteInputAndUnchangedDraftDoesNotCreateSettings() throws {
    let input = MediaInput(name:"Video",path:"",kind:"video")
    var draft = SourceTrimDraft(input:input,duration:10,frameRate:30)
    XCTAssertNil(try draft.applying(to:input).timing)
    for (start,end) in [(5.0,4.0),(0,11),(0,0),(Double.nan,5)] {
      draft.start = start; draft.end = end; XCTAssertThrowsError(try draft.applying(to:input))
    }
    var aligned = input; aligned.offset = 3
    draft = SourceTrimDraft(input:aligned,duration:10,frameRate:30); draft.start = 2
    XCTAssertThrowsError(try draft.applying(to:aligned))
  }
  func testImageInputCropRendersAndBakesIntoPortableArtworkWithoutDoubleApplication() throws {
    let c = try XCTUnwrap(CGContext(data:nil,width:40,height:20,bitsPerComponent:8,bytesPerRow:160,
      space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    c.setFillColor(OverlayRenderer.color("#E05020")); c.fill(CGRect(x:0,y:0,width:20,height:20))
    c.setFillColor(OverlayRenderer.color("#20A0E0")); c.fill(CGRect(x:20,y:0,width:20,height:20))
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage:try XCTUnwrap(c.makeImage())).representation(using:.png,properties:[:]))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    try png.write(to:file); defer {try? FileManager.default.removeItem(at:file)}
    var input = MediaInput(name:"Artwork",path:file.path,kind:"image",legacyIndex:4)
    var picture = PictureSettings(); picture.right = 0.5; input.picture = picture
    var o = DisplayObject(name:"Picture",kind:.image); o.inputIndex = 4; o.text = file.path; o.x = 0; o.y = 0; o.width = 100; o.height = 100
    var objectPicture = PictureSettings(); objectPicture.maintainAspect = false; o.picture = objectPicture
    var project = RaceProject(); project.width = 160; project.height = 90; project.inputs = [input]; project.objects = [o]
    func render(_ p:RaceProject) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:160,height:90,bitsPerComponent:8,bytesPerRow:640,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[:]),time:0,size:CGSize(width:160,height:90))
      return Data(bytes:try XCTUnwrap(c.data),count:57600)
    }
    let cropped = try render(project)
    project.inputs[0].picture = nil; XCTAssertNotEqual(cropped,try render(project)); project.inputs[0].picture = picture
    var portable = try project.reusableLayout()
    XCTAssertTrue(portable.inputs.isEmpty); XCTAssertEqual(portable.objects[0].text,"")
    XCTAssertEqual(cropped,try render(portable))
    portable.inputs = [input]; XCTAssertEqual(cropped,try render(portable),"An embedded portable image must not inherit an unrelated image source's crop again")
    var segment = ObjectSegment(time:1); segment.inputIndex = 4; project.objects[0].segments = [segment]
    let animated = try project.reusableLayout()
    XCTAssertNotNil(animated.objects[0].segments?.first?.artwork)
  }
}
