import AppKit
import CoreImage
import XCTest
@testable import RaceCore

final class ColorChannelTests:XCTestCase {
  func canvas(_ info:UInt32 = OverlayRenderer.bitmapInfo) -> CGContext {
    CGContext(data:nil,width:16,height:8,bitsPerComponent:8,bytesPerRow:0,space:OverlayRenderer.colorSpace,bitmapInfo:info)!
  }
  func pixel(_ c:CGContext,_ x:Int = 8,_ y:Int = 4) throws -> [Double] {
    c.flush()
    let bytes = c.data!.assumingMemoryBound(to:UInt8.self)
    let offset = y*c.bytesPerRow+x*4
    let positions = c.bitmapInfo.contains(.byteOrder32Little) ? [2,1,0,3] : [0,1,2,3]
    return positions.map{Double(bytes[offset+$0])}
  }
  func testWriteMaskKeepsUnderlyingChannelsWithOpacityAndAllDisabled() throws {
    for info in [OverlayRenderer.bitmapInfo,CGImageAlphaInfo.premultipliedLast.rawValue] {
      let c = canvas(info);c.setFillColor(OverlayRenderer.color("#336699"));c.fill(CGRect(x:0,y:0,width:16,height:8))
      RGBChannelCompositor.draw(c,mask:RGBWriteMask(bits:1)) {
        c.saveGState();c.setAlpha(0.5);c.setFillColor(OverlayRenderer.color("#CC4D1A"));c.fill(CGRect(x:0,y:0,width:16,height:8));c.restoreGState()
      }
      let result = try pixel(c)
      XCTAssertEqual(result[0],128,accuracy:2);XCTAssertEqual(result[1],102,accuracy:1);XCTAssertEqual(result[2],153,accuracy:1)
      var called = false;RGBChannelCompositor.draw(c,mask:RGBWriteMask(bits:0)){called = true}
      XCTAssertFalse(called);XCTAssertEqual(try pixel(c),result)
    }
  }
  func testWidgetMaskTimelineInheritanceAndPortableTemplate() throws {
    var p = RaceProject();p.width = 16;p.height = 8
    var background = DisplayObject(name:"Base",kind:.shape);background.shape = ShapeSettings();background.x = 0;background.y = 0;background.width = 100;background.height = 100;background.color = "#336699"
    var top = background;top.id = UUID();top.name = "Mask";top.color = "#CC4D1A";top.colorChannels = RGBWriteMask(bits:1)
    var end = top;end.colorChannels = nil;top.editSegment(at:1,from:top,to:end)
    p.objects = [background,top]
    for (time,expected) in [(0.0,[204.0,102,153]),(1.0,[204.0,77,26])] {
      let c = canvas();OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[:]),time:time,size:CGSize(width:16,height:8))
      let actual = try pixel(c);for i in 0..<3 {XCTAssertEqual(actual[i],expected[i],accuracy:2)}
    }
    XCTAssertTrue(top.segments![0].overrides(.colorChannels))
    var inherited = top.segments![0];inherited.setOverride(.colorChannels,enabled:false,value:end)
    XCTAssertFalse(inherited.overrides(.colorChannels))
    let layout = try p.reusableLayout();XCTAssertEqual(layout.objects[1].colorChannels?.bits,1)
    XCTAssertEqual(try JSONDecoder().decode(RaceProject.self,from:JSONEncoder().encode(p)).objects[1].segments,top.segments)
  }
  func testVerifiedBaseLegacyMaskAndOldNativeMigration() throws {
    var p = RaceProject();var o = DisplayObject(name:"Mask",kind:.shape);o.shape = ShapeSettings();o.colorChannels = RGBWriteMask(bits:6);p.objects = [o]
    for format in [LegacyWriter.Format.rrp,.rrt,.rro] {
      let bytes = try LegacyWriter.data(p,format:format)
      let decoded = try format == .rrp ? LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp")) : format == .rrt ? LegacyReader.template(bytes) : LegacyReader.style(bytes)
      XCTAssertEqual(decoded.objects[0].colorChannels?.bits,6)
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp");defer {try? FileManager.default.removeItem(at:file)}
    p.colorChannelVersion = nil;p.objects[0].colorChannels = nil
    p.objects[0].legacyCommon = Data(repeating:0,count:344);p.objects[0].legacyCommon?[288] = 1
    try p.save(file);var reopened = try RaceProject.read(file);XCTAssertEqual(reopened.objects[0].colorChannels?.bits,1)
    reopened.objects[0].colorChannels = nil;try reopened.save(file);XCTAssertNil(try RaceProject.read(file).objects[0].colorChannels)
    var value = o;value.colorChannels = RGBWriteMask(bits:1);o.editSegment(at:1,from:o,to:value);p.objects = [o]
    let events = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(events.objects[0].resolved(at:1).colorChannels?.bits,1)
  }
  func testStereoPairPreservesSessionAndValidatesWithoutPartialMutation() throws {
    var p = RaceProject();p.rangeStart = 1;p.rangeEnd = 8
    var a = MediaInput(name:"Left",path:"/tmp/left.mp4",kind:"video",legacyIndex:4);a.duration = 10;a.offset = 0.25
    var b = a;b.id = UUID();b.legacyIndex = 9;b.name = "Right";p.inputs = [a,b]
    p.objects = [DisplayObject(name:"HUD",kind:.speed)]
    let before = p;XCTAssertThrowsError(try p.addStereoPair(left:4,right:4,layout:.redCyan));XCTAssertEqual(p,before)
    try p.addStereoPair(left:4,right:9,layout:.redCyan,convergence:2)
    XCTAssertEqual(p.objects.map{$0.colorChannels?.bits},[6,1,nil]);XCTAssertEqual(p.objects[1].x,-1)
    XCTAssertEqual(p.objects[0].audio?.volume,0);XCTAssertEqual(p.inputs,before.inputs);XCTAssertEqual(p.rangeStart,1);XCTAssertEqual(p.rangeEnd,8)
    var cross = before;try cross.addStereoPair(left:4,right:9,layout:.cross)
    XCTAssertEqual(cross.objects[1].x,50);XCTAssertEqual(cross.objects[0].x,0);XCTAssertEqual(cross.objects[1].width,50)
    let layout = try p.reusableLayout();XCTAssertTrue(layout.inputs.allSatisfy{$0.path.isEmpty})
    XCTAssertEqual(layout.objects[1].colorChannels?.bits,1)
  }
  func testNativeObservedDisplayBytesAndTimelineFlags() throws {
    var common = Data(repeating:0,count:344);common[280] = 10;common[284] = 0;common[286] = 50;common[287] = 1;common[288] = 1
    let original = LegacyReader.decodeCommon(common,at:0,legacyIndex:0)
    XCTAssertEqual(original.opacity,0.5);XCTAssertEqual(original.picture?.flipX,true);XCTAssertEqual(original.picture?.flipY,false)
    var p = RaceProject();p.inputs = [MediaInput(name:"L",path:"/tmp/l.mp4",kind:"video",legacyIndex:0),MediaInput(name:"R",path:"/tmp/r.mp4",kind:"video",legacyIndex:1)]
    var o = DisplayObject(name:"Native",kind:.video);o.inputIndex = 0;o.opacity = 0.5;o.picture = PictureSettings();o.picture?.flipX = true;o.colorChannels = RGBWriteMask(bits:1)
    var next = o;next.opacity = 0.75;next.picture?.flipX = false;next.picture?.flipY = true;next.picture?.maintainAspect = false;next.inputIndex = 1;next.colorChannels = RGBWriteMask(bits:3);next.style = "Probe"
    o.editSegment(at:1,from:o,to:next);p.objects = [o]
    let record = try LegacyWriter.timeline(o,sources:[0:0,1:1],parents:[:])[0]
    XCTAssertEqual(record.u32(4),1|16|64|128|256|512)
    XCTAssertEqual(record[153],1);XCTAssertEqual(record[155],0);XCTAssertEqual(record[156],25);XCTAssertEqual(record[157],2);XCTAssertEqual(record[158],3)
    var third = next;third.picture?.maintainAspect = true;o.editSegment(at:2,from:next,to:third);p.objects = [o]
    let reopened = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    let event = reopened.objects[0].resolved(at:1)
    XCTAssertEqual(event.inputIndex,1);XCTAssertEqual(event.opacity,0.75);XCTAssertEqual(event.picture?.flipY,true);XCTAssertEqual(event.picture?.maintainAspect,false);XCTAssertEqual(event.style,"Probe");XCTAssertEqual(event.colorChannels?.bits,3)
    XCTAssertEqual(reopened.objects[0].resolved(at:2).picture?.maintainAspect,true)
  }
  func testOldNativeDisplayRepairRunsOnceAndPreservesLaterEdits() throws {
    var p = RaceProject();p.legacyDisplayControlsVersion = nil
    var object = DisplayObject(name:"Earlier import",kind:.video);object.picture = PictureSettings()
    var common = Data(repeating:0,count:344);common[286] = 50;common[287] = 1;common[288] = 7
    object.legacyCommon = common;p.objects = [object]
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp");defer {try? FileManager.default.removeItem(at:file)}
    try p.save(file);var repaired = try RaceProject.read(file)
    XCTAssertEqual(repaired.objects[0].opacity,0.5);XCTAssertEqual(repaired.objects[0].picture?.flipX,true)
    repaired.objects[0].opacity = 1;repaired.objects[0].picture?.flipX = false
    try repaired.save(file);let edited = try RaceProject.read(file)
    XCTAssertEqual(edited.objects[0].opacity,1);XCTAssertEqual(edited.objects[0].picture?.flipX,false)
  }
}
