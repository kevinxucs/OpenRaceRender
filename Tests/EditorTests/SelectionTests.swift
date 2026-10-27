import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class SelectionTests:XCTestCase {
  @MainActor func testModifierSelectionGroupingEditingDuplicateDeleteAndUndo() throws {
    let m = EditorModel(); m.addObject(.shape); m.addObject(.text); m.addObject(.gauge)
    let ids = m.project.objects.map(\.id)
    m.selectDisplay(ids[0]); m.selectDisplay(ids[2],modifiers:[.shift])
    XCTAssertEqual(m.selectedIDs,Set(ids))
    m.selectDisplay(ids[1],modifiers:[.command]); XCTAssertEqual(m.selectedIDs,[ids[0],ids[2]])
    let before = m.project; m.groupSelection()
    let group = try XCTUnwrap(m.selected)
    XCTAssertEqual(m.project.objects.count,4); XCTAssertEqual(m.selectedIDs,[group])
    XCTAssertEqual(m.canvasSelectionID(ids[0],individual:false),group)
    XCTAssertEqual(m.canvasSelectionID(ids[0],individual:true),ids[0])
    let binding = m.objectBinding(group); var g = binding.wrappedValue; g.x += 10; binding.wrappedValue = g
    XCTAssertEqual(m.project.objects[0].x,before.objects[0].x+10)
    m.undo(); XCTAssertEqual(m.project.objects[0].x,before.objects[0].x)
    m.undo(); XCTAssertEqual(m.project,before)
    m.redo(); m.selected = group; m.duplicate()
    XCTAssertEqual(m.project.objects.count,7)
    m.deleteSelected(); XCTAssertEqual(m.project.objects.count,4)
    m.undo(); XCTAssertEqual(m.project.objects.count,7)
    m.selected = group; m.ungroupSelection()
    XCTAssertEqual(m.selectedIDs.count,2); XCTAssertFalse(m.project.objects.contains { $0.id == group })
  }
  @MainActor func testSelectionGeometryAndNudgesPreserveRelativePlacementAndTimeline() throws {
    let m = EditorModel(); m.project.width = 1000; m.project.height = 500
    m.addObject(.shape); m.addObject(.text)
    m.project.objects[1].x = 50; m.project.objects[1].y = 40
    m.selectAllDisplays(); let before = m.project
    m.nudgeWidget(x:10,y:-5)
    XCTAssertEqual(m.project.objects[0].x,before.objects[0].x+1)
    XCTAssertEqual(m.project.objects[1].y,before.objects[1].y-1)
    m.undo(); XCTAssertEqual(m.project,before)
    m.selectionGeometry(\.size.width).wrappedValue = 100
    XCTAssertEqual(m.project.selectionBounds(m.selectedIDs)?.width ?? 0,100,accuracy:1e-10)
    m.undo(); XCTAssertEqual(m.project,before)
    m.groupSelection(); let group = try XCTUnwrap(m.selected)
    m.editingSegment = 4
    var g = m.objectBinding(group).wrappedValue; g.x += 10; m.objectBinding(group).wrappedValue = g
    XCTAssertEqual(m.project.objects[0].x,before.objects[0].x)
    XCTAssertEqual(m.project.objects[0].resolved(at:4).x,before.objects[0].x+10)
    m.removeSegment(); XCTAssertEqual(m.project.objects[0].resolved(at:4).x,before.objects[0].x)
  }
  @MainActor func testCanvasMarqueeIgnoresBackgroundCameraAndGroupDragHasOneUndo() throws {
    let m = EditorModel()
    var video = DisplayObject(name:"Background",kind:.video); video.x = 0; video.y = 0; video.width = 100; video.height = 100
    var a = DisplayObject(name:"A",kind:.shape); a.x = 10; a.y = 10; a.width = 20; a.height = 20
    var b = a; b.id = UUID(); b.name = "B"; b.x = 50
    m.project.objects = [video,a,b]
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    let view = PreviewView(frame:NSRect(x:0,y:0,width:800,height:400)); view.model = m; window.contentView = view
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double,flags:NSEvent.ModifierFlags = []) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:y),modifierFlags:flags,timestamp:0,
        windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    }
    view.mouseDown(with:try event(.leftMouseDown,40,10))
    view.mouseDragged(with:try event(.leftMouseDragged,600,160))
    view.mouseUp(with:try event(.leftMouseUp,600,160))
    XCTAssertEqual(m.selectedIDs,[a.id,b.id],"A full-frame camera must not prevent marquee selection of widgets")
    m.groupSelection(); let group = try XCTUnwrap(m.selected), before = m.project
    view.mouseDown(with:try event(.leftMouseDown,120,60))
    view.mouseDragged(with:try event(.leftMouseDragged,160,80))
    view.mouseDragged(with:try event(.leftMouseDragged,200,100))
    view.mouseUp(with:try event(.leftMouseUp,200,100))
    XCTAssertEqual(m.selected,group)
    XCTAssertEqual(m.project.objects[1].x,20); XCTAssertEqual(m.project.objects[2].x,60)
    m.undo(); XCTAssertEqual(m.project,before,"The entire drag must be one undo operation")
    view.mouseDown(with:try event(.leftMouseDown,120,60,flags:[.option]))
    XCTAssertEqual(m.selected,a.id,"Option-click should target an individual group member")
  }
}
