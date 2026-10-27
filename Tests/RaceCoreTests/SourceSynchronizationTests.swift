import XCTest
@testable import RaceCore

final class SourceSynchronizationTests: XCTestCase {
  func session() -> RaceProject {
    var a = MediaInput(name:"Reference",path:"a.mov",kind:"video",legacyIndex:1); a.duration = 20
    var b = MediaInput(name:"Target",path:"b.mov",kind:"video",legacyIndex:2); b.duration = 25
    var p = RaceProject(); p.inputs = [a,b]; p.rangeStart = 2; p.rangeEnd = 15
    return p
  }
  func testAlignEarlierAndLaterTargetEventsWithoutChangingReferenceOrMarks() throws {
    var p = session(); let original = p
    let reference = SourceSyncAnchor(p.inputs[0].id,at:5)
    XCTAssertEqual(try p.alignSource(SourceSyncAnchor(p.inputs[1].id,at:8),to:reference),5)
    XCTAssertEqual(p.inputs[1].offset,3); XCTAssertEqual(p.sourceTime(for:2,at:5),8)
    XCTAssertEqual(p.inputs[0],original.inputs[0]); XCTAssertEqual(p.rangeStart,2); XCTAssertEqual(p.rangeEnd,15)
    try p.alignSource(SourceSyncAnchor(p.inputs[1].id,at:2),to:reference)
    XCTAssertEqual(p.inputs[1].offset,-3); XCTAssertEqual(p.sourceTime(for:2,at:5),2); XCTAssertNil(p.sourceTime(for:2,at:2))
  }
  func testSourceClockIncludesReferenceAndTargetTrimRateDelay() throws {
    var p = session()
    var a = InputTiming(); a.trimStart = 2; a.rate = 2; a.projectStart = 3; p.inputs[0].timing = a; p.inputs[0].offset = 1
    var b = InputTiming(); b.trimStart = 1; b.trimEnd = 18; b.projectStart = 2; p.inputs[1].timing = b
    let ref = SourceSyncAnchor(p.inputs[0].id,at:9)
    let time = try p.alignSource(SourceSyncAnchor(p.inputs[1].id,at:7),to:ref,rate:0.5)
    XCTAssertEqual(time,6); XCTAssertEqual(p.sourceTime(for:2,at:time),7)
    XCTAssertEqual(p.inputs[1].offset,4); XCTAssertEqual(p.inputs[1].timing?.rate,0.5)
    XCTAssertEqual(p.inputs[1].timing?.trimStart,1); XCTAssertEqual(p.inputs[1].timing?.trimEnd,18); XCTAssertEqual(p.inputs[1].timing?.projectStart,2)
  }
  func testJoinedReferenceAndLoopUseFirstActiveOccurrence() throws {
    var p = session(); p.inputs[0].duration = 3
    var child = MediaInput(name:"Second reference clip",path:"c.mov",kind:"video",legacyIndex:4); child.duration = 5; child.joinedTo = 1
    p.inputs.append(child); var loop = InputTiming(); loop.loop = true; p.inputs[0].timing = loop
    XCTAssertEqual(try p.projectTime(for:SourceSyncAnchor(child.id,at:2)),5)
    try p.alignSource(SourceSyncAnchor(p.inputs[1].id,at:4),to:SourceSyncAnchor(child.id,at:2))
    XCTAssertEqual(p.sourceTime(for:2,at:5),4)
    let before = p
    XCTAssertThrowsError(try p.alignSource(SourceSyncAnchor(p.inputs[0].id,at:1),to:SourceSyncAnchor(child.id,at:2)))
    XCTAssertEqual(p,before,"Changing a root cannot preserve a reference that belongs to that same stream")
  }
  func testInvalidEventsAndRateCannotPartiallyMutateTiming() throws {
    var p = session(); let before = p
    let ref = SourceSyncAnchor(p.inputs[0].id,at:5), target = SourceSyncAnchor(p.inputs[1].id,at:8)
    for rate in [0,101,Double.nan,Double.infinity] {
      XCTAssertThrowsError(try p.alignSource(target,to:ref,rate:rate)); XCTAssertEqual(p,before)
    }
    for event in [SourceSyncAnchor(p.inputs[0].id,at:20),SourceSyncAnchor(UUID(),at:5),SourceSyncAnchor(p.inputs[0].id,at:Double.nan)] {
      XCTAssertThrowsError(try p.alignSource(target,to:event,rate:2)); XCTAssertEqual(p,before)
    }
    XCTAssertThrowsError(try p.alignSource(ref,to:ref)); XCTAssertEqual(p,before)
    var timing = InputTiming(); timing.trimStart = 10; p.inputs[1].timing = timing
    let trimmed = p
    XCTAssertThrowsError(try p.alignSource(target,to:ref,rate:2)); XCTAssertEqual(p,trimmed)
    p.inputs[1].joinedTo = 1; let joined = p
    XCTAssertThrowsError(try p.alignSource(target,to:ref)); XCTAssertEqual(p,joined)
  }
}
