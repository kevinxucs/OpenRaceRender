import RaceCore
import XCTest
@testable import OpenRaceRender

final class TimelineEditingTests: XCTestCase {
  @MainActor func testRetimeUndoRedoKeepsInspectorOnStableEventAndResetIsUndoable() throws {
    let model = EditorModel(); model.addObject(.text)
    let id = try XCTUnwrap(model.selected)
    var s = ObjectSegment(time:1); s.text = "Event"; model.project.objects[0].segments = [s]
    model.editingSegment = 1
    let before = model.project
    model.moveSelectedSegment(to:2)
    XCTAssertEqual(model.editingSegment,2); XCTAssertEqual(model.project.objects[0].segments?.first?.id,s.id)
    model.undo(); XCTAssertEqual(model.project,before); XCTAssertEqual(model.editingSegment,1)
    model.redo(); XCTAssertEqual(model.editingSegment,2)
    model.setSelectedSegmentField(.text,enabled:false)
    XCTAssertEqual(model.project.objects[0].resolved(at:3).text,"Your text")
    model.undo(); XCTAssertEqual(model.project.objects[0].resolved(at:3).text,"Event")
    let current = model.project
    model.moveSelectedSegment(to:-1); XCTAssertEqual(model.project,current); XCTAssertNotNil(model.error)
  }
  @MainActor func testTimelineZoomUsesWindowBoundsWithoutDirtyingProject() {
    let model = EditorModel(); model.project.explicitDuration = 100; model.time = 40; model.dirty = false
    model.zoomTimeline(2)
    XCTAssertEqual(model.timelineSpan,50); XCTAssertEqual(model.timelineLower,15); XCTAssertEqual(model.timelineUpper,65)
    XCTAssertFalse(model.dirty)
    model.timelineStart = 999; XCTAssertEqual(model.timelineLower,50)
    model.resetTimelineZoom(); XCTAssertEqual(model.timelineLower,0); XCTAssertEqual(model.timelineUpper,100)
    XCTAssertFalse(model.dirty)
  }
}
