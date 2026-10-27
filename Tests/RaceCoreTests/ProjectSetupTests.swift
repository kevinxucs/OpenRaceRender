import XCTest
@testable import RaceCore

final class ProjectSetupTests: XCTestCase {
  func testPrimaryLengthFollowsTrimsRateDelayAndJoinedSequenceInsteadOfLongerData() throws {
    var camera = MediaInput(name:"Primary camera",path:"a.mov",kind:"video",legacyIndex:1); camera.duration = 12
    var data = MediaInput(name:"Long logger",path:"data.csv",kind:"data",legacyIndex:9); data.duration = 100
    var project = RaceProject(); project.inputs = [camera,data]
    try project.matchLength(to:1); XCTAssertEqual(project.duration,12)
    var trim = SourceTrimDraft(input:camera,duration:12,frameRate:30); trim.start = 2; trim.end = 8
    project.inputs[0] = try trim.applying(to:camera)
    XCTAssertEqual(project.duration,6)
    project.inputs[0].timing?.rate = 2; project.inputs[0].timing?.projectStart = 1
    XCTAssertEqual(project.duration,4)
    var next = MediaInput(name:"Joined clip",path:"b.mov",kind:"video",legacyIndex:2); next.duration = 3; next.joinedTo = 1
    project.inputs.append(next); XCTAssertEqual(project.duration,7)
    XCTAssertEqual(project.lengthInputs.map(\.legacyIndex),[1,9])
    project.inputs[0].timing?.loop = true
    XCTAssertEqual(project.duration,7,"A bound loop must not recursively extend itself")
    try project.matchLength(to:nil); XCTAssertEqual(project.duration,100)
  }
  func testLengthModesAreExclusiveValidatedAndTransactional() throws {
    var p = RaceProject(); var video = MediaInput(name:"Camera",path:"a.mov",kind:"video",legacyIndex:3); video.duration = 10
    p.inputs = [video,MediaInput(name:"Still",path:"art.png",kind:"image",legacyIndex:8)]
    try p.setManualLength(2.5); XCTAssertNil(p.lengthInputIndex); XCTAssertEqual(p.duration,2.5)
    let saved = p
    for index in [8,999] { XCTAssertThrowsError(try p.matchLength(to:index)); XCTAssertEqual(p,saved) }
    for value in [0,-1,Double.infinity,Double.nan] { XCTAssertThrowsError(try p.setManualLength(value)); XCTAssertEqual(p,saved) }
    try p.matchLength(to:3); XCTAssertNil(p.explicitDuration); XCTAssertEqual(p.duration,10)
    XCTAssertEqual(p.lengthSummary,"Matches Camera")
    try p.setManualLength(4); XCTAssertNil(p.lengthInputIndex)
    try p.matchLength(to:nil); XCTAssertNil(p.explicitDuration); XCTAssertNil(p.lengthInputIndex)
  }
  func testNotesLengthAndSpeedPersistInNativeAndLegacyButDoNotLeakIntoTemplates() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:root) }
    var p = RaceProject(); var data = MediaInput(name:"Logger",path:"data.csv",kind:"data",legacyIndex:2); data.duration = 15
    p.inputs = [data]; p.objects = [DisplayObject(name:"Caption",kind:.text)]
    p.notes = "Session setup notes\nSecond line"; p.speedUnit = "knots"; try p.matchLength(to:2)
    p.rangeStart = 2; p.rangeEnd = 10
    let native = root.appendingPathComponent("project.orrp"), legacy = root.appendingPathComponent("project.rrp")
    try p.save(native); try LegacyWriter.write(p,to:legacy)
    for file in [native,legacy] {
      let reopened = try RaceProject.read(file)
      XCTAssertEqual(reopened.notes,p.notes); XCTAssertEqual(reopened.speedUnit,"knots")
      XCTAssertEqual(reopened.duration,15); XCTAssertEqual(reopened.lengthInputIndex,file == native ? 2 : 0)
      XCTAssertEqual(reopened.rangeStart,2); XCTAssertEqual(reopened.rangeEnd,10)
    }
    let layout = try p.reusableLayout()
    XCTAssertNil(layout.notes); XCTAssertNil(layout.lengthInputIndex); XCTAssertNil(layout.explicitDuration)
  }
}
