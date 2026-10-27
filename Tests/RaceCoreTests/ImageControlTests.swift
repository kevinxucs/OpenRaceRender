import AppKit
import XCTest
@testable import RaceCore

final class ImageControlTests: XCTestCase {
  func settings() -> ImageControlSettings { var s = ImageControlSettings(); s.mode = .proportional; return s }
  func artwork() throws -> Data {
    let c = try XCTUnwrap(CGContext(data:nil,width:40,height:40,bitsPerComponent:8,bytesPerRow:160,
      space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    c.setFillColor(OverlayRenderer.color("#FF4400")); c.fill(CGRect(x:0,y:0,width:20,height:40))
    c.setFillColor(OverlayRenderer.color("#00AAFF")); c.fill(CGRect(x:20,y:0,width:20,height:20))
    return try XCTUnwrap(NSBitmapImageRep(cgImage:try XCTUnwrap(c.makeImage())).representation(using:.png,properties:[:]))
  }
  func fixture() throws -> RaceProject {
    var p = RaceProject(); p.width = 320; p.height = 180; p.explicitDuration = 2
    var o = DisplayObject(name:"Data image",kind:.image); o.inputIndex = 9; o.channel = "Speed"
    o.x = 10; o.y = 10; o.width = 30; o.height = 50; o.artwork = try artwork(); o.imageControl = settings()
    p.inputs = [MediaInput(name:"Logger",path:"",kind:"data",legacyIndex:9)]; p.inputs[0].duration = 2
    p.objects = [o]; return p
  }
  func testMappingClampsAndReversesRangesAndUsesInclusiveThresholds() throws {
    var s = settings()
    XCTAssertEqual(s.mappedValue(-1),0); XCTAssertEqual(s.mappedValue(50),50); XCTAssertEqual(s.mappedValue(101),100)
    s.outputMinimum = 100; s.outputMaximum = 0; XCTAssertEqual(s.mappedValue(25),75)
    s.inputMinimum = 100; s.inputMaximum = 0; XCTAssertEqual(s.mappedValue(25),25)
    s.mode = .greaterOrEqual; s.inputMaximum = 50
    XCTAssertEqual(s.mappedValue(49),100); XCTAssertEqual(s.mappedValue(50),0)
    s.mode = .lessOrEqual; s.inputMinimum = 20
    XCTAssertEqual(s.mappedValue(20),0); XCTAssertEqual(s.mappedValue(21),100)
    s.inputMinimum = .nan; XCTAssertNil(s.mappedValue(20)); XCTAssertNil(s.mappedValue(nil)); XCTAssertNil(s.mappedValue(.infinity))
  }
  func testOutputsMissingDataAndFlashingAreDeterministic() {
    var s = settings(); s.pulseInterval = 0.5
    let state = ImageControlState.resolve(s,value:50,sourceAvailable:true,projectTime:0.25)
    XCTAssertEqual(state.opacity,0.5); XCTAssertTrue(state.visible)
    XCTAssertFalse(ImageControlState.resolve(s,value:50,sourceAvailable:true,projectTime:0.5).visible)
    XCTAssertTrue(ImageControlState.resolve(s,value:50,sourceAvailable:true,projectTime:1).visible)
    XCTAssertFalse(ImageControlState.resolve(s,value:50,sourceAvailable:false,projectTime:1).visible)
    for (output,expected) in [(ImageControlSettings.Output.rotation,50.0),(.brightness,0.5),(.hue,50)] {
      s.output = output
      let v = ImageControlState.resolve(s,value:50,sourceAvailable:true,projectTime:0)
      XCTAssertEqual(output == .rotation ? v.rotation : output == .brightness ? v.brightness : v.hue,expected)
    }
    s.output = .visibility; XCTAssertTrue(ImageControlState.resolve(s,value:50,sourceAvailable:true,projectTime:0).visible)
    XCTAssertFalse(ImageControlState.resolve(s,value:49,sourceAvailable:true,projectTime:0).visible)
    s.mode = .simple; XCTAssertTrue(ImageControlState.resolve(s,value:nil,sourceAvailable:false,projectTime:0).visible)
    XCTAssertTrue(s.isPulseOn(at:1e20)); s.pulseInterval = .nan; XCTAssertTrue(s.isPulseOn(at:0.75))
  }
  func testPixelsCombineGroupOpacityOnceAndChangeForAllImageEffects() throws {
    var p = try fixture(); let d = try Telemetry(text:"Time,Speed\n0,0\n1,50\n2,100")
    func render(_ project:RaceProject, _ time:Double = 1) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:320,height:180,bitsPerComponent:8,bytesPerRow:1280,
        space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      OverlayRenderer.draw(c,scene:RenderScene(project:project,telemetry:[9:d]),time:time,size:CGSize(width:320,height:180))
      return Data(bytes:try XCTUnwrap(c.data),count:230400)
    }
    p.objects[0].opacity = 0.5
    var group = DisplayObject(name:"Group",kind:.group); group.opacity = 0.5
    p.objects[0].parentID = group.id; p.objects.append(group)
    let original = try render(p)
    let alpha = stride(from:3,to:original.count,by:4).map { original[$0] }.max()!
    XCTAssertEqual(Double(alpha),32,accuracy:1)
    for output in [ImageControlSettings.Output.rotation,.brightness,.hue] {
      p.objects[0].imageControl?.output = output
      XCTAssertNotEqual(original,try render(p)); XCTAssertEqual(try render(p),try render(p))
    }
    p.objects[0].imageControl?.pulseInterval = 0.5
    XCTAssertTrue(try render(p,0.75).allSatisfy { $0 == 0 })
    p.objects[0].imageControl?.mode = .simple
    XCTAssertFalse(try render(p,1).allSatisfy { $0 == 0 })
  }
  func testAuthoredImagesRoundTripWithBoundedArtworkAndAllVerifiedMappings() throws {
    var p = try fixture()
    for output in [ImageControlSettings.Output.opacity,.rotation,.brightness,.hue] {
      p.objects[0].imageControl?.output = output; p.objects[0].imageControl?.pulseInterval = 0.3
      for mode in [ImageControlSettings.Mode.simple,.proportional,.greaterOrEqual,.lessOrEqual] {
        p.objects[0].imageControl?.mode = mode
        let result = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
        XCTAssertEqual(result.objects[0].imageControl,p.objects[0].imageControl)
        XCTAssertNotNil(result.objects[0].artwork)
        XCTAssertEqual(result.objects[0].inputIndex,mode == .simple ? 255 : 0)
        XCTAssertEqual(result.objects[0].channel,"Speed")
      }
    }
    p.objects[0].imageControl?.output = .visibility
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    p.objects[0].imageControl?.output = .opacity; p.objects[0].imageControl?.pulseInterval = 0.15
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
  func testImageContainerRejectsBadPrefixAndPreservesFollowingObjects() throws {
    var p = try fixture(); p.objects[0].imageControl?.mode = .simple
    var text = DisplayObject(name:"After image",kind:.text); text.text = "Still here"; p.objects.append(text)
    let bytes = try LegacyWriter.data(p,format:.rrp)
    let decoded = try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.objects.map(\.name),["Data image","After image"])
    var cursor = 0
    XCTAssertThrowsError(try LegacyProjectSettings.image(Data([100,0,0,0,8,0,1,0,1,0,32,0]),cursor:&cursor))
  }
  func testTemplatesRetainMappedRolesAndArtworkButDropStaticImageInput() throws {
    var p = try fixture()
    p.inputs.insert(MediaInput(name:"Artwork file",path:"/private/pointer.png",kind:"image",legacyIndex:4),at:0)
    p.objects[0].imageControl?.mode = .simple; p.objects[0].inputIndex = 4
    XCTAssertTrue(try p.reusableLayout().inputs.isEmpty)
    var edit = p.objects[0]; edit.imageControl?.mode = .proportional; edit.inputIndex = 9
    p.objects[0].editSegment(at:1,from:p.objects[0],to:edit)
    let layout = try p.reusableLayout()
    XCTAssertEqual(layout.inputs.map(\.legacyIndex),[9]); XCTAssertNotNil(layout.objects[0].artwork)
    var next = RaceProject(); next.inputs = [MediaInput(name:"New logger",path:"",kind:"data",legacyIndex:88)]
    next.applyLayout(layout,replace:true,mapping:[9:88])
    XCTAssertEqual(next.objects[0].resolved(at:1).inputIndex,88)
    XCTAssertEqual(next.objects[0].resolved(at:1).imageControl,edit.imageControl)
  }
  func testMappedImagesValidateTelemetryAndSettingsPersistThroughNativeAndLegacyStyles() throws {
    var p = try fixture()
    XCTAssertThrowsError(try p.validateExportAssets(start:0,duration:1))
    p.objects[0].imageControl?.mode = .simple
    XCTAssertNoThrow(try p.validateExportAssets(start:0,duration:1))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    p.objects[0].imageControl?.mode = .proportional
    for ext in ["orrt","rrt","rro"] {
      let file = root.appendingPathComponent("image."+ext)
      if ext == "orrt" { try p.save(file) } else { try LegacyWriter.data(p,format:ext == "rrt" ? .rrt : .rro).write(to:file) }
      let reopened = try RaceProject.read(file)
      XCTAssertEqual(reopened.objects[0].imageControl,p.objects[0].imageControl)
      XCTAssertNotNil(reopened.objects[0].artwork)
    }
    var changed = p.objects[0]; changed.imageControl?.output = .rotation
    p.objects[0].editSegment(at:1,from:p.objects[0],to:changed)
    let file = root.appendingPathComponent("image.orrp"); try p.save(file)
    XCTAssertEqual(try RaceProject.read(file).objects[0].resolved(at:1).imageControl,changed.imageControl)
  }
}
