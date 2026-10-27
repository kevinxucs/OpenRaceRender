import XCTest
@testable import RaceCore

final class TemplateSelectionTests: XCTestCase {
  func fixture() -> RaceProject {
    var p = RaceProject()
    p.inputs = [MediaInput(name: "private-camera.mov", path: "/private/session.mov", kind: "video", legacyIndex: 4),
      MediaInput(name: "private-logger.csv", path: "/private/data.csv", kind: "data", legacyIndex: 9),
      MediaInput(name: "Other logger", path: "/private/other.csv", kind: "data", legacyIndex: 12)]
    var camera = DisplayObject(name: "Camera", kind: .video); camera.inputIndex = 4
    var tyre = DisplayObject(name: "Tyres", kind: .temperature); tyre.inputIndex = 9
    var pedal = DisplayObject(name: "Pedals", kind: .throttle); pedal.inputIndex = 9
    var unrelated = DisplayObject(name: "Speed", kind: .speed); unrelated.inputIndex = 12
    var outer = DisplayObject(name: "Dashboard", kind: .group); outer.inputIndex = -1; outer.opacity = 0.5
    var inner = DisplayObject(name: "Lower cluster", kind: .group); inner.inputIndex = -1; inner.opacity = 0.4; inner.parentID = outer.id
    tyre.parentID = inner.id; pedal.parentID = outer.id; unrelated.parentID = inner.id
    var hide = ObjectSegment(time: 2); hide.visible = false
    var show = ObjectSegment(time: 3); show.visible = true
    outer.segments = [hide,show]
    p.objects = [camera,tyre,unrelated,inner,pedal,outer]
    return p
  }

  func testSubsetRetainsOnlyNecessaryGroupsAndPreservesInheritedState() throws {
    let p = fixture(), tyre = p.objects[1], pedal = p.objects[4]
    let original = p
    let result = try p.reusableLayout(objectIDs: [tyre.id,pedal.id],
      objectNames: [tyre.id:"Tyre display",pedal.id:"Pedal cluster",p.objects[5].id:"HUD"], inputNames: [9:"Vehicle data"])
    XCTAssertEqual(result.objects.map(\.name),["Tyre display","Lower cluster","Pedal cluster","HUD"])
    XCTAssertEqual(result.objects.map(\.id),[tyre.id,p.objects[3].id,pedal.id,p.objects[5].id])
    XCTAssertEqual(result.inputs.map(\.legacyIndex),[9]); XCTAssertEqual(result.inputs.first?.name,"Vehicle data")
    XCTAssertEqual(result.inputs.first?.path,"")
    for time in [0.0,2.5,3.5] {
      let before = try XCTUnwrap(p.resolvedObjects(at:time).first { $0.id == tyre.id })
      let after = try XCTUnwrap(result.resolvedObjects(at:time).first { $0.id == tyre.id })
      XCTAssertEqual(before.visible,after.visible); XCTAssertEqual(before.opacity,after.opacity)
      XCTAssertEqual(before.x,after.x)
    }
    XCTAssertEqual(p,original,"Export names and selections must not modify the source project")
    XCTAssertThrowsError(try p.reusableLayout(objectIDs: []))
    XCTAssertThrowsError(try p.reusableLayout(objectIDs: [UUID()]))
  }

  func testSavedGroupHistoryIncludesOnlySelectedMembersAndTheirSourceRoles() throws {
    var p = fixture()
    var current = ObjectSegment(time: 4); current.inputIndex = 9
    var prior = current; prior.inputIndex = 12
    p.objects[1].segments = [current]
    var event = ObjectSegment(time: 4)
    event.groupChildrenBefore = [p.objects[1].id:[prior],p.objects[2].id:[prior]]
    p.objects[3].segments = [event]
    let result = try p.reusableLayout(objectIDs:[p.objects[1].id], inputNames:[9:"Primary",12:"Alternate"])
    XCTAssertEqual(result.inputs.map(\.name),["Primary","Alternate"])
    let history = try XCTUnwrap(result.objects.first { $0.kind == .group && $0.name == "Lower cluster" }?.segments?.first?.groupChildrenBefore)
    XCTAssertEqual(Set(history.keys),[p.objects[1].id])
    var next = RaceProject()
    next.inputs = [MediaInput(name:"Next primary",path:"",kind:"data",legacyIndex:42),
      MediaInput(name:"Next alternate",path:"",kind:"data",legacyIndex:77)]
    next.applyLayout(result,replace:false,mapping:[9:42,12:77])
    let child = try XCTUnwrap(next.objects.first { $0.name == "Tyres" })
    let group = try XCTUnwrap(next.objects.first { $0.name == "Lower cluster" })
    XCTAssertNotEqual(child.id,p.objects[1].id)
    XCTAssertEqual(group.segments?.first?.groupChildrenBefore?[child.id]?.first?.inputIndex,77)
    next.removeDisplaySegment(group.id,at:4)
    XCTAssertEqual(next.objects.first { $0.id == child.id }?.resolved(at:4).inputIndex,77)
  }

  func testRenamedSubsetRoundTripsNativeAndLegacyTemplatesAndMapsRoles() throws {
    var p = fixture()
    p.objects.removeAll { $0.kind == .group }
    for i in p.objects.indices { p.objects[i].parentID = nil }
    let selected: Set<UUID> = [p.objects[1].id,p.objects[2].id]
    for i in p.objects.indices where selected.contains(p.objects[i].id) { p.objects[i].kind = .speed }
    let result = try p.reusableLayout(objectIDs:selected,
      objectNames:[p.objects[1].id:"Tyre panel",p.objects[2].id:"Speed panel"],
      inputNames:[9:"Vehicle sensors",12:"GPS logger"])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:root) }
    for ext in ["orrt","rrt"] {
      let url = root.appendingPathComponent("subset."+ext)
      if ext == "rrt" { try LegacyWriter.data(result,format:.rrt).write(to:url) }
      else { try result.save(url) }
      let reopened = try RaceProject.read(url)
      XCTAssertEqual(reopened.objects.map(\.name),result.objects.map(\.name))
      XCTAssertEqual(Set(reopened.inputs.map(\.name)),["Vehicle sensors","GPS logger"])
      XCTAssertTrue(reopened.inputs.allSatisfy { $0.path.isEmpty })
      let primary = try XCTUnwrap(reopened.inputs.first { $0.name == "Vehicle sensors" })
      let alternate = try XCTUnwrap(reopened.inputs.first { $0.name == "GPS logger" })
      var next = RaceProject()
      next.inputs = [MediaInput(name:"A",path:"",kind:"data",legacyIndex:21),MediaInput(name:"B",path:"",kind:"data",legacyIndex:22)]
      next.applyLayout(reopened,replace:false,mapping:[primary.legacyIndex:21,alternate.legacyIndex:22])
      XCTAssertEqual(next.objects.first { $0.name == "Tyre panel" }?.inputIndex,21)
      XCTAssertEqual(next.objects.first { $0.name == "Speed panel" }?.inputIndex,22)
    }
  }

  func testSingleMemberExportPreservesLegacyParentAndWhitespaceNamesFallBack() throws {
    var p = fixture()
    let member = p.objects[1].id
    p.objects[1].parentID = nil; p.objects[1].parentIndex = 3
    p.objects[3].legacyIndex = 3
    let layout = try p.reusableLayout(objectIDs:[member],objectNames:[member:" \n"],inputNames:[9:" "])
    XCTAssertEqual(layout.objects.first?.name,"Tyres")
    XCTAssertEqual(layout.inputs.first?.name,"private-logger.csv")
    XCTAssertEqual(layout.ancestors(of:member).count,2)
    XCTAssertEqual(try p.reusableLayout(selected:member).objects.count,3)
  }
  func testStaticArtworkAndGroupsDoNotCreateSpuriousInputRoles() throws {
    var p = fixture()
    p.objects[1].kind = .shape
    p.objects[3].inputIndex = 12; p.objects[5].inputIndex = 9
    let layout = try p.reusableLayout(objectIDs:[p.objects[1].id])
    XCTAssertTrue(layout.inputs.isEmpty)
  }
  func testReplacingOverlayRetainsGroupedCamerasWithoutRetainingOldWidgets() throws {
    var p = fixture()
    let camera = p.objects[0].id, group = p.objects[5].id, oldWidget = p.objects[2].id
    p.objects[0].parentID = group
    let layout = try p.reusableLayout(objectIDs:[p.objects[1].id])
    let original = p
    p.applyLayout(layout,replace:true,mapping:[9:9])
    XCTAssertEqual(p.objects.count,5)
    XCTAssertTrue(p.objects.contains { $0.id == camera })
    XCTAssertTrue(p.objects.contains { $0.id == group })
    XCTAssertFalse(p.objects.contains { $0.id == oldWidget })
    XCTAssertEqual(p.ancestors(of:camera),[group])
    for o in p.objects where o.parentID != nil { XCTAssertNotNil(p.parentID(of:o)) }
    for time in [0.0,2.5,3.5] {
      let before = try XCTUnwrap(original.resolvedObjects(at:time).first { $0.id == camera })
      let after = try XCTUnwrap(p.resolvedObjects(at:time).first { $0.id == camera })
      XCTAssertEqual(after.visible,before.visible); XCTAssertEqual(after.opacity,before.opacity)
    }
  }
}
