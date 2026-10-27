import AppKit
import CoreGraphics
import CoreImage

public struct RenderScene: @unchecked Sendable {
  public var project: RaceProject
  public var telemetry: [Int: Telemetry]
  public init(project: RaceProject, telemetry: [Int: Telemetry]) {
    self.project = project
    self.telemetry = telemetry
  }
}

public enum OverlayRenderer {
  public static let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!
  // Match AVFoundation's destination surface so compositing widgets does not
  // require a fresh RGBA/BGRA conversion for every intermediate bitmap.
  public static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
  public static func rect(_ o: DisplayObject, size: CGSize) -> CGRect {
    CGRect(
      x: o.x * size.width / 100, y: o.y * size.height / 100, width: o.width * size.width / 100,
      height: o.height * size.height / 100)
  }
  public static func color(_ hex: String, alpha: Double = 1) -> CGColor {
    let v = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x5ee0b5
    return CGColor(colorSpace:colorSpace,components:[Double((v >> 16) & 255)/255,
      Double((v >> 8) & 255)/255,Double(v & 255)/255,alpha])!
  }
  public static func draw(
    _ c: CGContext, scene: RenderScene, time: Double, size: CGSize, selection: UUID? = nil
  ) {
    c.saveGState()
    c.clip(to: CGRect(origin: .zero, size: size))
    for o in scene.project.resolvedObjects(at: time)
    where o.visible && time >= o.start && time < o.end
      && ![.video, .audio, .group].contains(o.kind)
    {
      let r = LegacyStyledRenderer.contentRect(o,in:rect(o,size:size))
      guard r.width > 0 && r.height > 0 else { continue }
      c.saveGState()
      c.setAlpha(o.opacity)
      c.clip(to: r)
      let data = scene.telemetry[o.inputIndex]
      let placement = scene.project.media(for:o.inputIndex,at:time)
      if o.legacyType != nil,(o.timerSettings?.usesSourceClock ?? true), (o.kind != .image || o.imageUsesData), placement == nil,
        scene.project.inputs.contains(where:{ $0.legacyIndex == o.inputIndex && $0.kind == "data" }) {
        c.restoreGState();continue
      }
      if o.legacyType == 50,(o.timerSettings?.usesSourceClock ?? true),o.legacyActivation == 0,placement == nil {
        c.restoreGState();continue
      }
      let t = placement?.sourceTime(at:time) ?? -1
      let segmentStart = max(o.start,(o.segments ?? []).filter { $0.time <= time }.map(\.time).max() ?? o.start)
      let historyStart = max(segmentStart,placement?.start ?? 0)
      let interval = 1/max(1,scene.project.fps)
      let timeline = EnhancedTimeline(sourceStart:placement?.sourceTime(at:historyStart) ?? 0,
        sourceStep:interval*(placement?.rate ?? 1),displayStart:historyStart-segmentStart,frameInterval:interval,
        inputName:scene.project.inputs.first(where:{$0.legacyIndex == o.inputIndex})?.name ?? placement?.input.name)
      if let p = o.picture, o.kind != .image {
        c.translateBy(x: r.midX, y: r.midY)
        c.rotate(by: p.rotation * .pi / 180)
        c.scaleBy(x: p.flipX ? -1 : 1, y: p.flipY ? -1 : 1)
        c.translateBy(x: -r.midX, y: -r.midY)
      }
      if let artwork = o.artwork, o.kind != .image,!(o.kind == .map && o.mapSettings != nil), let image = NSImage(data:artwork), let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) { c.draw(cg,in:r) }
      if o.kind == .text, o.typography != nil {
        DrawingRenderer.text(c, object: o, rect: r, height: size.height)
        c.restoreGState(); continue
      }
      if o.kind == .shape, o.shape != nil {
        DrawingRenderer.shape(c, object: o, rect: r, height: size.height)
        c.restoreGState(); continue
      }
      if [.speed, .rpm, .gauge].contains(o.kind), GaugeDesignerRenderer.draw(c, object: o, rect: r, data: data, time: t, unit: scene.project.speedUnit) {
        c.restoreGState(); continue
      }
      if TimerDisplayRenderer.draw(c,object:o,rect:r,data:data,sourceTime:t,projectTime:time) { c.restoreGState(); continue }
      if MapComparisonRenderer.draw(c,object:o,rect:r,scene:scene,sourceTime:t,projectTime:time) { c.restoreGState(); continue }
      if MapDisplayRenderer.draw(c,object:o,rect:r,data:data,time:t) { c.restoreGState(); continue }
      if HUDRenderer.draw(c, object: o, rect: r, data: data, time: t, unit: scene.project.speedUnit) {
        c.restoreGState(); continue
      }
      let scriptTime = placement?.sourceTime(at:time) ?? max(0,time-historyStart)
      if LegacyEnhancedRenderer.draw(c,object:o,rect:r,data:data,time:scriptTime,unit:scene.project.speedUnit,timeline:timeline) {
        c.restoreGState(); continue
      }
      if LegacyMapRenderer.draw(c,object:o,rect:r,data:data,time:t) {
        c.restoreGState();continue
      }
      if LegacyStyledRenderer.draw(c,object:o,rect:r,data:data,time:t,unit:scene.project.speedUnit,canvasHeight:size.height) {
        c.restoreGState(); continue
      }
      if o.kind == .image {
        let sourcePicture = scene.project.inputs.first { $0.kind == "image" && !o.text.isEmpty && $0.path == o.text }?.picture
        if !ImageRenderer.draw(c,object:o,rect:r,data:data,sourceTime:t,projectTime:time,inputPicture:sourcePicture) {
          panel(c,r); text(c,"IMAGE",x:r.midX,y:r.midY,size:min(r.width,r.height)*0.1,color:"#97A6BA")
        }
      } else { renderObject(c, o: o, r: r, data: data, time: t, unit: scene.project.speedUnit) }
      c.restoreGState()
    }
    if let id = selection, let o = scene.project.displayForEditing(id, at: time) {
      let r = rect(o, size: size)
      c.setStrokeColor(color("#5EE0B5"))
      c.setLineWidth(1.5)
      c.stroke(r)
      for p in [
        CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
        CGPoint(x: r.maxX, y: r.maxY),
      ] {
        c.setFillColor(color("#5EE0B5"))
        c.fill(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
      }
    }
    c.restoreGState()
  }
  static func text(
    _ c: CGContext, _ string: String, x: Double, y: Double, size: Double, color: String = "#FFFFFF",
    align: Double = 0.5, weight: NSFont.Weight = .semibold
  ) {
    guard size > 0 && size.isFinite else { return }
    let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    let attr: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor(cgColor: self.color(color)) ?? NSColor.white,
    ]
    let s = NSAttributedString(string: string, attributes: attr)
    let ns = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    s.draw(at: CGPoint(x: x - s.size().width * align, y: y))
    NSGraphicsContext.restoreGraphicsState()
  }
  static func panel(_ c: CGContext, _ r: CGRect) {
    c.setFillColor(color("#0D1218", alpha: 0.78))
    c.addPath(
      CGPath(
        roundedRect: r, cornerWidth: min(10, r.height * 0.12),
        cornerHeight: min(10, r.height * 0.12), transform: nil))
    c.fillPath()
  }
  static func number(_ value: Double?, decimals: Int = 0) -> String {
    guard let v = value, v.isFinite else { return "—" }
    return String(format: "%.*f", decimals, v)
  }

  static func renderObject(
    _ c: CGContext, o: DisplayObject, r: CGRect, data: Telemetry?, time: Double, unit: String
  ) {
    let w = r.width
    let h = r.height
    let cx = r.midX
    let cy = r.midY
    let s = min(w, h)
    let accent = o.color
    func value(_ name: String, _ interp: Bool = true) -> Double? {
      data?.value(o.channel.isEmpty ? name : o.resolvedChannel, at: time, interpolate: interp)
    }
    switch o.kind {
    case .speed, .rpm, .gauge:
      let v = o.kind == .speed ? data?.speed(at: time, unit: unit, channel:o.resolvedChannel) : value(o.kind == .rpm ? "rpm" : o.resolvedChannel)
      gauge(
        c, r: r, value: v, minimum: o.minimum, maximum: o.maximum, settings: o.gauge ?? GaugeSettings(), label: o.kind == .speed ? unit.uppercased() : "RPM",
        accent: accent)
    case .map:
      guard let d = data, !d.mapPoints.isEmpty else {
        panel(c, r)
        text(c, "NO GPS", x: cx, y: cy, size: s * 0.08, color: "#9BA8B9")
        break
      }
      let pts = d.mapPoints
      let xs = pts.map(\.0)
      let ys = pts.map(\.1)
      let minX = xs.min()!
      let maxX = xs.max()!
      let minY = ys.min()!
      let maxY = ys.max()!
      let scale = min(w * 0.86 / max(0.000001, maxX - minX), h * 0.86 / max(0.000001, maxY - minY))
      func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: cx + (x - (minX + maxX) / 2) * scale, y: cy + (y - (minY + maxY) / 2) * scale)
      }
      c.setLineJoin(.round)
      c.setLineCap(.round)
      c.setStrokeColor(color("#111821", alpha: 0.8))
      c.setLineWidth(max(5, s * 0.035))
      c.beginPath()
      for (i, p) in pts.enumerated() {
        let q = point(p.0, p.1)
        if i == 0 { c.move(to: q) } else { c.addLine(to: q) }
      }
      c.strokePath()
      c.setStrokeColor(color("#E4EAF1"))
      c.setLineWidth(max(1.5, s * 0.012))
      c.beginPath()
      for (i, p) in pts.enumerated() {
        let q = point(p.0, p.1)
        if i == 0 { c.move(to: q) } else { c.addLine(to: q) }
      }
      c.strokePath()
      if let position = d.trackPosition(at:time) {
        let q = point(position.0,position.1)
        let radius = max(3, s * 0.028)
        c.setFillColor(color(accent))
        c.fillEllipse(
          in: CGRect(x: q.x - radius, y: q.y - radius, width: radius * 2, height: radius * 2))
      }
    case .gforce:
      let radius = s * 0.43
      c.setFillColor(color("#0D1218", alpha: 0.65))
      c.fillEllipse(
        in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
      c.setStrokeColor(color("#FFFFFF", alpha: 0.4))
      c.setLineWidth(1)
      for k in [0.5, 1.0] {
        c.strokeEllipse(
          in: CGRect(
            x: cx - radius * k, y: cy - radius * k, width: radius * k * 2, height: radius * k * 2))
      }
      c.move(to: CGPoint(x: cx - radius, y: cy))
      c.addLine(to: CGPoint(x: cx + radius, y: cy))
      c.move(to: CGPoint(x: cx, y: cy - radius))
      c.addLine(to: CGPoint(x: cx, y: cy + radius))
      c.strokePath()
      if let gx = data?.value("gx", at: time), let gy = data?.value(o.resolvedChannel, at: time) {
        let x = cx + max(-1, min(1, gy / 2)) * radius
        let y = cy + max(-1, min(1, gx / 2)) * radius
        c.setFillColor(color(accent))
        c.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        text(
          c, number(hypot(gx, gy), decimals: 2) + " G", x: cx, y: r.minY + h * 0.03, size: s * 0.1)
      }
    case .gear:
      panel(c, r)
      let v = data?.value(o.resolvedChannel,at:time,interpolate:false)
      text(c,GearEstimator.displayName(v),x:cx,y:r.minY+h*0.08,size:h*0.72,color:accent)
      if data?.provenance(for:o.resolvedChannel)?.kind == .gear {
        text(c,"EST",x:cx,y:r.minY+h*0.85,size:max(5,h*0.10),color:"#97A6BA")
      }
    case .throttle, .brake, .bar:
      let key = o.kind == .brake ? "brake" : "throttle"
      let v = value(key)
      panel(c, r)
      let inset = max(2, h * 0.09)
      let bar = CGRect(
        x: r.minX + inset, y: r.minY + inset,
        width: max(
          0,
          (w - inset * 2)
            * max(0, min(1, ((v ?? o.minimum) - o.minimum) / max(0.001, o.maximum - o.minimum)))),
        height: h - inset * 2)
      c.setFillColor(color(o.kind == .brake ? "#FF6C72" : accent, alpha: 0.85))
      c.fill(bar)
      text(
        c, o.name.uppercased() + "  " + number(v) + "%", x: cx, y: r.minY + h * 0.22,
        size: min(h * 0.42, w / 16))
    case .lights:
      let v = value("rpm")
      let active = (v ?? 0) / max(1, o.maximum)
      for i in 0..<8 {
        let d = min(h * 0.75, w / 9)
        let x = r.minX + (Double(i) + 0.5) * w / 8
        let col = i < 4 ? "#5EE0B5" : (i < 6 ? "#FFD66B" : "#FF616D")
        c.setFillColor(color(col, alpha: active > Double(i + 1) / 10 ? 1 : 0.16))
        c.fillEllipse(in: CGRect(x: x - d / 2, y: cy - d / 2, width: d, height: d))
      }
    case .lap, .timer, .delta, .bestLap, .bestTime:
      let current = data?.lap(at: time)
      let best = data?.bestLap
      var content = "—"
      var label = o.name.uppercased()
      var col = "#FFFFFF"
      switch o.kind {
      case .lap:
        content = current.map { String($0.number) } ?? "—"
        label = "LAP"
      case .timer:
        content = current.map { clockText(time - $0.start) } ?? "—"
        label = "LAP TIME"
      case .bestLap:
        content = best.map { String($0.number) } ?? "—"
        label = "BEST LAP"
      case .bestTime:
        content = best.map { clockText($0.duration) } ?? "—"
        label = "BEST TIME"
      case .delta:
        if let delta = data?.delta(at: time) {
          content = String(format: "%+.3f", delta)
          col = delta <= 0 ? accent : "#FF6C72"
        }
        label = "DELTA"
      default: break
      }
      panel(c, r)
      text(
        c, label, x: r.minX + w * 0.06, y: r.minY + h * 0.65, size: min(h * 0.20, w / 15),
        color: "#97A6BA", align: 0)
      text(
        c, content, x: r.minX + w * 0.06, y: r.minY + h * 0.08,
        size: min(h * 0.5, w / Double(max(3, content.count)) * 1.5), color: col, align: 0)
    case .temperature:
      let key = o.automaticChannel
      let v = value(key) ?? (o.channel.isEmpty ? data?.value(key, at: time) : nil)
      let radius = min(w * 0.2, h * 0.08)
      let base = CGPoint(x: cx, y: r.minY + h * 0.2)
      c.setStrokeColor(color("#FFFFFF", alpha: 0.7))
      c.setLineWidth(radius * 1.8)
      c.setLineCap(.round)
      c.move(to: base)
      c.addLine(to: CGPoint(x: cx, y: r.minY + h * 0.85))
      c.strokePath()
      c.setStrokeColor(color(accent))
      c.setLineWidth(radius * 1.1)
      c.move(to: base)
      c.addLine(
        to: CGPoint(
          x: cx,
          y: base.y + h * 0.65
            * max(0, min(1, ((v ?? 0) - o.minimum) / max(1, o.maximum - o.minimum)))))
      c.strokePath()
      c.setFillColor(color(accent))
      c.fillEllipse(
        in: CGRect(x: base.x - radius, y: base.y - radius, width: radius * 2, height: radius * 2))
      text(c, number(v) + "°", x: cx, y: r.minY, size: min(w * 0.33, h * 0.1))
    case .graph:
      GraphRenderer.draw(c, object: o, rect: r, data: data, time: time)
    case .text:
      let str = o.text.isEmpty ? o.name : o.text
      text(
        c, str, x: r.minX, y: r.minY + h * 0.15,
        size: min(h * 0.65, w / Double(max(1, str.count)) * 1.6), color: accent, align: 0)
    case .shape:
      c.setFillColor(color(accent))
      c.fill(r)
    case .image:
      // Image controls require both clocks: data mapping follows synchronization,
      // while flashing stays deterministic in the project timeline.
      if !ImageRenderer.draw(c,object:o,rect:r,data:data,sourceTime:time,projectTime:time) {
        panel(c,r); text(c,"IMAGE",x:cx,y:cy,size:s*0.1,color:"#97A6BA")
      }
    case .enhanced:
      panel(c, r)
      let v = value(o.channel)
      text(
        c, o.name.uppercased(), x: cx, y: r.minY + h * 0.6,
        size: min(h * 0.2, w / Double(max(1, o.name.count)) * 1.4), color: "#97A6BA")
      text(c, number(v, decimals: 1), x: cx, y: r.minY + h * 0.05, size: h * 0.45, color: accent)
    default: break
    }
  }
  static func sceneImagePath(_ o: DisplayObject) -> String? { o.text.isEmpty ? nil : o.text }
  static func gauge(
    _ c: CGContext, r: CGRect, value: Double?, minimum: Double, maximum: Double, settings g: GaugeSettings, label: String, accent baseAccent: String
  ) {
    let accent = (g.redline.map { (value ?? minimum) >= $0 } ?? false) ? g.warningColor : baseAccent
    let fraction = max(0, min(1, ((value ?? minimum)-minimum)/max(0.000001,maximum-minimum)))
    let radius = min(r.width, r.height) * 0.46
    let cx = r.midX
    let cy = r.midY
    if let image = g.backgroundImage.flatMap({ NSImage(data: $0) }) ?? g.backgroundPath.flatMap({ NSImage(contentsOfFile: $0) }), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { c.draw(cg, in: r) }
    if g.showFace {
      c.setFillColor(color("#0D1218", alpha: 0.65))
      c.fillEllipse(in: CGRect(x: cx-radius, y: cy-radius, width: radius*2, height: radius*2))
    }
    let sweep = max(1,min(360,g.sweep)) * .pi/180 * (g.counterClockwise ? -1 : 1)
    let start = Double.pi/2 - sweep/2 + g.rotation * .pi/180
    func point(_ fraction: Double, _ rr: Double) -> CGPoint {
      let a = start + fraction * sweep
      return CGPoint(x: cx + cos(a) * rr, y: cy - sin(a) * rr)
    }
    c.setLineCap(.round)
    for i in 0..<40 {
      let a = Double(i) / 40
      let b = Double(i + 1) / 40
      c.setStrokeColor(
        color(
          Double(i) / 40 <= fraction ? accent : "#FFFFFF",
          alpha: Double(i) / 40 <= fraction ? 0.95 : 0.17))
      c.setLineWidth(radius * 0.055)
      c.move(to: point(a, radius * 0.91))
      c.addLine(to: point(b, radius * 0.91))
      c.strokePath()
    }
    let range = max(0.000001, maximum-minimum)
    let interval = g.tickInterval.flatMap { $0.isFinite && $0 > 0 ? max(range/40,$0) : nil }
    let divisions = interval.map { max(1,Int(min(40,floor(range/$0)))) } ?? max(1,min(40,g.divisions))
    for i in 0...divisions {
      let tickValue = interval.map { minimum+Double(i)*$0 } ?? (minimum+Double(i)/Double(divisions)*range)
      let f = (tickValue-minimum)/range
      c.setStrokeColor(color("#FFFFFF", alpha: 0.7))
      c.setLineWidth(max(1, radius * 0.008))
      c.move(to: point(f, radius * 0.76))
      c.addLine(to: point(f, radius * 0.85))
      c.strokePath()
      let p = point(f, radius * 0.64)
      if g.showLabels {
        text(c, number(tickValue/max(0.000001,g.numberingScale)), x: p.x, y: p.y-radius*0.04, size: radius*0.1)
      }
    }
    if let v = value {
      let tip = point(max(0,min(1,(v-minimum)/max(0.000001,maximum-minimum))), radius*0.8)
      c.setStrokeColor(color(accent))
      c.setLineWidth(radius * 0.025)
      c.move(to: CGPoint(x: cx, y: cy))
      c.addLine(to: tip)
      c.strokePath()
    }
    if g.showNumber { text(c, number(value, decimals: max(0,min(6,g.decimals))), x: cx, y: cy-radius*0.13, size: radius*0.32) }
    if g.showLabels { text(c, g.label.isEmpty ? label : g.resolvedLabel(unit: label), x: cx, y: cy-radius*0.34, size: radius*0.11, color: "#B8C5D5") }
  }
}
