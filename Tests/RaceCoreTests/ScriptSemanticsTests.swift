import AppKit
import XCTest
@testable import RaceCore

final class ScriptSemanticsTests:XCTestCase {
  func testInstalledEnhancedStylesAcceptDocumentedParameterTypes() throws {
    guard let path = ProcessInfo.processInfo.environment["OPENRACERENDER_LIBRARY"] else {throw XCTSkip("Set OPENRACERENDER_LIBRARY for optional installed-style coverage.")}
    let entries = LayoutLibrary.entries(in:[URL(fileURLWithPath:path)])
    var tested = 0
    for entry in entries where entry.category == .styles {
      let project = try RaceProject.read(entry.url)
      for object in project.objects where object.hasScriptStyleSettings {
        for time in [0.5,90.0] {
          let c = try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
          var failure = ""
          XCTAssertTrue(LegacyEnhancedRenderer.draw(c,object:object,rect:CGRect(x:0,y:0,width:8,height:8),data:WidgetDesign.telemetry,time:time,unit:"mph",failure:{failure = $0}),"\(entry.relativePath): \(failure)")
        }
        tested += 1
      }
    }
    XCTAssertGreaterThan(tested,0)
  }
  func testDrawTimeDecimalsCompactCarrySignsAndActualPixels() throws {
    XCTAssertEqual(ScriptTimeFormat.string(1.234,decimals:3,compact:0),"00:00:01.234")
    XCTAssertEqual(ScriptTimeFormat.string(1.234,decimals:2,compact:1),"00:01.23")
    XCTAssertEqual(ScriptTimeFormat.string(1.234,decimals:1,compact:2),"1.2")
    XCTAssertEqual(ScriptTimeFormat.string(61.25,decimals:2,compact:2),"01:01.25")
    XCTAssertEqual(ScriptTimeFormat.string(3661.25,decimals:0,compact:2),"01:01:01")
    XCTAssertEqual(ScriptTimeFormat.string(59.9995,decimals:3,compact:2),"01:00.000")
    XCTAssertEqual(ScriptTimeFormat.string(-0.00001,decimals:0,compact:0),"00:00:00")
    XCTAssertEqual(ScriptTimeFormat.string(-61.25,decimals:2,compact:1),"-01:01.25")
    XCTAssertEqual(ScriptTimeFormat.string(.nan,decimals:3,compact:0),"—")
    let object = DisplayObject(name:"Time formatting",kind:.enhanced)
    var draft = EnhancedScriptDraft(object:object);draft.width = 320;draft.height = 100;draft.background = ""
    draft.foreground = "DrawTime(61.234,3,10,50,White,28,AlignH_Left,1);"
    let actual = try draft.test(object:object,data:nil,sourceTime:0,displayTime:0,unit:"mph",fps:30)
    draft.foreground = "DrawText(\"01:01.234\",10,50,White,28,AlignH_Left);"
    let expected = try draft.test(object:object,data:nil,sourceTime:0,displayTime:0,unit:"mph",fps:30)
    XCTAssertEqual(actual.image.dataProvider?.data as Data?,expected.image.dataProvider?.data as Data?)
  }
  func laps() throws -> Telemetry {
    let d = try Telemetry(text:"Time,Speed\n0,10\n60,20\n")
    d.laps = [TelemetryLap(number:0,start:0,end:2,complete:false),TelemetryLap(number:1,start:2,end:14,complete:true),TelemetryLap(number:2,start:14,end:24,complete:true),TelemetryLap(number:3,start:24,end:37,complete:true),TelemetryLap(number:4,start:37,end:45,complete:true),TelemetryLap(number:5,start:45,end:60,complete:false)]
    return d
  }
  func testOverallCurrentPreviousRecordsAndPartialLapsDifferAtBoundaries() throws {
    let d = try laps()
    XCTAssertEqual(d.bestLap?.number,4);XCTAssertNil(d.bestLap(at:13));XCTAssertNil(d.previousBestLap(at:13))
    XCTAssertEqual(d.bestLap(at:14)?.number,1);XCTAssertNil(d.previousBestLap(at:14))
    XCTAssertEqual(d.bestLap(at:24)?.number,2);XCTAssertEqual(d.previousBestLap(at:24)?.number,1)
    XCTAssertEqual(d.bestLap(at:37)?.number,2);XCTAssertEqual(d.previousBestLap(at:37)?.number,2)
    XCTAssertEqual(d.bestLap(at:45)?.number,4);XCTAssertEqual(d.previousBestLap(at:45)?.number,2)
    let c = try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    let drawing = ScriptDrawing(context:c,font:"Arial",data:d,time:24,unit:"mph")
    XCTAssertEqual(try drawing.call("getcurbestlaptime",[]).number,10)
    XCTAssertEqual(try drawing.call("getprevbestlaptime",[]).number,12)
    XCTAssertEqual(try drawing.call("getbestlaptime",[]).number,8)
    XCTAssertEqual(try drawing.call("getlaptime",[.number(5)]).number,0)
  }
  func testLocationMetadataOverridesAndNearbyTrackFallbackAreIdempotent() throws {
    let d = try Telemetry(text:"Session title,Session label\nTrack name,Recorded Raceway\nTime,Speed,Latitude,Longitude\n0,10,36,-121\n1,20,36.001,-121.001\n")
    XCTAssertEqual(d.locationName,"Recorded Raceway");XCTAssertEqual(d.title,"Session label")
    var s = DataSettings();s.locationName = " Custom circuit ";try d.configureValidated(s);XCTAssertEqual(d.locationName,"Custom circuit")
    try d.configureValidated(s);XCTAssertEqual(d.locationName,"Custom circuit")
    s.locationName = "";try d.configureValidated(s);XCTAssertNil(d.locationName)
    s.locationName = nil;try d.configureValidated(s);XCTAssertEqual(d.locationName,"Recorded Raceway")
    var library = TrackLibrary();library.tracks = [SavedTrack(name:"Near",finishLine:FinishLine(latitude:36,longitude:-121,heading:0)),SavedTrack(name:"Far",finishLine:FinishLine(latitude:40,longitude:-120,heading:0))]
    XCTAssertEqual(d.inferredLocationName(library:library),"Near")
    library.tracks.removeFirst();XCTAssertNil(d.inferredLocationName(library:library))
    var current = DataSettings();current.locationName = "Keep me"
    s.locationName = "Do not copy this location"
    let global = DataProfile(name:"Portable",settings:s)
    XCTAssertNil(global.settings.locationName);XCTAssertEqual(global.applying(to:current).locationName,"Keep me")
    s.locationName = "Track profile";let track = DataProfile(name:"Track",settings:s,includeTrackSettings:true)
    XCTAssertEqual(track.applying(to:current).locationName,"Track profile")
  }
  func testInputNameAndLocationChangeInvalidatePersistentBackgroundContext() throws {
    let data = try Telemetry(text:"Track name,Alpha\nTime,Speed\n0,1\n2,2\n")
    var object = DisplayObject(name:"Names",kind:.enhanced)
    var draft = EnhancedScriptDraft(object:object);draft.width = 8;draft.height = 8;draft.persistent = true
    draft.background = "name=InputName; loc=LocName;";draft.foreground = "if(name == \"First\" && loc == \"Alpha\") DrawRect(0,0,8,8,Red,Filled); else DrawRect(0,0,8,8,Blue,Filled);"
    object = try draft.applying(to:object)
    func pixel(_ name:String) throws -> (UInt8,UInt8) {
      let c = try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      XCTAssertTrue(LegacyEnhancedRenderer.draw(c,object:object,rect:CGRect(x:0,y:0,width:8,height:8),data:data,time:1,unit:"mph",timeline:EnhancedTimeline(inputName:name)))
      let bytes = try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self));return (bytes[0],bytes[2])
    }
    let first = try pixel("First"),second = try pixel("Renamed")
    XCTAssertEqual(first.0,255);XCTAssertEqual(second.1,255)
    data.locationName = "Beta";XCTAssertEqual(try pixel("First").1,255)
  }
  func testStringsRequireExplicitNumericFormattingAndTypedFunctionArguments() throws {
    XCTAssertThrowsError(try ScriptMachine.binary("+",.number(1),.string(" MPH")))
    XCTAssertEqual(try ScriptMachine.binary("+",.string("1"),.string(" MPH")).string,"1 MPH")
    let object = DisplayObject(name:"Typed",kind:.enhanced);var draft = EnhancedScriptDraft(object:object)
    for code in ["DrawNumber(\"bad\",0,0,0,White,10,0);","DrawText(123,0,0,White,10,0);","if(\"bad\") Print(1);","x=-\"bad\";","x=\"bad\" && 1;"] {
      draft.foreground = code;XCTAssertThrowsError(try draft.test(object:object,data:nil,sourceTime:0,displayTime:0,unit:"mph",fps:30))
    }
  }
}
