import AppKit
import XCTest
@testable import RaceCore

final class MapDisplayTests:XCTestCase {
  func testMissingMapPositionsShowStatusInsteadOfSilentBlank() throws {
    let data = try Telemetry(text:"Time,RPM\n0,1000\n1,2000\n")
    var p = RaceProject(); var source = MediaInput(name:"Data",path:"",kind:"data"); source.duration = 1; p.inputs = [source]
    var o = DisplayObject(name:"Map",kind:.map); o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.mapSettings = MapDisplaySettings(); p.objects = [o]
    let c = try XCTUnwrap(CGContext(data:nil,width:200,height:200,bitsPerComponent:8,bytesPerRow:800,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[0:data]),time:0.5,size:CGSize(width:200,height:200))
    XCTAssertTrue(Data(bytes:try XCTUnwrap(c.data),count:160000).contains{$0 != 0})
  }
  func testViewportRotationFollowAndBackgroundUseIdenticalCoordinates() {
    let bounds = CGRect(x:0,y:0,width:100,height:100),rect = CGRect(x:0,y:0,width:200,height:100)
    var style = MapDisplaySettings(); let base = MapViewport(bounds:bounds,rect:rect,settings:style,position:nil,heading:nil)
    style.rotation = 90
    let rotated = MapViewport(bounds:bounds,rect:rect,settings:style,position:nil,heading:nil)
    let north = CGPoint(x:50,y:100).applying(rotated.transform)
    XCTAssertEqual(north.x,143,accuracy:1e-9); XCTAssertEqual(north.y,50,accuracy:1e-9)
    style.rotation = 0; style.headingUp = true
    let heading = MapViewport(bounds:bounds,rect:rect,settings:style,position:nil,heading:90)
    let east = CGPoint(x:100,y:50).applying(heading.transform); XCTAssertEqual(east.x,100,accuracy:1e-9); XCTAssertEqual(east.y,93,accuracy:1e-9)
    style.followPosition = true; style.zoom = 2
    let followed = MapViewport(bounds:bounds,rect:rect,settings:style,position:CGPoint(x:20,y:30),heading:90)
    let center = CGPoint(x:20,y:30).applying(followed.transform); XCTAssertEqual(center.x,100,accuracy:1e-9); XCTAssertEqual(center.y,50,accuracy:1e-9)
    for point in [CGPoint(x:10,y:90),CGPoint(x:50,y:50)] {
      let map = point.applying(followed.transform),image = point.applying(base.transform).applying(followed.backgroundTransform)
      XCTAssertEqual(map.x,image.x,accuracy:1e-9); XCTAssertEqual(map.y,image.y,accuracy:1e-9)
    }
  }
  func testTraceChoicesResolutionAndExactLapEndpoints() throws {
    let rows = (0...5000).map{"\(Double($0)/100),\($0),\($0%100),\($0 < 1000 ? 1 : $0 < 3000 ? 2 : 3)"}
    let data = try Telemetry(text:"Time,X,Y,Lap\n"+rows.joined(separator:"\n"))
    var settings = DataSettings(); settings.assignments["lap"] = "Lap"; data.configure(settings)
    var style = MapDisplaySettings(); style.trace = .best
    XCTAssertEqual(style.range(data:data,time:2),10...30)
    style.trace = .current; XCTAssertEqual(style.range(data:data,time:35),30...50)
    style.trace = .lap; style.lapStart = 999; XCTAssertNil(style.range(data:data,time:2))
    let normal = MapDisplayRenderer.Trace(data:data,range:10.25...20.75,maximum:1000)
    let extreme = MapDisplayRenderer.Trace(data:data,range:10.25...20.75,maximum:16000)
    XCTAssertEqual(normal.points.first?.0,1025); XCTAssertEqual(normal.points.last?.0,2075)
    XCTAssertLessThanOrEqual(normal.points.count,extreme.points.count)
  }
  func testIconsVisibilityAndFlagsRenderDistinctPixels() throws {
    let data = try Telemetry(text:"Time,X,Y\n0,0,0\n1,1,1\n2,2,0\n")
    var p = RaceProject(); var input = MediaInput(name:"Data",path:"",kind:"data"); input.duration = 2; p.inputs = [input]
    var object = DisplayObject(name:"Map",kind:.map); object.x = 0; object.y = 0; object.width = 100; object.height = 100
    var style = MapDisplaySettings(); style.drawCourse = false
    func render(_ style:MapDisplaySettings) throws -> Data {
      var copy = p; var o = object; o.mapSettings = style; copy.objects = [o]
      let c = try XCTUnwrap(CGContext(data:nil,width:200,height:200,bitsPerComponent:8,bytesPerRow:800,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
      OverlayRenderer.draw(c,scene:RenderScene(project:copy,telemetry:[0:data]),time:0.5,size:CGSize(width:200,height:200))
      return Data(bytes:try XCTUnwrap(c.data),count:160000)
    }
    var images = Set<Data>()
    for icon in MapDisplaySettings.Icon.allCases { style.icon = icon; images.insert(try render(style)) }
    XCTAssertEqual(images.count,4)
    style.drawPosition = false; let empty = try render(style); XCTAssertTrue(empty.allSatisfy{$0 == 0})
    style.drawStart = true; XCTAssertNotEqual(try render(style),empty)
  }
  func testImportedOptionsAreReadWithoutMutationAndEditedStateClearsAndPersists() throws {
    var o = DisplayObject(name:"Imported",kind:.map); o.legacyType = 70
    var payload = Data(repeating:0,count:80); payload.putU32(0xFFFFFF00,32); payload.putU32(0x00FF0000,48); payload[60] = 150; payload[63] = 1; payload[68] = 1; o.legacyPayload = payload
    let style = o.editableMapSettings
    XCTAssertFalse(style.drawCourse); XCTAssertTrue(style.drawPosition); XCTAssertEqual(style.zoom,1.5); XCTAssertEqual(style.trace,.best); XCTAssertEqual(style.icon,.arrow); XCTAssertNil(o.mapSettings)
    o.mapSettings = style; var changed = o; changed.mapSettings = nil; o.editSegment(at:2,from:o,to:changed)
    XCTAssertNil(o.resolved(at:3).mapSettings)
    XCTAssertEqual(try JSONDecoder().decode(DisplayObject.self,from:JSONEncoder().encode(o)),o)
    var p = RaceProject(); p.objects = [o]; XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
}
