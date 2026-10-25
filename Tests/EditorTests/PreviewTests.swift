import AVFoundation
import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class PreviewTests: XCTestCase {
  @MainActor func testPlayerSurfaceSurvivesAppKitLayoutAndReattachment() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
    container.wantsLayer = true
    let preview = PreviewView(frame: NSRect(x: 20, y: 30, width: 720, height: 400))
    let model = EditorModel()
    let player = AVPlayer()
    model.previewPlayer = player
    preview.model = model
    container.addSubview(preview)
    preview.refresh()
    let surface = preview.compositionLayer
    // AppKit draws into the container and overlay, never AVPlayer's contents.
    XCTAssertFalse(preview.layer === surface)
    XCTAssertTrue(preview.videoSurface.layer === surface)
    XCTAssertTrue(surface.player === player)
    XCTAssertEqual(preview.videoSurface.frame, preview.bounds)
    for size in [NSSize(width: 640, height: 360), NSSize(width: 1280, height: 720)] {
      preview.setFrameSize(size)
      preview.needsLayout = true
      preview.layoutSubtreeIfNeeded()
      preview.needsDisplay = true
      preview.displayIfNeeded()
      XCTAssertTrue(preview.videoSurface.layer === surface)
      XCTAssertTrue(surface.player === player)
      XCTAssertEqual(preview.overlay.frame, preview.bounds)
      XCTAssertEqual(surface.bounds.size, size)
      XCTAssertEqual(preview.videoSurface.frame, preview.bounds)
    }
    preview.removeFromSuperview()
    container.addSubview(preview)
    preview.refresh()
    XCTAssertTrue(preview.videoSurface.layer === surface)
    XCTAssertTrue(surface.player === player)
    XCTAssertTrue(preview.overlay.superview === preview)
    let replacement = AVPlayer()
    model.previewPlayer = replacement
    preview.refresh()
    XCTAssertTrue(surface.player === replacement)
    model.previewPlayer = nil
    preview.refresh()
    XCTAssertNil(surface.player)
  }
  @MainActor func testVideoContentsAreHostedOutsideAppKitDrawing() {
    let container = NSView(frame:NSRect(x:0,y:0,width:800,height:450))
    container.wantsLayer = true
    let preview = PreviewView(frame:container.bounds), model = EditorModel()
    preview.model = model; container.addSubview(preview); preview.refresh()
    for _ in 0..<10 {
      preview.needsDisplay = true; preview.videoSurface.needsDisplay = true
      preview.overlay.needsDisplay = true; container.displayIfNeeded()
      XCTAssertNil(preview.compositionLayer.delegate,"AppKit must not own video-layer drawing")
      XCTAssertEqual(preview.videoSurface.layerContentsRedrawPolicy,.never)
      XCTAssertTrue(preview.videoSurface.subviews.isEmpty)
      XCTAssertTrue(preview.overlay.superview === preview)
      XCTAssertTrue(preview.subviews.first === preview.videoSurface)
      XCTAssertTrue(preview.subviews.last === preview.overlay)
      XCTAssertTrue(preview.hitTest(NSPoint(x:400,y:225)) === preview,"Video must not intercept widget dragging")
    }
  }
  @MainActor func testWizardTransfersPlayerOwnershipAndDismantlesCleanly() {
    let model = EditorModel(), player = AVPlayer()
    model.previewPlayer = player
    let canvas = PreviewView(), wizard = PreviewView()
    canvas.model = model; wizard.model = model; wizard.interactive = false; model.canvasView = canvas
    for _ in 0..<5 {
      model.showSync = false; wizard.refresh(); canvas.refresh()
      XCTAssertTrue(canvas.compositionLayer.player === player); XCTAssertNil(wizard.compositionLayer.player)
      model.showSync = true; canvas.refresh(); wizard.refresh()
      XCTAssertNil(canvas.compositionLayer.player); XCTAssertTrue(wizard.compositionLayer.player === player)
      model.showSync = false; canvas.refresh(); wizard.refresh()
      XCTAssertTrue(canvas.compositionLayer.player === player); XCTAssertNil(wizard.compositionLayer.player)
    }
    wizard.disconnect()
    XCTAssertNil(wizard.model); XCTAssertNil(wizard.compositionLayer.player)
    XCTAssertTrue(model.canvasView === canvas)
    canvas.disconnect()
    XCTAssertNil(model.canvasView); XCTAssertNil(canvas.compositionLayer.player)
  }
  @MainActor func testFrameOffsetNudgesUseProjectFPSAndSourceRateAndSupportUndoAndSave() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer { try? FileManager.default.removeItem(at:file) }
    for fps in [24.0,30.0,30000.0/1001,60.0] {
      for rate in [0.5,1.0,2.0] {
        let model = EditorModel()
        var input = MediaInput(name:"Data",path:"",kind:"data"); input.duration = 100; input.offset = -0.01
        var timing = InputTiming(); timing.rate = rate; input.timing = timing
        model.project.inputs = [input]; model.project.fps = fps; model.seek(10); model.dirty = false
        let before = model.project
        let event = try XCTUnwrap(model.project.placements.first).projectTime(for:20)
        model.nudgeOffset(input.id,frames:1)
        XCTAssertEqual(model.project.inputs[0].offset,input.offset+rate/fps,accuracy:1e-12)
        XCTAssertEqual(try XCTUnwrap(model.project.placements.first).projectTime(for:20),event-1/fps,accuracy:1e-12)
        XCTAssertEqual(model.time,10); XCTAssertTrue(model.dirty)
        try model.project.save(file)
        XCTAssertEqual(try RaceProject.read(file).inputs[0].offset,model.project.inputs[0].offset)
        model.undo(); XCTAssertEqual(model.project,before)
        model.nudgeOffset(input.id,frames:-1)
        XCTAssertEqual(model.project.inputs[0].offset,input.offset-rate/fps,accuracy:1e-12)
        model.nudgeOffset(input.id,frames:1)
        XCTAssertEqual(model.project.inputs[0].offset,input.offset,accuracy:1e-12)
      }
    }
  }
}
