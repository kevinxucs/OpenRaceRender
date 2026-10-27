import XCTest
@testable import RaceCore

final class SegmentEditingTests: XCTestCase {
  func fixture() -> RaceProject {
    var p = RaceProject(); var o = DisplayObject(name:"Title",kind:.text); o.text = "Base"
    var a = ObjectSegment(time:1); a.text = "First"; a.opacity = 0.5
    var b = ObjectSegment(time:3); b.color = "#FF0000"
    o.segments = [a,b]; p.objects = [o]; return p
  }
  func testMoveReordersAndShiftPreservesIdentityAndInheritance() throws {
    var p = fixture(); let id = p.objects[0].id, event = p.objects[0].segments![1].id
    try p.retimeSegment(id,at:3,to:0.5)
    XCTAssertEqual(p.objects[0].segments?.first?.id,event)
    XCTAssertEqual(p.objects[0].resolved(at:0.6).text,"Base")
    XCTAssertEqual(p.objects[0].resolved(at:1.5).text,"First")
    try p.retimeSegment(id,at:0.5,to:2.5,following:true)
    XCTAssertEqual(p.objects[0].segments?.map(\.time),[2.5,3])
    XCTAssertEqual(p.objects[0].segments?.first?.id,event)
    XCTAssertEqual(p.objects[0].resolved(at:2).color,"#5EE0B5")
    XCTAssertEqual(p.objects[0].resolved(at:4).text,"First")
  }
  func testInvalidMovesAreTransactionalAndDoNotMergeUnrelatedEvents() throws {
    var p = fixture(); let original = p, id = p.objects[0].id
    for target in [-1.0,Double.nan,Double.infinity,3,1_000_000,1e308] {
      XCTAssertThrowsError(try p.retimeSegment(id,at:1,to:target)); XCTAssertEqual(p,original)
    }
    XCTAssertThrowsError(try p.retimeSegment(id,at:3,to:1,following:true)); XCTAssertEqual(p,original)
  }
  func testPerFieldInheritanceAndFreezeDoNotClearOtherChanges() throws {
    var p = fixture(); let id = p.objects[0].id
    try p.setSegmentOverride(id,at:1,field:.text,enabled:false)
    XCTAssertEqual(p.objects[0].resolved(at:2).text,"Base"); XCTAssertEqual(p.objects[0].resolved(at:2).opacity,0.5)
    try p.setSegmentOverride(id,at:3,field:.opacity,enabled:true)
    XCTAssertEqual(p.objects[0].segments?[1].opacity,0.5)
    p.objects[0].segments?[0].opacity = 0.8
    XCTAssertEqual(p.objects[0].resolved(at:4).opacity,0.5)
    try p.inheritSegment(id,at:3)
    XCTAssertEqual(p.objects[0].resolved(at:4).opacity,0.8)
    XCTAssertTrue(p.objects[0].segments![1].changedFields.isEmpty)
  }
  func testExplicitStyleAndTypedParameterClearsSurviveNativeSaveAndCanInheritAgain() throws {
    var o = DisplayObject(name:"Gauge",kind:.speed); o.gauge = GaugeSettings(); o.legacyType = 30
    o.hud = HUDSettings(.speed)
    o.legacyCommon = Data(repeating:0,count:344); o.legacyPayload = Data(repeating:0,count:712)
    var changed = o; changed.gauge = nil; changed.hud = nil; changed.legacyType = 50; changed.legacyCommon?[280] = 50
    changed.legacyPayload = Data(repeating:0,count:67168)
    o.editSegment(at:1,from:o,to:changed)
    XCTAssertNil(o.resolved(at:2).gauge); XCTAssertEqual(o.resolved(at:2).legacyType,50)
    XCTAssertEqual(o.resolved(at:2).legacyCommon?[280],50)
    XCTAssertTrue(SegmentField.available(for:o.resolved(at:2)).contains(.hud),"Cleared HUD fields must remain available for restoring inheritance")
    var native = o.resolved(at:2); native.legacyType = nil; native.legacyCommon = nil; native.legacyPayload = nil
    o.editSegment(at:3,from:o.resolved(at:3),to:native)
    let restored = try JSONDecoder().decode(DisplayObject.self,from:JSONEncoder().encode(o))
    XCTAssertNil(restored.resolved(at:4).legacyType); XCTAssertNil(restored.resolved(at:4).legacyPayload)
    var p = RaceProject(); p.objects = [restored]
    try p.setSegmentOverride(o.id,at:1,field:.gauge,enabled:false)
    XCTAssertNotNil(p.objects[0].resolved(at:2).gauge)
    try p.setSegmentOverride(o.id,at:3,field:.style,enabled:false)
    XCTAssertEqual(p.objects[0].resolved(at:4).legacyType,50)
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    var authored = RaceProject(); authored.inputs = [MediaInput(name:"Data",path:"",kind:"data")]
    authored.objects = [DisplayObject(name:"Speed",kind:.speed)]
    var legacy = try LegacyReader.project(LegacyWriter.data(authored,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    let original = legacy.objects[0]
    var enhanced = original; enhanced.legacyType = 50; enhanced.legacyCommon?[280] = 50
    enhanced.legacyPayload = Data(repeating:0,count:67168); enhanced.gauge = nil
    legacy.objects[0].editSegment(at:1,from:original,to:enhanced)
    XCTAssertThrowsError(try LegacyWriter.data(legacy,format:.rrp)) { error in
      XCTAssertTrue(error.localizedDescription.contains("renderer types"),error.localizedDescription)
    }
  }
  func groupFixture() -> RaceProject {
    var p = RaceProject(); let g = DisplayObject(name:"Group",kind:.group)
    var c = DisplayObject(name:"Member",kind:.text); c.x = 10; c.y = 10; c.width = 10; c.height = 10; c.parentID = g.id
    var event = ObjectSegment(time:1); event.text = "Independent"; c.segments = [event]
    p.objects = [c,g]; return p
  }
  func testGroupMoveRestoresIndependentChildAndCreatesFreshUndoHistoryAtDestination() throws {
    var p = groupFixture(); let group = p.objects[1].id
    var value = p.displayForEditing(group,at:1)!; value.x = 30; p.updateDisplay(value,at:1)
    let event = p.objects[1].segments![0].id
    try p.retimeSegment(group,at:1,to:2)
    XCTAssertEqual(p.objects[0].resolved(at:1.5).x,10); XCTAssertEqual(p.objects[0].resolved(at:1.5).text,"Independent")
    XCTAssertEqual(p.objects[0].resolved(at:2.5).x,30); XCTAssertEqual(p.objects[1].segments?[0].id,event)
    p.removeDisplaySegment(group,at:2)
    XCTAssertEqual(p.objects[0].resolved(at:3).x,10); XCTAssertEqual(p.objects[0].segments?.map(\.time),[1])
  }
  func testGroupFieldResetAndFollowingShiftKeepChildChanges() throws {
    var p = groupFixture(); let group = p.objects[1].id
    var value = p.displayForEditing(group,at:1)!; value.x = 30; value.width = 20; p.updateDisplay(value,at:1)
    try p.setSegmentOverride(group,at:1,field:.position,enabled:false)
    XCTAssertEqual(p.objects[0].resolved(at:1).x,10); XCTAssertEqual(p.objects[0].resolved(at:1).width,20)
    XCTAssertEqual(p.objects[0].resolved(at:1).text,"Independent")
    value = p.displayForEditing(group,at:3)!; value.x = 50; p.updateDisplay(value,at:3)
    try p.retimeSegment(group,at:1,to:2,following:true)
    XCTAssertEqual(p.objects[1].segments?.map(\.time),[2,4]); XCTAssertEqual(p.objects[0].resolved(at:4).x,50)
    var q = groupFixture(); var opacity = ObjectSegment(time:1); opacity.opacity = 0.5
    q.objects[1].segments = [opacity]; try q.inheritSegment(q.objects[1].id,at:1)
    XCTAssertEqual(q.objects[0].segments?.first?.text,"Independent","A group opacity edit must not delete a child's independent event")
  }
  func testImportedGroupMoveRetainsIndependentMemberParametersWithoutSnapshot() throws {
    var p = groupFixture(); let group = p.objects[1].id
    var event = ObjectSegment(time:1); event.x = 30; p.objects[1].segments = [event]
    p.objects[0].segments?[0].x = 30
    try p.retimeSegment(group,at:1,to:2)
    XCTAssertEqual(p.objects[0].resolved(at:1.5).text,"Independent")
    XCTAssertEqual(p.objects[0].resolved(at:1.5).x,10)
    XCTAssertEqual(p.objects[0].resolved(at:2.5).x,30)
  }
  func testLaterNestedGroupEditsAreProtectedFromUnsafeParentRetiming() throws {
    var p = groupFixture(); let outer = DisplayObject(name:"Outer",kind:.group)
    p.objects[1].parentID = outer.id; p.objects.append(outer)
    var v = p.displayForEditing(outer.id,at:1)!; v.x = 30; p.updateDisplay(v,at:1)
    v = p.displayForEditing(p.objects[1].id,at:1)!; v.x = 50; p.updateDisplay(v,at:1)
    let original = p
    XCTAssertThrowsError(try p.retimeSegment(outer.id,at:1,to:2)); XCTAssertEqual(p,original)
  }
}
