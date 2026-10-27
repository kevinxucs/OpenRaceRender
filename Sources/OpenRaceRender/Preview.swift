import AVFoundation
import RaceCore
import SwiftUI

struct Preview: NSViewRepresentable {
  @ObservedObject var model: EditorModel
  var interactive = true
  func makeNSView(context: Context) -> PreviewView {
    let v = PreviewView()
    v.model = model
    v.interactive = interactive
    if interactive { model.canvasView = v }
    return v
  }
  func updateNSView(_ view: PreviewView, context: Context) {
    view.model = model
    view.interactive = interactive
    if interactive { model.canvasView = view }
    view.refresh()
  }
  static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.disconnect() }
}

@MainActor final class OverlayView: NSView {
  weak var model: EditorModel?
  var showSelection = true
  var dropPoint: CGPoint?
  var marquee: CGRect?
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    guard let m = model, let c = NSGraphicsContext.current?.cgContext else { return }
    if m.previewPlayer == nil {
      OverlayRenderer.draw(c, scene: m.designScene, time: m.time, size: bounds.size)
    }
    if showSelection, let box = m.project.selectionBounds(m.selectedIDs, at: m.time) {
      func canvas(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX*bounds.width/100, y: r.minY*bounds.height/100,
          width: r.width*bounds.width/100, height: r.height*bounds.height/100)
      }
      c.setStrokeColor(OverlayRenderer.color("#5EE0B5")); c.setLineWidth(1)
      for id in m.project.selectionRoots(m.selectedIDs) {
        if let r = m.project.selectionBounds([id], at: m.time) { c.stroke(canvas(r)) }
      }
      let r = canvas(box)
      c.setLineWidth(1.5); c.stroke(r)
      c.setFillColor(OverlayRenderer.color("#5EE0B5")); c.fill(CGRect(x: r.maxX-4, y: r.maxY-4, width: 8, height: 8))
    }
    if let r = marquee {
      c.setFillColor(OverlayRenderer.color("#5EE0B5", alpha: 0.12)); c.fill(r)
      c.setStrokeColor(OverlayRenderer.color("#5EE0B5")); c.stroke(r)
    }
    if let point = dropPoint {
      c.setFillColor(OverlayRenderer.color("#5EE0B5", alpha: 0.25))
      c.fillEllipse(in: CGRect(x: point.x-20, y: point.y-20, width: 40, height: 40))
      c.setStrokeColor(OverlayRenderer.color("#5EE0B5")); c.setLineWidth(2)
      c.strokeEllipse(in: CGRect(x: point.x-20, y: point.y-20, width: 40, height: 40))
    }
  }
}

/// AVPlayerLayer owns opaque contents. Host it without AppKit drawing into it;
/// keep the selection overlay in a separate sibling view.
@MainActor final class PlayerSurfaceView: NSView {
  let playerLayer = AVPlayerLayer()
  override init(frame: NSRect) {
    super.init(frame: frame)
    layer = playerLayer
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    playerLayer.backgroundColor = NSColor.black.cgColor
    playerLayer.videoGravity = .resizeAspect
  }
  required init?(coder: NSCoder) { fatalError() }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class PreviewView: NSView {
  weak var model: EditorModel?
  let overlay = OverlayView()
  let videoSurface = PlayerSurfaceView()
  var compositionLayer: AVPlayerLayer { videoSurface.playerLayer }
  var interactive = true
  var dragCheckpoint = false
  var dragging: UUID?
  var initialPoint = CGPoint.zero
  var initialProject: RaceProject?
  var initialBounds: CGRect?
  var initialSelection: Set<UUID> = []
  var selectingArea = false
  var resizing = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Composition preview · drop widgets here")
    layer?.backgroundColor = NSColor.black.cgColor
    overlay.wantsLayer = true
    addSubview(videoSurface)
    addSubview(overlay)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var acceptsFirstResponder: Bool { true }
  override func layout() {
    super.layout()
    refresh()
  }
  func refresh() {
    guard let m = model else { return }
    videoSurface.frame = bounds
    compositionLayer.contentsScale = window?.backingScaleFactor ?? 2
    overlay.frame = bounds
    overlay.model = m
    overlay.showSelection = interactive
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // Only the active preview owns video output. Opening the sync wizard must
    // detach the canvas, and dismissing it must explicitly return ownership.
    let player = interactive != m.showSync ? m.previewPlayer : nil
    if compositionLayer.player !== player {
      compositionLayer.player = player
      m.syncPlayers(play: m.playing)
    }
    CATransaction.commit()
    overlay.needsDisplay = true
  }
  func disconnect() {
    compositionLayer.player = nil
    overlay.model = nil
    if model?.canvasView === self { model?.canvasView = nil }
    model = nil
  }
  override func mouseDown(with event: NSEvent) {
    guard interactive, let m = model, bounds.width > 0, bounds.height > 0 else { return }
    window?.makeFirstResponder(self)
    let p = convert(event.locationInWindow, from: nil)
    dragCheckpoint = false; initialPoint = p; resizing = false; selectingArea = false
    initialProject = nil; initialBounds = nil; dragging = nil
    if let box = m.project.selectionBounds(m.selectedIDs, at: m.time),
      hypot(p.x-box.maxX*bounds.width/100, p.y-box.maxY*bounds.height/100) < 10 {
      resizing = true
    } else if let o = m.project.resolvedObjects(at: m.time).reversed().first(where: {
      $0.visible && m.time >= $0.start && m.time < $0.end && ![.audio, .group].contains($0.kind)
        && ($0.kind != .video || m.selectedIDs.contains($0.id) || event.modifierFlags.contains(.option))
        && OverlayRenderer.rect($0, size: bounds.size).contains(p)
    }) {
      let id = m.canvasSelectionID(o.id, individual: event.modifierFlags.contains(.option))
      if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
        m.selectDisplay(id, modifiers: [.command])
      } else if !m.selectedIDs.contains(id) { m.selected = id; m.selectedInput = nil }
      if !m.selectedIDs.contains(id) { refresh(); return }
    } else {
      initialSelection = event.modifierFlags.intersection([.command, .shift]).isEmpty ? [] : m.selectedIDs
      m.setSelection(initialSelection); selectingArea = true; return
    }
    dragging = m.selected
    initialProject = m.project
    initialBounds = m.project.selectionBounds(m.selectedIDs, at: m.time)
  }
  override func mouseDragged(with event: NSEvent) {
    guard let m = model else { return }
    let p = convert(event.locationInWindow, from: nil)
    if selectingArea {
      let area = CGRect(x: min(p.x,initialPoint.x), y: min(p.y,initialPoint.y),
        width: abs(p.x-initialPoint.x), height: abs(p.y-initialPoint.y))
      overlay.marquee = area
      let ids = m.project.resolvedObjects(at: m.time).filter {
        $0.visible && m.time >= $0.start && m.time < $0.end && ![.audio,.group].contains($0.kind)
          && ($0.kind != .video || event.modifierFlags.contains(.option))
          && area.intersects(OverlayRenderer.rect($0, size: bounds.size))
      }.map { m.canvasSelectionID($0.id, individual: event.modifierFlags.contains(.option)) }
      m.setSelection(initialSelection.union(ids)); refresh(); return
    }
    guard dragging != nil, var project = initialProject, let from = initialBounds else { return }
    if !dragCheckpoint { m.checkpoint(); dragCheckpoint = true }
    let dx = (p.x-initialPoint.x)/bounds.width*100, dy = (p.y-initialPoint.y)/bounds.height*100
    var to = from
    if resizing {
      if m.lockWidgetAspect, from.width > 0, from.height > 0 {
        let change = abs(dx/from.width) > abs(dy/from.height) ? dx/from.width : dy/from.height
        let scale = max(max(0.1/from.width,0.1/from.height),1+change)
        to.size = CGSize(width: from.width*scale, height: from.height*scale)
      } else { to.size = CGSize(width: max(0.1,from.width+dx), height: max(0.1,from.height+dy)) }
    } else { to = from.offsetBy(dx: dx, dy: dy) }
    if event.modifierFlags.contains(.shift) {
      to.origin = CGPoint(x: round(to.minX), y: round(to.minY))
      if resizing { to.size = CGSize(width: max(1,round(to.width)), height: max(1,round(to.height))) }
    }
    project.transformDisplays(m.selectedIDs, from: from, to: to, at: m.editingSegment)
    m.project = project; refresh()
  }
  override func mouseUp(with event: NSEvent) {
    dragging = nil; initialProject = nil; initialBounds = nil
    selectingArea = false; overlay.marquee = nil; refresh()
  }
  override func keyDown(with event: NSEvent) {
    guard let m = model else { return }
    if event.modifierFlags.contains(.option), [123, 124, 125, 126].contains(event.keyCode), m.selected != nil {
      let amount = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
      m.nudgeWidget(x: event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0,
        y: event.keyCode == 125 ? -amount : event.keyCode == 126 ? amount : 0)
      refresh(); return
    }
    if event.keyCode == 49 {
      m.togglePlayback()
      return
    }
    if event.keyCode == 123 {
      m.seek(m.time - 1 / m.project.fps)
      return
    }
    if event.keyCode == 124 {
      m.seek(m.time + 1 / m.project.fps)
      return
    }
    if event.keyCode == 51 {
      m.deleteSelected()
      return
    }
    super.keyDown(with: event)
  }
}
