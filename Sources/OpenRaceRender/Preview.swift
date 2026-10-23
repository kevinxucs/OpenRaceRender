import AVFoundation
import RaceCore
import SwiftUI

struct Preview: NSViewRepresentable {
  @ObservedObject var model: EditorModel
  func makeNSView(context: Context) -> PreviewView {
    let v = PreviewView()
    v.model = model
    return v
  }
  func updateNSView(_ view: PreviewView, context: Context) {
    view.model = model
    view.refresh()
  }
}

@MainActor final class OverlayView: NSView {
  weak var model: EditorModel?
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    guard let m = model, let c = NSGraphicsContext.current?.cgContext else { return }
    if m.previewPlayer == nil {
      OverlayRenderer.draw(c, scene: m.scene, time: m.time, size: bounds.size, selection: m.selected)
    } else if let base = m.project.objects.first(where: { $0.id == m.selected }) {
      let r = OverlayRenderer.rect(base.resolved(at: m.time), size: bounds.size)
      c.setStrokeColor(OverlayRenderer.color("#5EE0B5")); c.setLineWidth(1.5); c.stroke(r)
      c.setFillColor(OverlayRenderer.color("#5EE0B5")); c.fill(CGRect(x: r.maxX-4, y: r.maxY-4, width: 8, height: 8))
    }
  }
}

@MainActor final class PreviewView: NSView {
  weak var model: EditorModel?
  let overlay = OverlayView()
  let compositionLayer = AVPlayerLayer()
  var dragging: UUID?
  var initialPoint = CGPoint.zero
  var initialObject: DisplayObject?
  var resizing = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    compositionLayer.videoGravity = .resizeAspect
    layer?.addSublayer(compositionLayer)
    overlay.wantsLayer = true
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
    overlay.frame = bounds
    overlay.model = m
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if compositionLayer.player !== m.previewPlayer {
      compositionLayer.player = m.previewPlayer
      m.syncPlayers(play: m.playing)
    }
    compositionLayer.frame = bounds
    CATransaction.commit()
    overlay.needsDisplay = true
  }
  override func mouseDown(with event: NSEvent) {
    guard let m = model else { return }
    window?.makeFirstResponder(self)
    let p = convert(event.locationInWindow, from: nil)
    if let selected = m.project.objects.first(where: { $0.id == m.selected }) {
      let r = OverlayRenderer.rect(selected.resolved(at: m.time), size: bounds.size)
      if hypot(p.x - r.maxX, p.y - r.maxY) < 10 {
        dragging = selected.id
        initialObject = selected.resolved(at: m.time)
        initialPoint = p
        resizing = true
        m.checkpoint()
        return
      }
    }
    guard
      let o = m.project.objects.map({ $0.resolved(at: m.time) }).reversed().first(where: {
        $0.visible && m.time >= $0.start && m.time < $0.end && ![.audio, .group].contains($0.kind)
          && OverlayRenderer.rect($0, size: bounds.size).contains(p)
      })
    else {
      m.selected = nil
      return
    }
    m.selected = o.id
    m.selectedInput = nil
    dragging = o.id
    initialPoint = p
    initialObject = o
    resizing = false
    m.checkpoint()
  }
  override func mouseDragged(with event: NSEvent) {
    guard let m = model, let id = dragging, var o = initialObject,
      let i = m.project.objects.firstIndex(where: { $0.id == id })
    else { return }
    let p = convert(event.locationInWindow, from: nil)
    let dx = (p.x - initialPoint.x) / bounds.width * 100
    let dy = (p.y - initialPoint.y) / bounds.height * 100
    if resizing {
      o.width = max(1, o.width + dx)
      o.height = max(1, o.height + dy)
    } else {
      o.x += dx
      o.y += dy
    }
    if event.modifierFlags.contains(.shift) {
      o.x = round(o.x)
      o.y = round(o.y)
      o.width = round(o.width)
      o.height = round(o.height)
    }
    m.updateObject(at: i, value: o)
    refresh()
  }
  override func mouseUp(with event: NSEvent) {
    dragging = nil
    initialObject = nil
  }
  override func keyDown(with event: NSEvent) {
    guard let m = model else { return }
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
