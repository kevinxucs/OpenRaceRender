import AVFoundation
import AppKit
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
    // The video must be AppKit's backing surface, not an unmanaged sibling of
    // the selection overlay that AppKit can reorder during view redraws.
    XCTAssertTrue(preview.layer === surface)
    XCTAssertTrue(surface.player === player)
    XCTAssertEqual(surface.frame, preview.frame)
    for size in [NSSize(width: 640, height: 360), NSSize(width: 1280, height: 720)] {
      preview.setFrameSize(size)
      preview.needsLayout = true
      preview.layoutSubtreeIfNeeded()
      preview.needsDisplay = true
      preview.displayIfNeeded()
      XCTAssertTrue(preview.layer === surface)
      XCTAssertTrue(surface.player === player)
      XCTAssertEqual(preview.overlay.frame, preview.bounds)
      XCTAssertEqual(surface.bounds.size, size)
      XCTAssertEqual(surface.frame, preview.frame)
    }
    preview.removeFromSuperview()
    container.addSubview(preview)
    preview.refresh()
    XCTAssertTrue(preview.layer === surface)
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
}
