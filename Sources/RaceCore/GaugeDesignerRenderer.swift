import AppKit

enum GaugeDesignerRenderer {
  static func paint(_ base: String, rule: GaugeColorChange, value: Double) -> CGColor {
    guard rule.enabled, value.isFinite else { return OverlayRenderer.color(base) }
    func blend(_ a: String, _ b: String, _ f: Double) -> CGColor {
      let x = OverlayRenderer.color(a).components!, y = OverlayRenderer.color(b).components!
      return CGColor(colorSpace: OverlayRenderer.colorSpace, components: zip(x, y).map { $0 + ($1 - $0) * max(0, min(1, f)) })!
    }
    if rule.secondEnabled && value >= rule.threshold {
      if rule.gradient && rule.secondThreshold > rule.threshold {
        return blend(rule.color, rule.secondColor, (value - rule.threshold) / (rule.secondThreshold - rule.threshold))
      }
      return OverlayRenderer.color(value >= rule.secondThreshold ? rule.secondColor : rule.color)
    }
    if rule.gradient && rule.threshold > rule.start {
      return blend(base, rule.color, (value - rule.start) / (rule.threshold - rule.start))
    }
    return OverlayRenderer.color(value >= rule.threshold ? rule.color : base)
  }

  static func draw(_ c: CGContext, object o: DisplayObject, rect r: CGRect, data: Telemetry?, time: Double, unit: String) -> Bool {
    guard let settings = o.gauge, let d = settings.design else { return false }
    let channel = o.resolvedChannel
    let measured = o.kind == .speed ? LegacyEnhancedRenderer.channelBounds(channel, data: data, unit: unit) : data?.bounds(channel)
    let minimum = d.automaticMinimum ? measured?.0 ?? o.minimum : o.minimum
    let maximum = max(minimum + 0.00001, d.automaticMaximum ? measured?.1 ?? o.maximum : o.maximum)
    func sample(_ t: Double) -> Double? {
      o.kind == .speed ? data?.speed(at: t, unit: unit, channel: channel) : data?.value(channel, at: t)
    }
    var value = sample(time)
    if d.smoothing.isFinite, d.smoothing > 0 {
      let span = min(10, d.smoothing)
      let values = (0..<9).compactMap { sample(time + (Double($0) / 8 - 0.5) * span) }
      if !values.isEmpty { value = values.reduce(0, +) / Double(values.count) }
    }
    let radius = min(r.width, r.height) * 0.46
    guard radius > 0 else { return true }
    let sweep = settings.sweep.isFinite ? max(1, min(360, settings.sweep)) : 270
    let rotation = settings.rotation.isFinite ? settings.rotation : 0
    func angle(_ fraction: Double) -> Double { (-90 - rotation + (settings.counterClockwise ? 1 : -1) * fraction * sweep) * .pi / 180 }
    func fraction(_ v: Double) -> Double { d.fraction(v, minimum: minimum, maximum: maximum, sweep: sweep) }
    func point(_ f: Double, _ distance: Double) -> CGPoint { CGPoint(x: r.midX + cos(angle(f)) * distance, y: r.midY + sin(angle(f)) * distance) }
    func length(_ v: Double, limit: Double = 200) -> Double { (v.isFinite ? max(-limit, min(limit, v)) : 0) * radius / 100 }
    let circle = CGRect(x: r.midX - radius, y: r.midY - radius, width: radius * 2, height: radius * 2)
    if let image = settings.backgroundImage.flatMap({ NSImage(data: $0) }) ?? settings.backgroundPath.flatMap({ NSImage(contentsOfFile: $0) }),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { c.draw(cg, in: r) }
    if settings.showFace {
      c.saveGState(); c.addEllipse(in: circle); c.clip()
      let color = paint(d.faceColor, rule: d.faceChange, value: value ?? minimum)
      if d.faceGradient, let gradient = CGGradient(colorsSpace: OverlayRenderer.colorSpace,
        colors: [color, OverlayRenderer.color(d.faceSecondColor)] as CFArray, locations: [0, 1]) {
        c.drawLinearGradient(gradient, start: CGPoint(x: r.midX, y: circle.maxY), end: CGPoint(x: r.midX, y: circle.minY), options: [])
      } else { c.setFillColor(color); c.fill(circle) }
      c.restoreGState()
    }
    if d.trim {
      c.setStrokeColor(OverlayRenderer.color(d.trimColor)); c.setLineWidth(max(0.5, length(d.trimWidth))); c.strokeEllipse(in: circle)
    }
    func mark(_ v: Double, size: Double, width: Double, color: String, style: GaugeDesign.Mark) {
      let f = fraction(v), outer = length(d.tip), inner = outer - max(0, length(size)), mid = point(f, outer)
      let shade = paint(color, rule: d.markingChange, value: v)
      c.setFillColor(shade); c.setStrokeColor(shade); c.setLineWidth(max(0.4, length(width))); c.setLineCap(.round)
      switch style {
      case .dash: c.move(to: point(f, inner)); c.addLine(to: mid); c.strokePath()
      case .dot:
        let size = max(1, length(width) * 2); c.fillEllipse(in: CGRect(x: mid.x - size / 2, y: mid.y - size / 2, width: size, height: size))
      case .triangle:
        let a = angle(f), wing = max(1, length(width) * 2)
        let inside = point(f, inner)
        c.move(to: inside); c.addLine(to: CGPoint(x: mid.x + sin(a) * wing, y: mid.y - cos(a) * wing)); c.addLine(to: CGPoint(x: mid.x - sin(a) * wing, y: mid.y + cos(a) * wing)); c.closePath(); c.fillPath()
      }
    }
    let range = maximum - minimum
    let major = settings.tickInterval.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? range / Double(max(1, min(100, settings.divisions)))
    let safeMajor = max(range / 500, major)
    let minor = d.minorInterval.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? safeMajor / Double(max(1, min(100, d.minorDivisions)))
    if d.showMinor {
      let step = max(range / 1000, minor)
      for i in 0...min(1000, Int(floor(range / step))) {
        let v = minimum + Double(i) * step
        if abs((v - minimum) / safeMajor - ((v - minimum) / safeMajor).rounded()) > 0.00001 {
          mark(v, size: d.minorLength, width: d.minorWidth, color: d.minorColor, style: d.minorStyle)
        }
      }
    }
    var labelBounds: [CGRect] = []
    func label(_ text: String, style: GaugeCaption, at p: CGPoint, avoidClutter: Bool = false) {
      let size = max(1, length(style.size)), bounds = CGRect(x: p.x - Double(text.count) * size * 0.3, y: p.y - size * 0.5, width: Double(text.count) * size * 0.6, height: size)
      if avoidClutter && d.limitClutter && labelBounds.contains(where: { $0.intersects(bounds) }) { return }
      labelBounds.append(bounds)
      LegacyStyledRenderer.label(c, text, font: style.font, size: size, color: OverlayRenderer.color(style.color), x: p.x, y: p.y - size * 0.5, bold: style.bold, italic: style.italic)
    }
    let count = min(500, Int(floor(range / safeMajor)))
    for i in 0...count {
      let v = minimum + Double(i) * safeMajor
      if d.showMajor { mark(v, size: d.majorLength, width: d.majorWidth, color: d.marksColor, style: d.majorStyle) }
      let endpoint = i == 0 || abs(v - maximum) < range * 0.00001
      if settings.showLabels && (!d.everyOtherNumber || i % 2 == 0 || endpoint) && (d.numberExtremes || !endpoint) {
        let scale = settings.numberingScale.isFinite && settings.numberingScale > 0 ? settings.numberingScale : 1
        label(OverlayRenderer.number(v / scale), style: d.numberStyle, at: point(fraction(v), length(d.tip - d.majorLength - d.numberStyle.size)), avoidClutter: true)
      }
    }
    if d.pins {
      c.setFillColor(OverlayRenderer.color(d.pinColor))
      for f in [0.0, 1.0] {
        let p = point(f, length(d.tip + 4)), size = max(1, length(d.pinSize))
        c.fillEllipse(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
      }
    }
    if let v = value, v.isFinite {
      let f = fraction(v)
      if d.mode == .filled {
        let inner = max(0, min(99, d.fillInnerRadius)), middle = (100 + inner) / 2
        c.setStrokeColor(paint(d.needleColor, rule: d.needleChange, value: v)); c.setLineWidth(length(100 - inner)); c.setLineCap(.butt)
        c.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: length(middle), startAngle: angle(0), endAngle: angle(f), clockwise: !settings.counterClockwise); c.strokePath()
      } else {
        func needle(_ f: Double, tip: Double, tail: Double, width: Double, color: CGColor, taper: Double) {
          let a = angle(f), end = point(f, length(tip)), back = point(f, -length(tail)), half = max(0.5, length(width) / 2)
          c.setStrokeColor(color); c.setFillColor(color)
          if taper > 0 {
            let tipWidth = half / max(1, min(20, taper + 1))
            c.move(to: CGPoint(x: back.x + sin(a) * half, y: back.y - cos(a) * half))
            c.addLine(to: CGPoint(x: end.x + sin(a) * tipWidth, y: end.y - cos(a) * tipWidth))
            c.addLine(to: CGPoint(x: end.x - sin(a) * tipWidth, y: end.y + cos(a) * tipWidth))
            c.addLine(to: CGPoint(x: back.x - sin(a) * half, y: back.y + cos(a) * half)); c.closePath(); c.fillPath()
          } else { c.setLineWidth(half * 2); c.move(to: back); c.addLine(to: end); c.strokePath() }
        }
        if d.mode == .dualNeedle {
          let interval = d.dualInterval.isFinite ? max(0.000001, d.dualInterval) : 1000
          let partial = (max(0, v - minimum).truncatingRemainder(dividingBy: interval)) / interval
          needle(partial, tip: d.dualTip, tail: d.dualTail, width: d.dualWidth, color: OverlayRenderer.color(d.dualColor), taper: d.taper)
        }
        needle(f, tip: d.tip, tail: d.tail, width: d.needleWidth, color: paint(d.needleColor, rule: d.needleChange, value: v), taper: d.taper)
        let center = max(0, length(d.centerSize)); c.setFillColor(OverlayRenderer.color(d.centerColor))
        c.fillEllipse(in: CGRect(x: r.midX - center / 2, y: r.midY - center / 2, width: center, height: center))
      }
    }
    func captionPoint(_ caption: GaugeCaption, defaultY: Double) -> CGPoint {
      CGPoint(x: r.minX + r.width * (caption.automaticPosition ? 0.5 : caption.x / 100), y: r.minY + r.height * (caption.automaticPosition ? defaultY : caption.y / 100))
    }
    if settings.showNumber { label(OverlayRenderer.number(value, decimals: max(0, min(6, settings.decimals))), style: d.valueStyle, at: captionPoint(d.valueStyle, defaultY: 0.40)) }
    if settings.showLabels { label(settings.label.isEmpty ? (o.kind == .speed ? unit.uppercased() : o.kind == .rpm ? "RPM" : o.name) : settings.resolvedLabel(unit: unit), style: d.labelStyle, at: captionPoint(d.labelStyle, defaultY: 0.28)) }
    return true
  }
}
