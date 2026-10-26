import AppKit
import XCTest
@testable import RaceCore

final class LegacyWriterTests: XCTestCase {
  func project() -> RaceProject {
    var p = RaceProject(); p.name = "Writer acceptance"; p.notes = "Native authored — no original RRP bytes"
    var video = MediaInput(name:"Camera",path:"/tmp/camera.mp4",kind:"video",legacyIndex:7)
    video.duration = 90; video.offset = -2
    var t = InputTiming(); t.trimStart = 1.5; t.trimEnd = 80; t.projectStart = 3; t.rate = 0.5; t.loop = true
    video.timing = t
    var a = AudioSettings(); a.routing = .swap; a.balance = -0.25
    video.audio = a; video.volume = 0.75
    var picture = PictureSettings(); picture.brightness = 0.7; picture.contrast = 1.2; picture.hue = -30; picture.rotation = 15; picture.flipX = true
    video.picture = picture
    var data = MediaInput(name:"Logger",path:"/tmp/log.csv",kind:"data",legacyIndex:12); data.duration = 90
    var s = DataSettings(); s.assignments = ["time":"Elapsed", "rpm":"Engine", "speed":"GPS speed"]
    s.timeUnitsPerSecond = 1000; s.speedMultiplier = 3.6; s.gearAdjustment = -1; s.interpolate = false
    var calc = CalculatedField(); calc.name = "Scaled"; calc.source = "Engine"; calc.multiply = 2; s.fields = [calc]
    data.dataSettings = s; p.inputs = [data,video]
    var v = DisplayObject(name:"Picture",kind:.video); v.inputIndex = 7; v.width = 100; v.height = 100
    var text = DisplayObject(name:"Caption 日本語",kind:.text); text.text = "Writer ✓"; text.typography = TextSettings()
    text.typography?.alignment = .center; text.typography?.bold = true; text.typography?.outline = true
    var shape = DisplayObject(name:"Outline",kind:.shape); shape.shape = ShapeSettings(); shape.shape?.kind = .ellipse
    shape.shape?.stroke = true; shape.shape?.strokeWidth = 9; shape.shape?.gradient = true
    p.objects = [v,shape,text]; p.rangeStart = 5; p.rangeEnd = 30; p.lengthInputIndex = 7
    return p
  }
  func testNativeAuthoredProjectWritesRecordsWithoutLegacyBytesAndRemapsInputs() throws {
    let p = project(), b = try LegacyWriter.data(p,format:.rrp)
    XCTAssertEqual(b.u32(4),20191031); XCTAssertEqual(b.u32(8),20161216)
    XCTAssertEqual(b[2152+2216+11312+2216+43],255,"Neutral new video records must disable the black color tint in RaceRender")
    let decoded = try LegacyReader.project(b,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.notes,p.notes); XCTAssertEqual(decoded.rangeStart,5); XCTAssertEqual(decoded.rangeEnd,30)
    XCTAssertEqual(decoded.lengthInputIndex,1); XCTAssertEqual(decoded.objects.map(\.name),p.objects.map(\.name))
    XCTAssertEqual(decoded.objects[0].inputIndex,1)
    XCTAssertEqual(decoded.objects[1].shape?.kind,.ellipse); XCTAssertEqual(decoded.objects[1].shape?.strokeWidth,4)
    XCTAssertEqual(decoded.objects[2].text,"Writer ✓"); XCTAssertEqual(decoded.objects[2].typography?.alignment,.center)
    let video = decoded.inputs[1]
    XCTAssertEqual(video.offset,1.5); XCTAssertEqual(video.timing?.projectStart,7); XCTAssertEqual(video.timing?.rate,0.5)
    XCTAssertEqual(video.timing?.loop,true); XCTAssertEqual(video.volume,0.75); XCTAssertEqual(video.audio?.routing,.swap)
    XCTAssertEqual(video.picture?.hue,-30); XCTAssertEqual(video.picture?.contrast ?? 0,1.2,accuracy:0.0001)
    XCTAssertEqual(decoded.inputs[0].dataSettings?.assignments,p.inputs[0].dataSettings?.assignments)
    XCTAssertEqual(decoded.inputs[0].dataSettings?.fields.first?.multiply,2)
    XCTAssertEqual(try LegacyWriter.input(255,sources:[255:2]),2,"A sparse native ID is remapped before treating an absent legacy 255 as unassigned")
    // Export folds trim + offset into RR's source-start and delay fields, preserving the clock.
    XCTAssertEqual(p.placements.first(where:{$0.rootIndex == 7})?.sourceTime(at:9),decoded.placements.first(where:{$0.rootIndex == 1})?.sourceTime(at:9))
  }
  func testTimelineRoundTripsCommonPayloadAndAudioChanges() throws {
    var p = project(), segment = ObjectSegment(time:4)
    segment.x = 32; segment.opacity = 0.5; segment.text = "Changed at four seconds"
    p.objects[2].segments = [segment]; p.objects[2].end = 8
    var mute = ObjectSegment(time:2); mute.audio = AudioSettings(); mute.audio?.volume = 0
    mute.inputIndex = 7; mute.visible = false; p.objects[0].segments = [mute]
    let decoded = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.objects[2].resolved(at:5).text,segment.text)
    XCTAssertEqual(decoded.objects[2].resolved(at:5).x,32); XCTAssertEqual(decoded.objects[2].resolved(at:5).opacity,0.5)
    XCTAssertFalse(decoded.objects[2].resolved(at:9).visible)
    XCTAssertEqual(decoded.objects[0].resolved(at:3).audio?.volume,0)
    XCTAssertFalse(decoded.objects[0].resolved(at:3).visible)
  }
  func testTemplateAndStyleIntegrityAndUnicodeArtworkBoundaries() throws {
    var p = project(); p.inputs[0].kind = "audio"; p.objects.removeFirst()
    p.objects[0].artwork = try pixel()
    let template = try LegacyWriter.data(p,format:.rrt,seed:0xbe87390a)
    XCTAssertEqual(template.u32(64817),136)
    let decoded = try LegacyReader.template(template)
    XCTAssertEqual(decoded.objects.map(\.name),p.objects.map(\.name)); XCTAssertEqual(decoded.inputs[0].kind,"audio")
    XCTAssertNotNil(decoded.objects[0].artwork)
    // Verify integrity fields independently of the reader, which intentionally tolerates old files.
    var cursor = 64825+p.inputs.count*136+1
    let key = LegacyCodec.templateKey(0xbe87390a)
    for _ in p.objects {
      let meta = LegacyCodec.transform(Data(template[cursor+132..<cursor+348]),key:key), length = Int(template.u32(cursor+348))
      XCTAssertEqual(Data(template[cursor+352..<cursor+360]),LegacyWriter.integrity(meta,seed:20191031+UInt32(length)))
      cursor += 360+length+(length > 0 ? 8 : 0)
      _ = try LegacyProjectSettings.image(template,cursor:&cursor)
    }
    p.objects = [p.objects[1]]
    let style = try LegacyWriter.data(p,format:.rro,seed:42), styleProject = try LegacyReader.style(style)
    XCTAssertEqual(styleProject.objects.first?.text,p.objects.first?.text)
    XCTAssertEqual(styleProject.objects.first?.typography?.bold,true)
  }
  func testNativeImagesEmbedWithoutPathsInAllThreeFormats() throws {
    var p = RaceProject(), image = DisplayObject(name:"Image 日本語",kind:.image)
    image.artwork = try pixel(); p.objects = [image]
    let project = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(project.objects[0].kind,.image); XCTAssertNotNil(project.objects[0].artwork)
    XCTAssertTrue(project.objects[0].text.isEmpty)
    let template = try LegacyReader.template(LegacyWriter.data(p,format:.rrt,seed:42))
    XCTAssertEqual(template.objects[0].kind,.image); XCTAssertNotNil(template.objects[0].artwork)
    let style = try LegacyReader.style(LegacyWriter.data(p,format:.rro,seed:42))
    XCTAssertEqual(style.objects[0].kind,.image); XCTAssertNotNil(style.objects[0].artwork)
  }
  func testIntegrityAlgorithmMatchesKeyVectorAndDistinctPayloads() {
    XCTAssertEqual(Array(LegacyWriter.integrity(Data("WP RaceRender LLC".utf8),seed:0xbe87390a,count:32)),LegacyCodec.templateKey(0xbe87390a))
    XCTAssertNotEqual(LegacyWriter.integrity(Data([0,1,2,3]),seed:20191031),LegacyWriter.integrity(Data([0,1,2,4]),seed:20191031))
    XCTAssertNotEqual(LegacyWriter.integrity(Data([0,1,2,3]),seed:20191031),LegacyWriter.integrity(Data([0,1,2,3]),seed:20191032))
  }
  func testGaugeModesPrecisionNumberingAndSplitUseNativeVerifiedFields() throws {
    var p = RaceProject(), o = DisplayObject(name:"RPM dial",kind:.rpm)
    o.inputIndex = -1; o.maximum = 8000
    var g = GaugeSettings(), d = GaugeDesign(); g.numberingScale = 1000; g.decimals = 2
    d.mode = .dualNeedle; d.splitValue = 3000; d.splitAngle = 135; d.faceGradient = true; d.pins = true
    g.design = d; o.gauge = g; p.objects = [o]
    let bytes = try LegacyWriter.data(p,format:.rrp), payload = Data(bytes[2500..<3212])
    XCTAssertEqual(payload[618],2,"Tachometer type, separate from decimal precision")
    XCTAssertEqual(payload[619] & 0x70,0x10,"Dual needle is a payload flag, not common byte 283")
    XCTAssertEqual(payload[619] & 4,4); XCTAssertEqual(payload[633] & 24,8)
    XCTAssertEqual(payload[627],191,"Dash 1 marks on both explicit data intervals, rather than one fraction")
    XCTAssertEqual(payload.f64(648),3000); XCTAssertEqual(payload.u32(656),135)
    let decoded = try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.objects[0].gauge?.design?.mode,.dualNeedle)
    XCTAssertEqual(decoded.objects[0].gauge?.design?.splitValue,3000)
    XCTAssertEqual(decoded.objects[0].gauge?.numberingScale,1000); XCTAssertEqual(decoded.objects[0].gauge?.decimals,2)
    p.objects[0].gauge?.design?.mode = .filled
    let filled = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(filled.objects[0].gauge?.design?.mode,.filled)
  }
  func testNativeGaugeAndJoinedInputs() throws {
    var p = project(); p.objects = []
    var g = DisplayObject(name:"RPM dial",kind:.rpm); g.inputIndex = 12; g.maximum = 8000; g.gauge = GaugeSettings()
    g.gauge?.numberingScale = 1000; g.gauge?.label = "RPM"; p.objects = [g]
    var root = MediaInput(name:"Joined",path:"",kind:"video",legacyIndex:30); root.isJoinRoot = true
    p.inputs[1].joinedTo = 30; p.inputs.append(root)
    let decoded = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.objects[0].legacyType,30); XCTAssertEqual(decoded.objects[0].maximum,8000)
    XCTAssertEqual(decoded.objects[0].gauge?.label,"RPM"); XCTAssertEqual(decoded.inputs[1].joinedTo,2)
    XCTAssertEqual(decoded.inputs[2].isJoinRoot,true); XCTAssertEqual(decoded.inputs[2].path,"")
  }
  func testFirstClipJoinsBecomeVirtualStreamsWithoutChangingTheirClock() throws {
    var p = project(); p.objects = [p.objects[0]]; p.inputs.removeFirst()
    p.inputs[0].timing?.loop = nil
    var second = MediaInput(name:"Part two",path:"/tmp/part2.mp4",kind:"video",legacyIndex:15)
    second.duration = 20; second.joinedTo = 7; p.inputs.append(second)
    let original = p.placements
    let decoded = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    XCTAssertEqual(decoded.inputs.count,3); XCTAssertEqual(decoded.inputs[0].isJoinRoot,true)
    XCTAssertEqual(decoded.objects[0].inputIndex,0)
    let placements = decoded.placements
    XCTAssertEqual(placements.count,original.count)
    for (a,b) in zip(original,placements) {
      XCTAssertEqual(a.start,b.start,accuracy:0.001); XCTAssertEqual(a.end,b.end,accuracy:0.001)
      XCTAssertEqual(a.sourceStart,b.sourceStart,accuracy:0.001); XCTAssertEqual(a.rate,b.rate,accuracy:0.001)
      XCTAssertEqual(a.input.path,b.input.path)
    }
  }
  func testUnsupportedSettingsFailBeforeOverwritingOutput() throws {
    var p = project(); p.objects[1].shape?.kind = .diamond
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp)) { XCTAssertTrue($0.localizedDescription.contains("diamond")) }
    p.objects[1].shape?.kind = .rectangle
    var segment = ObjectSegment(time:1); segment.x = 50; p.objects[0].segments = [segment]
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrt))
    p.objects[0].segments = nil; p.inputs[0].path = "/tmp/session.rcz"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".rrp")
    defer { try? FileManager.default.removeItem(at:url) }
    let sentinel = Data("Previous file".utf8); try sentinel.write(to:url)
    XCTAssertThrowsError(try LegacyWriter.write(p,to:url)); XCTAssertEqual(try Data(contentsOf:url),sentinel)
  }
  func testUnchangedImportedInputSettingsPreserveOpaqueBytes() throws {
    let original = try LegacyWriter.data(project(),format:.rrp)
    var b = original
    let sourceSettings = 2152+2216
    b[sourceSettings+9000] = 0x7e
    var imported = try LegacyReader.project(b,base:URL(fileURLWithPath:"/tmp"))
    imported.objects.removeFirst(); imported.objects.reverse(); imported.objects.append(DisplayObject(name:"New text",kind:.text))
    let updated = try LegacyWriter.data(imported,format:.rrp)
    XCTAssertEqual(updated[sourceSettings+9000],0x7e)
    XCTAssertEqual(try LegacyReader.project(updated,base:URL(fileURLWithPath:"/tmp")).objects.last?.name,"New text")
  }
  func pixel() throws -> Data {
    let image = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    image.setColor(.red,atX:0,y:0); image.setColor(.blue,atX:1,y:0)
    return try XCTUnwrap(image.representation(using:.png,properties:[:]))
  }
}
