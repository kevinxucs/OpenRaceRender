import AppKit
import XCTest
@testable import RaceCore

final class GroupingTests: XCTestCase {
  func fixture() -> RaceProject {
    var p = RaceProject()
    var a = DisplayObject(name: "Left", kind: .shape); a.x = 10; a.y = 20; a.width = 20; a.height = 30
    a.shape = ShapeSettings(); a.color = "#FF0000"
    var b = DisplayObject(name: "Right", kind: .shape); b.x = 50; b.y = 30; b.width = 10; b.height = 20
    b.shape = ShapeSettings(); b.color = "#00FF00"
    p.objects = [a,b]; return p
  }
  func testGroupingUsesCanvasCoordinatesAndTransformsEveryMemberOnce() throws {
    var p = fixture(); let members = Set(p.objects.map(\.id))
    let group = try p.groupDisplays(members)
    XCTAssertEqual(p.selectionBounds([group]), CGRect(x: 10,y: 20,width: 50,height: 30))
    XCTAssertEqual(p.objects[0].x,10,"Grouping must not convert RR's absolute child coordinates")
    var value = try XCTUnwrap(p.displayForEditing(group)); value.x = 15; value.width = 100
    p.updateDisplay(value)
    XCTAssertEqual(p.objects[0].x,15); XCTAssertEqual(p.objects[0].width,40)
    XCTAssertEqual(p.objects[1].x,95); XCTAssertEqual(p.objects[1].width,20)
    XCTAssertEqual(p.resolvedObjects(at:0)[1].x,95,"Rendering must not apply the parent's geometry twice")
    XCTAssertEqual(p.selectionRoots(members.union([group])),[group])
  }
  func testNestedGroupsAndExistingGroupAdditionKeepStableParents() throws {
    var p = fixture(); let first = try p.groupDisplays(Set(p.objects.map(\.id)))
    var c = DisplayObject(name: "Third",kind:.text); c.x = 70; p.objects.append(c)
    XCTAssertEqual(try p.groupDisplays([first,c.id]), first,"One existing group should receive the extra display")
    XCTAssertEqual(p.parentID(of:c),nil)
    XCTAssertEqual(p.parentID(of:p.objects.last!),first)
    var d = DisplayObject(name:"Fourth",kind:.text); d.x = 80
    var e = DisplayObject(name:"Fifth",kind:.text); e.x = 90; p.objects += [d,e]
    let second = try p.groupDisplays([d.id,e.id]), outer = try p.groupDisplays([first,second])
    XCTAssertEqual(p.ancestors(of:c.id),[first,outer])
    let before = p.objects[0].x
    var group = try XCTUnwrap(p.displayForEditing(outer)); group.x += 10; p.updateDisplay(group)
    XCTAssertEqual(p.objects[0].x,before+10)
    XCTAssertThrowsError(try p.groupDisplays([c.id,d.id]),"Mixed parent selection must not silently change hierarchy")
  }
  func testGroupSegmentKeepsPriorChildEventAndRemovalRestoresIt() throws {
    var p = fixture(); let a = p.objects[0].id
    var existing = ObjectSegment(time:5); existing.x = 25; existing.text = "Keep this"; p.objects[0].segments = [existing]
    var later = ObjectSegment(time:10); later.x = 70; p.objects[0].segments?.append(later)
    let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    var value = try XCTUnwrap(p.displayForEditing(group,at:5)); value.x += 10
    p.updateDisplay(value,at:5)
    XCTAssertEqual(p.objects[0].x,10); XCTAssertEqual(p.objects[0].resolved(at:5).x,35)
    XCTAssertEqual(p.objects[0].resolved(at:5).text,"Keep this")
    XCTAssertEqual(p.objects[0].resolved(at:10).x,70,"Later explicit overrides retain their own values")
    let data = try JSONEncoder().encode(p); p = try JSONDecoder().decode(RaceProject.self,from:data)
    p.removeDisplaySegment(group,at:5)
    XCTAssertEqual(p.objects.first { $0.id == a }?.segments,[existing,later])
    XCTAssertEqual(p.selectionBounds([group],at:5)?.minX,25)
  }
  func testBaseGroupResizeTransformsExplicitFutureGeometry() throws {
    var p = fixture(); var s = ObjectSegment(time:4); s.x = 30; s.width = 10; p.objects[0].segments = [s]
    let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    var value = try XCTUnwrap(p.displayForEditing(group)); value.width *= 2; value.x += 5; p.updateDisplay(value)
    XCTAssertEqual(p.objects[0].resolved(at:4).x,55); XCTAssertEqual(p.objects[0].resolved(at:4).width,20)
  }
  func testDuplicateDeleteAndReorderOperateOnWholeSubtrees() throws {
    var p = fixture(); let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    let copies = p.duplicateDisplays([group,p.objects[0].id]); let copy = try XCTUnwrap(copies.first)
    XCTAssertEqual(p.objects.count,6); XCTAssertEqual(copies.count,1)
    XCTAssertEqual(p.descendants(of:[copy]).count,3)
    XCTAssertTrue(p.descendants(of:[group]).isDisjoint(with:p.descendants(of:[copy])))
    p.moveDisplays([group],direction:1)
    XCTAssertEqual(p.objects.suffix(3).last?.id,group)
    p.deleteDisplays([group]); XCTAssertEqual(p.objects.count,3)
    XCTAssertEqual(p.descendants(of:[copy]).count,3)
    XCTAssertEqual(p.selectionBounds([copy])?.minX,12)
  }
  func testApplyingSameLegacyTemplateTwiceDoesNotCrossWireGroups() throws {
    var layout = fixture(), group = DisplayObject(name:"Imported group",kind:.group)
    group.legacyIndex = 27
    layout.objects[0].legacyIndex = 2; layout.objects[0].parentIndex = 27
    layout.objects[1].legacyIndex = 5; layout.objects[1].parentIndex = 27
    layout.objects.append(group)
    var p = RaceProject(); p.applyLayout(layout,replace:false); p.applyLayout(layout,replace:false)
    XCTAssertEqual(p.objects.count,6)
    let groups = p.objects.filter { $0.kind == .group }
    XCTAssertNotEqual(groups[0].id,groups[1].id)
    for g in groups { XCTAssertEqual(p.descendants(of:[g.id]).count,3) }
    let portable = try p.reusableLayout(selected:groups[1].id)
    XCTAssertEqual(portable.objects.count,3); XCTAssertNil(portable.objects.last?.parentID)
    for format in [LegacyWriter.Format.rrp,.rrt] {
      let bytes = try LegacyWriter.data(p,format:format,seed:42)
      let decoded = format == .rrp ? try LegacyReader.project(bytes,base:URL(fileURLWithPath:"/tmp")) : try LegacyReader.template(bytes)
      for g in decoded.objects.filter({ $0.kind == .group }) { XCTAssertEqual(decoded.descendants(of:[g.id]).count,3) }
    }
  }
  func testLegacyGroupPlaceholderDoesNotReplaceChildBounds() {
    var p = fixture(), g = DisplayObject(name:"Native Group",kind:.group)
    g.x = 32.5; g.y = 32.5; g.width = 35; g.height = 35; g.legacyIndex = 4
    p.objects[0].parentIndex = 4; p.objects[1].parentIndex = 4; p.objects.append(g)
    XCTAssertEqual(p.displayForEditing(g.id)?.x,10)
    XCTAssertEqual(p.resolvedObjects(at:0)[0].x,10)
  }
  func testUngroupBakesVisibilityAndOpacityWithoutCumulativeMultiplication() throws {
    var p = fixture(); let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    let i = try XCTUnwrap(p.objects.firstIndex { $0.id == group }); p.objects[i].opacity = 0.5
    var hide = ObjectSegment(time:2); hide.visible = false
    var show = ObjectSegment(time:4); show.visible = true; p.objects[i].segments = [hide,show]
    let before = [0.0,1,2,3,4,5].map { p.resolvedObjects(at:$0).filter { $0.kind != .group } }
    XCTAssertEqual(p.ungroupDisplays([group]).count,2)
    for (i,t) in [0.0,1,2,3,4,5].enumerated() {
      let result = p.resolvedObjects(at:t)
      XCTAssertEqual(result.map(\.visible),before[i].map(\.visible))
      XCTAssertEqual(result.map(\.opacity),before[i].map(\.opacity))
    }
    XCTAssertTrue(p.objects.allSatisfy { p.parentID(of:$0) == nil })
  }
  func testGroupRenderingEqualsAlreadyTransformedChildrenAndHonorsHide() throws {
    var p = fixture(); let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    var g = try XCTUnwrap(p.displayForEditing(group)); g.x += 8; g.width *= 0.5; p.updateDisplay(g)
    func pixels(_ project:RaceProject) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:0,
        space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      OverlayRenderer.draw(c,scene:RenderScene(project:project,telemetry:[:]),time:0,size:CGSize(width:200,height:100))
      return try XCTUnwrap(c.makeImage()?.dataProvider?.data) as Data
    }
    var flat = p; flat.objects.removeAll { $0.kind == .group }; flat.stabilizeHierarchy()
    XCTAssertEqual(try pixels(p),try pixels(flat))
    p.objects[p.objects.count-1].visible = false
    XCTAssertTrue(try pixels(p).allSatisfy { $0 == 0 })
  }
  func testLegacyExportBakesGroupGatesOnceAndRejectsBrokenParents() throws {
    var p = fixture(); let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    let i = try XCTUnwrap(p.objects.firstIndex { $0.id == group })
    p.objects[i].opacity = 0.5; p.objects[i].start = 2; p.objects[i].end = 8
    var hide = ObjectSegment(time:4); hide.visible = false
    var show = ObjectSegment(time:6); show.visible = true; p.objects[i].segments = [hide,show]
    let decoded = try LegacyReader.project(LegacyWriter.data(p,format:.rrp),base:URL(fileURLWithPath:"/tmp"))
    for t in [0.0,2,4,6,8,9] {
      let expected = p.resolvedObjects(at:t).filter { $0.kind != .group }
      let actual = decoded.resolvedObjects(at:t).filter { $0.kind != .group }
      XCTAssertEqual(actual.map { $0.visible && t >= $0.start && t < $0.end },expected.map { $0.visible && t >= $0.start && t < $0.end })
      XCTAssertEqual(actual.map(\.opacity),expected.map(\.opacity))
    }
    p.objects[0].parentID = UUID(); XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    p.objects[0].parentID = nil; p.objects[0].parentIndex = 456
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    p.objects[0].parentIndex = -1; p.objects[i].parentID = group
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp)); XCTAssertEqual(p.resolvedObjects(at:0).count,3)
  }
  func testCopiedGroupSegmentRestoresCopiedMembersRatherThanOriginals() throws {
    var p = fixture(); var s = ObjectSegment(time:5); s.x = 25; p.objects[0].segments = [s]
    let group = try p.groupDisplays(Set(p.objects.map(\.id)))
    var value = try XCTUnwrap(p.displayForEditing(group,at:5)); value.x += 10; p.updateDisplay(value,at:5)
    let copy = try XCTUnwrap(p.duplicateDisplays([group]).first)
    p.removeDisplaySegment(copy,at:5)
    let copiedMembers = p.descendants(of:[copy]).subtracting([copy])
    XCTAssertEqual(p.objects.first { copiedMembers.contains($0.id) && $0.name == "Left" }?.resolved(at:5).x,27)
    XCTAssertEqual(p.objects[0].resolved(at:5).x,35)
    var base = try XCTUnwrap(p.displayForEditing(group)); base.x += 7; p.updateDisplay(base)
    p.removeDisplaySegment(group,at:5)
    XCTAssertEqual(p.objects[0].resolved(at:5).x,32,"A base move must also move saved member event geometry")

    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    defer { try? FileManager.default.removeItem(at:file) }
    let artwork = Data([1,2,3,4]); try artwork.write(to:file)
    var imageProject = fixture(); imageProject.objects[0].kind = .image
    imageProject.objects[0].artwork = artwork
    var imageEvent = ObjectSegment(time:5); imageEvent.text = file.path; imageProject.objects[0].segments = [imageEvent]
    let imageGroup = try imageProject.groupDisplays(Set(imageProject.objects.map(\.id)))
    var moved = try XCTUnwrap(imageProject.displayForEditing(imageGroup,at:5)); moved.x += 10
    imageProject.updateDisplay(moved,at:5)
    let portable = try imageProject.reusableLayout(selected:imageGroup)
    XCTAssertFalse(String(decoding:try JSONEncoder().encode(portable),as:UTF8.self).contains(file.path),"Group edit history must not retain external asset paths in templates")
    let snapshot = portable.objects.last?.segments?.first?.groupChildrenBefore?[portable.objects[0].id]?.first
    XCTAssertEqual(snapshot?.embeddedImage,artwork); XCTAssertEqual(snapshot?.text,"")
  }
}
