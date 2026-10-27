import AppKit
import XCTest
@testable import RaceCore

final class TimerDisplayTests:XCTestCase {
  func testManualDelayOffsetStopAndArbitrarySeekOrderDoNotNeedData() throws {
    var settings = TimerSettings(); settings.mode = .manual; settings.startDelay = 2; settings.startOffset = 5; settings.stopValue = 8
    let values = [10.0,12,13.5,20].map{settings.value(projectTime:$0,sourceTime:-1,displayStart:10,data:nil)}
    XCTAssertEqual(values,[5,5,6.5,8])
    XCTAssertEqual(settings.value(projectTime:13.5,sourceTime:1000,displayStart:10,data:nil),6.5)
    settings.anchorTime = 20; XCTAssertEqual(settings.value(projectTime:23,sourceTime:0,displayStart:0,data:nil),6)
    settings.stopValue = 4; XCTAssertThrowsError(try settings.validate())
  }
  func testDurationFormattingCarriesSignHoursCompactAndPrecisionWithoutEarlyTick() {
    XCTAssertEqual(TimerSettings.durationString(59.99999),"00:59.999")
    XCTAssertEqual(TimerSettings.durationString(3600.125),"01:00:00.125")
    XCTAssertEqual(TimerSettings.durationString(3600,format:.minutesSeconds,decimals:0),"60:00")
    XCTAssertEqual(TimerSettings.durationString(-1.25,format:.seconds,decimals:2,compact:true),"−1.25")
    XCTAssertEqual(TimerSettings.durationString(62,format:.hoursMinutesSeconds,decimals:0,compact:true),"0:01:02")
    XCTAssertEqual(TimerSettings.durationString(.infinity),"—")
  }
  func testWallClockEpochTimezoneMidnightAndDSTAreExplicitAndStable() throws {
    var s = TimerSettings(); s.mode = .timeOfDay; s.clock = .project; s.epoch = 1710064799; s.timeZone = "America/Los_Angeles"; s.decimals = 0
    XCTAssertEqual(s.string(projectTime:0,sourceTime:-1,displayStart:0,data:nil),"01:59:59")
    XCTAssertEqual(s.string(projectTime:1,sourceTime:-1,displayStart:0,data:nil),"03:00:00")
    s.epoch = 86399; s.timeZone = "UTC"; XCTAssertEqual(s.string(projectTime:1,sourceTime:-1,displayStart:0,data:nil),"00:00:00")
    s.epoch = 43200; s.twelveHour = true; XCTAssertEqual(s.string(projectTime:0,sourceTime:-1,displayStart:0,data:nil),"12:00:00 PM")
    s.timeZone = "Not/A_Zone"; XCTAssertThrowsError(try s.validate())
    s.mode = .manual; XCTAssertNoThrow(try s.validate(),"An unused timezone must not disable a manual timer")
  }
  func testSourceClockUsesRecordingEpochAndConfiguredSourceTimeWithoutGuessingRelativeCSV() throws {
    let data = try Telemetry(text:"Time,RPM\n0,1000\n1,2000\n2,3000\n")
    var s = TimerSettings(); s.mode = .timeOfDay; s.decimals = 3
    XCTAssertEqual(s.string(projectTime:100,sourceTime:1.125,displayStart:0,data:data),"—")
    data.firstSampleUnixTime = 43200
    XCTAssertEqual(s.string(projectTime:100,sourceTime:1.125,displayStart:0,data:data),"12:00:01.125")
    XCTAssertEqual(s.string(projectTime:5,sourceTime:1.125,displayStart:0,data:data),"12:00:01.125")
    s.epoch = 0; XCTAssertEqual(s.string(projectTime:5,sourceTime:1.125,displayStart:0,data:data),"00:00:01.125")
    XCTAssertEqual(s.string(projectTime:0,sourceTime:-1,displayStart:0,data:data),"—")
  }
  func testManualImportedWidgetRendersWithoutMissingInputAndPreflightRejectsMissingClockAnchor() throws {
    var p = RaceProject(); var o = DisplayObject(name:"Timer",kind:.timer); o.inputIndex = 99; o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.legacyType = 50; o.legacyActivation = 0
    var s = TimerSettings(); s.mode = .manual; o.timerSettings = s; p.objects = [o]
    XCTAssertNoThrow(try p.validateExportAssets(start:0,duration:1,telemetry:[:]))
    let c = try XCTUnwrap(CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:800,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo))
    OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[:]),time:0.5,size:CGSize(width:200,height:100))
    XCTAssertTrue(Data(bytes:try XCTUnwrap(c.data),count:80000).contains{$0 != 0})
    s.mode = .timeOfDay; p.objects[0].timerSettings = s
    XCTAssertThrowsError(try p.validateExportAssets(start:0,duration:1,telemetry:[:]))
    p.objects[0].timerSettings?.epoch = 0
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
  }
  func testTimerTemplateCleanupNoDummyRoleAndTimelineClear() throws {
    var p = RaceProject(); p.inputs = [MediaInput(name:"Unused",path:"private.csv",kind:"data",legacyIndex:1)]
    var o = DisplayObject(name:"Manual",kind:.timer); o.inputIndex = 1; var s = TimerSettings(); s.mode = .manual; s.anchorTime = 12; s.epoch = 43200; o.timerSettings = s
    var reset = o; reset.timerSettings = nil; o.editSegment(at:3,from:o,to:reset)
    XCTAssertNil(o.resolved(at:4).timerSettings)
    // A later reset to the original lap timer restores the data dependency.
    p.objects = [o]; XCTAssertEqual(p.layoutInputIndices([o.id]),[1])
    p.objects[0].segments = nil; let layout = try p.reusableLayout()
    XCTAssertTrue(layout.inputs.isEmpty); XCTAssertNil(layout.objects[0].timerSettings?.anchorTime); XCTAssertNil(layout.objects[0].timerSettings?.epoch)
    XCTAssertEqual(try JSONDecoder().decode(RaceProject.self,from:JSONEncoder().encode(p)),p)
  }
}
