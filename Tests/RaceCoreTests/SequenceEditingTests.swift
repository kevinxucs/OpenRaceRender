import XCTest
@testable import RaceCore

final class SequenceEditingTests: XCTestCase {
  func session() -> RaceProject {
    var a = MediaInput(name:"A",path:"a.mov",kind:"video",legacyIndex:1); a.duration = 2
    var b = MediaInput(name:"B",path:"b.mov",kind:"video",legacyIndex:2); b.duration = 3; b.joinedTo = 1
    var data = MediaInput(name:"Logger",path:"data.csv",kind:"data",legacyIndex:5); data.duration = 30
    var o = DisplayObject(name:"Camera",kind:.video); o.inputIndex = 1
    var p = RaceProject(); p.inputs = [a,data,b]; p.objects = [o]; p.lengthInputIndex = 1; p.rangeStart = 0.5; p.rangeEnd = 4
    return p
  }
  func testDraftNormalizationAndReorderingPreserveLogicalRoleAndCancelState() throws {
    let p = session(); var draft = try SequenceDraft(project:p,inputID:p.inputs[0].id)
    XCTAssertEqual(draft.original,p); XCTAssertEqual(draft.project.duration,p.duration)
    XCTAssertEqual(draft.project.inputs.first?.id,p.inputs[0].id)
    XCTAssertEqual(draft.clips.map(\.name),["A","B"])
    let first = draft.clips[0]
    try draft.move(first.id,to:1)
    let edited = try draft.applying(to:p)
    XCTAssertEqual(edited.media(for:1,at:1)?.input.name,"B")
    XCTAssertEqual(edited.media(for:1,at:4)?.input.name,"A")
    XCTAssertEqual(edited.objects,p.objects); XCTAssertEqual(edited.rangeStart,p.rangeStart); XCTAssertEqual(edited.rangeEnd,p.rangeEnd)
    XCTAssertEqual(p.inputs[0].name,"A"); XCTAssertNil(p.inputs[0].isJoinRoot)
  }
  func testFillersOccupyExactJoinedClockIncludingTrailingGapAndUpdatedChildTrim() throws {
    let p = session(); var draft = try SequenceDraft(project:p,inputID:p.inputs[0].id)
    let gap = try draft.addFiller(after:draft.clips[0].id,seconds:1)
    try draft.addFiller(after:draft.clips.last?.id,seconds:0.5)
    var edited = try draft.applying(to:p)
    XCTAssertEqual(edited.duration,6.5)
    XCTAssertEqual(edited.media(for:1,at:2)?.input.id,gap)
    XCTAssertEqual(edited.media(for:1,at:3)?.input.name,"B")
    XCTAssertEqual(edited.media(for:1,at:6.25)?.input.isTimeFiller,true)
    edited.inputs[0].duration = 1 // stale metadata must not silently cut the sequence
    XCTAssertEqual(edited.duration,6.5)
    var b = draft.clips.first(where:{$0.name == "B"})!; var timing = InputTiming(); timing.trimEnd = 1; b.timing = timing
    try draft.update(b); XCTAssertEqual(try draft.applying(to:p).duration,4.5)
    draft.removeFiller(gap); XCTAssertEqual(try draft.applying(to:p).duration,3.5)
  }
  func testDraftValidationRejectsStaleProjectAndInvalidDurationWithoutApplying() throws {
    let p = session(); var draft = try SequenceDraft(project:p,inputID:p.inputs[0].id)
    let unchanged = draft
    XCTAssertThrowsError(try draft.addFiller(after:nil,seconds:.nan)); XCTAssertEqual(draft,unchanged)
    var changed = p; changed.notes = "External edit"
    XCTAssertThrowsError(try draft.applying(to:changed))
    let id = try draft.addFiller(after:nil)
    var gap = draft.clips.first(where:{$0.id == id})!; gap.duration = -1; try draft.update(gap)
    XCTAssertThrowsError(try draft.applying(to:p))
  }
  func testRootBlocksAndJoinedMembersReorderWithoutRenumberingSources() throws {
    var p = session(); let original = p
    try p.moveInput(p.inputs[1].id,direction:-1)
    XCTAssertEqual(p.inputs.map(\.legacyIndex),[5,1,2])
    XCTAssertEqual(p.objects,original.objects)
    let b = p.inputs.first(where:{$0.legacyIndex == 2})!
    try p.moveInput(b.id,direction:-1)
    XCTAssertEqual(p.media(for:1,at:0.5)?.input.id,b.id)
    XCTAssertEqual(p.inputs.first(where:{$0.isJoinRoot == true})?.legacyIndex,1)
  }
  func testNativeGapPersistenceAndExplicitLegacyRefusal() throws {
    let p = session(); var draft = try SequenceDraft(project:p,inputID:p.inputs[0].id)
    try draft.addFiller(after:draft.clips[0].id,seconds:1.25)
    let edited = try draft.applying(to:p)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer {try? FileManager.default.removeItem(at:file)}
    try edited.save(file); let reopened = try RaceProject.read(file)
    XCTAssertEqual(reopened.duration,6.25); XCTAssertEqual(reopened.inputs.filter{$0.isTimeFiller == true}.count,1)
    XCTAssertThrowsError(try LegacyWriter.data(edited,format:.rrp)) { error in XCTAssertTrue(error.localizedDescription.contains("Time filler")) }
    let template = try edited.reusableLayout()
    XCTAssertTrue(template.inputs.allSatisfy{$0.isTimeFiller == nil && $0.joinedTo == nil && $0.isJoinRoot == nil})
  }
  func testGapNeedsNoAssetButMissingPhysicalClipIsStillReported() throws {
    let p = session(); var draft = try SequenceDraft(project:p,inputID:p.inputs[0].id)
    try draft.addFiller(after:draft.clips.last?.id,seconds:1)
    let edited = try draft.applying(to:p)
    XCTAssertNoThrow(try edited.validateExportAssets(start:5,duration:0.5))
    XCTAssertThrowsError(try edited.validateExportAssets(start:0,duration:1))
  }
  func testMergingVirtualStreamRemovesContainerInsteadOfAddingItsDurationTwice() throws {
    var a = MediaInput(name:"A",path:"a.mov",kind:"video",legacyIndex:0); a.duration = 1
    var stream = MediaInput(name:"B stream",path:"",kind:"video",legacyIndex:1); stream.isJoinRoot = true; stream.duration = 2
    var b = MediaInput(name:"B",path:"b.mov",kind:"video",legacyIndex:2); b.joinedTo = 1; b.duration = 2
    var p = RaceProject(); p.inputs = [a,stream,b]; p.lengthInputIndex = 1
    var camera = DisplayObject(name:"A",kind:.video); camera.inputIndex = 0
    var event = ObjectSegment(time:1); event.inputIndex = 1; camera.segments = [event]
    p.objects = [camera]
    var bad = p; bad.inputs[1].offset = 1; let before = bad
    XCTAssertThrowsError(try bad.joinInputAfterPrevious(stream.id)); XCTAssertEqual(bad,before)
    try p.joinInputAfterPrevious(stream.id)
    XCTAssertEqual(p.inputs.count,2); XCTAssertEqual(p.inputs[1].joinedTo,0)
    XCTAssertEqual(p.duration,3); XCTAssertEqual(p.lengthInputIndex,0)
    XCTAssertEqual(p.objects[0].segments?.first?.inputIndex,0)
  }
}
