import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import RaceCore

final class SphericalTests:XCTestCase {
  let context = PictureProcessor.context()
  func pixel(_ image:CIImage,_ x:Int,_ y:Int) -> [UInt8] {
    var bytes = [UInt8](repeating:0,count:4)
    bytes.withUnsafeMutableBytes{context.render(image,toBitmap:$0.baseAddress!,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:OverlayRenderer.colorSpace)};return bytes
  }
  func gradient(_ width:Int,_ height:Int) -> CIImage {
    var data = Data();for y in 0..<height {for x in 0..<width {data.append(contentsOf:[UInt8(x*2),UInt8(y*2),40,255])}}
    return CIImage(bitmapData:data,bytesPerRow:width*4,size:CGSize(width:width,height:height),format:.RGBA8,colorSpace:OverlayRenderer.colorSpace)
  }
  func testPanWrapAndFisheyeAgainstAnalyticCoordinates() throws {
    let source = gradient(128,128)
    try XCTSkipIf(pixel(source,64,64)[0] != 128,"Core Image unavailable")
    var settings = PictureSettings(),projection = SphericalProjection();projection.pan = 90;settings.spherical = projection
    let panorama = PictureProcessor.apply(source,settings:settings)
    XCTAssertEqual(Double(pixel(panorama,64,64)[0]),192,accuracy:2)
    XCTAssertEqual(Double(pixel(panorama,120,64)[0]),48,accuracy:2)
    projection.pan = -0.25/128*360;settings.spherical = projection
    XCTAssertEqual(Double(pixel(PictureProcessor.apply(source,settings:settings),0,64)[0]),63.5,accuracy:2)
    projection.mode = .fisheye;projection.pan = 0;projection.fieldOfView = 240;projection.axis = .up;settings.spherical = projection
    try settings.validateEffects()
    let unwrapped = PictureProcessor.apply(source,settings:settings)
    XCTAssertEqual(unwrapped.extent,CGRect(x:0,y:0,width:256,height:128))
    XCTAssertEqual(pixel(unwrapped,128,0)[3],0)
    for (x,y) in [(128,64),(64,90),(192,100)] {
      let lon = (Double(x)+0.5)/256*2*Double.pi-Double.pi
      let lat = (Double(y)+0.5)/128*Double.pi-Double.pi/2
      let theta = Double.pi/2-lat,radius = theta/(120 * .pi/180)*64
      let sx = 64+sin(lon)*radius,sy = 64+cos(lon)*radius
      let actual = pixel(unwrapped,x,y)
      XCTAssertEqual(Double(actual[0]),(sx-0.5)*2,accuracy:4);XCTAssertEqual(Double(actual[1]),255-sy*2,accuracy:4);XCTAssertEqual(actual[3],255)
    }
    projection.fieldOfView = .nan;settings.spherical = projection;XCTAssertThrowsError(try settings.validateEffects())
  }
  func testExpandedWorkspacePlacementAndSettingsPersistence() throws {
    var project = RaceProject();project.setSphericalWorkspace(true);project.width = 300;project.height = 150
    XCTAssertEqual(project.canvasRect(CGRect(x:0,y:0,width:100,height:100),size:CGSize(width:300,height:150)),CGRect(x:100,y:50,width:100,height:50))
    XCTAssertEqual(project.workspacePoint(CGPoint(x:50,y:75),size:CGSize(width:300,height:150)),CGPoint(x:-50,y:50))
    var object = DisplayObject(name:"Left",kind:.shape);object.shape = ShapeSettings();object.color = "#FF0000";object.x = -100;object.y = 0;object.width = 100;object.height = 100
    project.objects = [object]
    let canvas = CGContext(data:nil,width:300,height:150,bitsPerComponent:8,bytesPerRow:0,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo)!
    OverlayRenderer.draw(canvas,scene:RenderScene(project:project,telemetry:[:]),time:0,size:CGSize(width:300,height:150))
    let image = CIImage(cgImage:try XCTUnwrap(canvas.makeImage()),options:[.colorSpace:NSNull()])
    XCTAssertEqual(pixel(image,50,75)[0],255);XCTAssertEqual(pixel(image,150,75)[3],0)
    let placed = object.placed(at:CGPoint(x:-50,y:50),within:project.workspaceBounds);XCTAssertLessThan(placed.x,0)
    let encoded = try JSONEncoder().encode(project),reopened = try JSONDecoder().decode(RaceProject.self,from:encoded)
    XCTAssertEqual(reopened.sphericalWorkspace,true)
    let layout = try project.reusableLayout();var destination = RaceProject();destination.applyLayout(layout,replace:false)
    XCTAssertEqual(destination.sphericalWorkspace,true)
    var settings = ExportSettings();try settings.validate(project:project)
    var output = OutputSettings();output.width = 320;output.height = 180;settings.output = output
    XCTAssertThrowsError(try settings.validate(project:project))
  }
  func word(_ n:UInt32) -> Data {var value = n.bigEndian;return withUnsafeBytes(of:&value){Data($0)}}
  func box(_ name:String,_ data:Data) -> Data {word(UInt32(data.count+8))+Data(name.utf8)+data}
  func syntheticMovie(stereo:Bool = false) -> Data {
    let v2 = box("sv3d",box("svhd",word(0)+Data("Original test\0".utf8)))
    let stereoBox = stereo ? box("st3d",word(0)+Data([1])) : Data()
    let sample = box("avc1",Data(repeating:0,count:78)+v2+stereoBox)
    let description = box("stsd",word(0)+word(1)+sample)
    let handler = box("hdlr",Data(repeating:0,count:8)+Data("vide".utf8)+Data(repeating:0,count:12))
    let tkhd = box("tkhd",Data(repeating:0,count:76)+word(320 << 16)+word(160 << 16))
    let track = box("trak",tkhd+box("mdia",handler+box("minf",box("stbl",description)))+box("uuid",Data(repeating:7,count:16)+Data("Keep unrelated metadata".utf8)))
    return box("mdat",Data("Original encoded media bytes".utf8))+box("moov",track)
  }
  func testMetadataCopyClearV2AndPreserveMediaAndOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    let source = root.appendingPathComponent("source.mp4"),marked = root.appendingPathComponent("marked.mp4"),cleared = root.appendingPathComponent("clear.mp4")
    let bytes = syntheticMovie();try bytes.write(to:source)
    try FileManager.default.setAttributes([.posixPermissions:0o444],ofItemAtPath:source.path)
    XCTAssertTrue(try SphericalMetadata.inspect(source).hasV2)
    try SphericalMetadata.copy(source,to:marked,enabled:true)
    let info = try SphericalMetadata.inspect(marked);XCTAssertTrue(info.hasV1);XCTAssertFalse(info.hasV2);XCTAssertEqual(info.width,320)
    XCTAssertEqual(try Data(contentsOf:source),bytes)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:source.path)[.posixPermissions] as? NSNumber)?.intValue,0o444)
    XCTAssertTrue(try Data(contentsOf:marked).starts(with:bytes.prefix(35)))
    try SphericalMetadata.copy(marked,to:cleared,enabled:false);XCTAssertFalse(try SphericalMetadata.inspect(cleared).marked)
    XCTAssertThrowsError(try SphericalMetadata.copy(source,to:marked,enabled:true))
    XCTAssertThrowsError(try SphericalMetadata.copy(source,to:source,enabled:false))
    let stereo = root.appendingPathComponent("stereo.mp4");try syntheticMovie(stereo:true).write(to:stereo)
    XCTAssertThrowsError(try SphericalMetadata.copy(stereo,to:root.appendingPathComponent("bad.mp4"),enabled:true))
  }
  func testNativeSphericalWorkspaceAndSourceSettings() throws {
    var header = Data(repeating:0,count:2152); header[2126] = 6
    var project = RaceProject(); LegacyProjectSettings.header(header,project:&project,sourceStart:2152)
    XCTAssertEqual(project.sphericalWorkspace,true);XCTAssertEqual(project.width,3840);XCTAssertEqual(project.height,1920)
    var record = Data(repeating:0,count:2216);record[2176] = 1;record[2178] = 255
    var settings = Data(repeating:0,count:56);settings[31] = 2;settings[43] = 255
    settings.putU32(Float(240).bitPattern,44);settings.putU32(Float(90).bitPattern,48)
    var source = MediaInput(name:"Test",path:"",kind:"video"),warnings:[String] = []
    LegacyProjectSettings.input(record,at:0,settings:settings,input:&source,warnings:&warnings)
    XCTAssertEqual(source.picture?.spherical?.pan,90);XCTAssertEqual(source.picture?.spherical?.fieldOfView,240)
    XCTAssertEqual(source.picture?.spherical?.mode,.fisheye);XCTAssertEqual(source.picture?.spherical?.axis,.up)
  }
  func testActual360ExportAutomaticallyMarksPlayableOutput() async throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    defer {try? FileManager.default.removeItem(at:output)}
    var p = RaceProject();p.sphericalWorkspace = true;p.width = 320;p.height = 160;p.fps = 10;p.explicitDuration = 1
    var shape = DisplayObject(name:"Center",kind:.shape);shape.shape = ShapeSettings();shape.color = "#FF0000";shape.x = 0;shape.y = 0;shape.width = 100;shape.height = 100;p.objects = [shape]
    try await VideoExporter().export(scene:RenderScene(project:p,telemetry:[:]),to:output,start:0,duration:1)
    let info = try SphericalMetadata.inspect(output);XCTAssertTrue(info.hasV1);XCTAssertEqual(info.height,160)
    let asset = AVURLAsset(url:output);let tracks = try await asset.loadTracks(withMediaType:.video);XCTAssertEqual(tracks.count,1)
    let duration = try await asset.load(.duration).seconds;XCTAssertEqual(duration,1,accuracy:0.02)
  }
}
