import AppKit

/// Original vector geometry inspired by a simulator's analog instrument cluster.
enum GTInstrumentRenderer {
  static let white = "#F5F7FA", muted = "#AEB8C5", red = "#FF575E"
  static func angle(_ fraction: Double) -> Double { (225-max(0, min(1, fraction))*270)*Double.pi/180 }
  static func draw(_ c: CGContext, object o: DisplayObject, rect r: CGRect, data d: Telemetry?, time t: Double, unit: String) -> Bool {
    guard let hud = o.hud, hud.presentation == "gt" else { return false }
    let w = r.width, h = r.height, s = min(w, h)
    func text(_ text: String, _ x: Double, _ y: Double, _ size: Double, _ color: String = white, _ align: Double = 0.5, _ weight: NSFont.Weight = .regular) {
      OverlayRenderer.text(c, text, x: r.minX+x*w, y: r.minY+y*h, size: size*h, color: color, align: align, weight: weight)
    }
    func fill(_ rect: CGRect, _ color: String, _ alpha: Double = 1) { c.setFillColor(OverlayRenderer.color(color, alpha: alpha)); c.fill(rect) }
    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX+x*w, y: r.minY+y*h) }
    func line(_ from: CGPoint, _ to: CGPoint, _ color: String = white, _ width: Double = 1, _ alpha: Double = 1) {
      c.setStrokeColor(OverlayRenderer.color(color, alpha: alpha)); c.setLineWidth(width); c.move(to: from); c.addLine(to: to); c.strokePath()
    }
    func value(_ name: String) -> Double? { d?.value(name, at: t, interpolate: o.kind != .gear) }
    switch hud.role {
    case .speed, .rpm:
      let rpm = hud.role == .rpm
      let v = rpm ? value(o.resolvedChannel) : d?.speed(at: t, unit: unit, channel: o.resolvedChannel)
      let center = point(0.5, 0.51), radius = s*0.46
      let maximum = max(o.minimum+1, o.maximum), range = maximum-o.minimum
      let redline = o.gauge?.redline ?? maximum*0.85
      func at(_ factor: Double, _ length: Double) -> CGPoint {
        let a = angle(factor); return CGPoint(x: center.x+cos(a)*radius*length, y: center.y+sin(a)*radius*length)
      }
      c.setFillColor(OverlayRenderer.color("#080C12", alpha: 0.25))
      c.fillEllipse(in: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
      func arc(_ start: Double, _ end: Double, _ color: String, _ width: Double) {
        c.setStrokeColor(OverlayRenderer.color(color)); c.setLineWidth(width); c.setLineCap(.butt)
        c.addArc(center: center, radius: radius*0.98, startAngle: angle(start), endAngle: angle(end), clockwise: true); c.strokePath()
      }
      arc(0, 1, white, max(1, s*0.008))
      if rpm { arc(max(0, (redline-o.minimum)/range), 1, red, max(2, s*0.018)) }
      let divisions = rpm ? max(1, min(16, Int(range/1000))) : 8
      for i in 0...divisions*5 {
        let factor = Double(i)/Double(divisions*5), major = i%5 == 0
        let color = rpm && o.minimum+factor*range >= redline ? red : white
        line(at(factor, major ? 0.85 : 0.91), at(factor, 0.965), color, max(0.6, s*(major ? 0.006 : 0.003)), major ? 1 : 0.75)
        if major {
          let p = at(factor, 0.735), number = (o.minimum+factor*range)/(rpm ? 1000 : 1)
          OverlayRenderer.text(c, String(format: "%.0f", number), x: p.x, y: p.y-h*0.016, size: h*0.038, color: white, weight: .regular)
        }
      }
      if let v {
        let factor = (v-o.minimum)/range
        line(at(factor, -0.10), at(factor, 0.83), rpm ? red : white, max(1.4, s*0.009))
        c.setFillColor(OverlayRenderer.color(white)); c.fillEllipse(in: CGRect(x: center.x-s*0.018, y: center.y-s*0.018, width: s*0.036, height: s*0.036))
      }
      // Digital readout sits below the needle pivot, with the trip counter below it.
      fill(CGRect(x: r.minX+w*0.27, y: r.minY+h*0.29, width: w*0.46, height: h*0.19), "#080C12", 0.3)
      text(OverlayRenderer.number(v), 0.5, 0.30, rpm ? 0.125 : 0.20, white, 0.5, .light)
      text(rpm ? "×1000 rpm" : unit, 0.5, 0.60, 0.042, muted)
      text(rpm ? "RPM" : hud.label.uppercased(), 0.5, 0.67, 0.032, muted)
    case .odometer:
      let v = value(o.resolvedChannel).map { $0*hud.multiplier }
      let precision = max(0, min(4, hud.decimals))
      let digits = v.flatMap { $0.isFinite && $0 >= 0 && $0 < 100_000_000 ? String(format: "%0*.*f", max(8, precision+3), precision, $0) : nil } ?? "--------"
      fill(r, "#080C12", 0.68)
      c.setStrokeColor(OverlayRenderer.color(muted, alpha: 0.45)); c.setLineWidth(max(0.5, h*0.025)); c.stroke(r.insetBy(dx: 0.5, dy: 0.5))
      let title = ["", "Trip distance", "Distance"].contains(hud.label) ? "TRIP" : hud.label.uppercased()
      text(title, 0.04, 0.74, min(0.19, w/h/max(4, Double(title.count))*0.7), muted, 0)
      text(digits, 0.04, 0.09, min(0.52, w/h/Double(digits.count)*1.1), white, 0, .medium)
      text(hud.unit, 0.96, 0.15, 0.24, muted, 1)
    case .gear:
      let v = value(o.resolvedChannel)
      text(v == 0 ? "N" : OverlayRenderer.number(v), 0.5, 0.12, 0.70, white, 0.5, .medium)
      text(hud.label.uppercased(), 0.5, 0.88, 0.10, muted)
    case .pedal:
      let v = value(o.resolvedChannel), fraction = max(0, min(1, ((v ?? 0)-o.minimum)/max(1, o.maximum-o.minimum)))
      let track = CGRect(x: r.minX+w*0.26, y: r.minY+h*0.19, width: w*0.48, height: h*0.65)
      fill(track, "#080C12", 0.58)
      fill(CGRect(x: track.minX+1, y: track.minY+1, width: max(0, track.width-2), height: max(0, (track.height-2)*fraction)), o.color)
      c.setStrokeColor(OverlayRenderer.color(white, alpha: 0.85)); c.setLineWidth(max(0.8, w*0.025)); c.stroke(track)
      for factor in [0.25, 0.5, 0.75] {
        line(CGPoint(x: track.minX, y: track.minY+track.height*factor), CGPoint(x: track.maxX, y: track.minY+track.height*factor), white, 0.6, 0.3)
      }
      text(o.kind == .brake ? "BRAKE" : "THR", 0.5, 0.89, 0.045, muted)
      text(OverlayRenderer.number(v)+"%", 0.5, 0.10, 0.055)
      // Small pedal pad below the live travel bar.
      let pad = CGRect(x: r.minX+w*0.28, y: r.minY+h*0.015, width: w*0.44, height: h*0.045)
      fill(pad, white, 0.7)
      for i in 1...3 { let x = pad.minX+pad.width*Double(i)/4; line(CGPoint(x: x, y: pad.minY), CGPoint(x: x, y: pad.maxY), "#080C12", 0.8) }
    case .tyres:
      let pressureUnit = hud.unit.isEmpty ? "psi" : hud.unit
      text(hud.label.uppercased()+" · "+pressureUnit.uppercased()+" / °C", 0.5, 0.94, 0.047, muted)
      // Top-down body: rounded nose, tapered cabin, rear deck and axle lines.
      let body = CGMutablePath(); body.move(to: point(0.46, 0.85)); body.addLine(to: point(0.54, 0.85))
      body.addCurve(to: point(0.61, 0.76), control1: point(0.59, 0.85), control2: point(0.61, 0.82))
      body.addLine(to: point(0.62, 0.36))
      body.addCurve(to: point(0.58, 0.10), control1: point(0.63, 0.25), control2: point(0.61, 0.12))
      body.addLine(to: point(0.42, 0.10))
      body.addCurve(to: point(0.38, 0.36), control1: point(0.39, 0.12), control2: point(0.37, 0.25))
      body.addLine(to: point(0.39, 0.76))
      body.addCurve(to: point(0.46, 0.85), control1: point(0.39, 0.82), control2: point(0.41, 0.85)); body.closeSubpath()
      c.setFillColor(OverlayRenderer.color("#080C12", alpha: 0.5)); c.addPath(body); c.fillPath()
      c.setStrokeColor(OverlayRenderer.color(white, alpha: 0.8)); c.setLineWidth(max(0.8, s*0.004)); c.addPath(body); c.strokePath()
      for (low, high) in [(0.62, 0.75), (0.20, 0.32)] {
        let glass = CGMutablePath(); glass.move(to: point(0.42, low)); glass.addLine(to: point(0.58, low)); glass.addLine(to: point(0.565, high)); glass.addLine(to: point(0.435, high)); glass.closeSubpath()
        c.setFillColor(OverlayRenderer.color(white, alpha: 0.12)); c.addPath(glass); c.fillPath()
        c.setStrokeColor(OverlayRenderer.color(muted, alpha: 0.65)); c.addPath(glass); c.strokePath()
      }
      line(point(0.40, 0.16), point(0.60, 0.16), white, max(0.8, s*0.004), 0.6)
      for (i, corner) in ["FL", "FR", "RL", "RR"].enumerated() {
        let left = i%2 == 0, y = i < 2 ? 0.69 : 0.27, wheelX = left ? 0.335 : 0.665
        let pressureName = "Tyre pressure "+corner, temperature = value("Tyre temperature "+corner)
        let pressure = value(pressureName).map { v in
          let header = d?.channelIndex(pressureName).map { d!.headers[$0] } ?? ""
          return HUDRenderer.tyrePressure(v, header: header, unit: pressureUnit)
        }
        let heat = temperature.map { $0 < 40 ? "#80CDEB" : $0 < 70 ? "#9AE0A3" : $0 < 90 ? "#F4C579" : red } ?? "#66717D"
        line(point(0.40, y), point(0.60, y), muted, max(0.6, s*0.003), 0.5)
        let wheel = CGRect(x: r.minX+(wheelX-0.028)*w, y: r.minY+(y-0.085)*h, width: w*0.056, height: h*0.17)
        let path = CGPath(roundedRect: wheel, cornerWidth: w*0.008, cornerHeight: w*0.008, transform: nil)
        c.setFillColor(OverlayRenderer.color(heat, alpha: 0.9)); c.addPath(path); c.fillPath()
        c.setStrokeColor(OverlayRenderer.color(white, alpha: 0.7)); c.addPath(path); c.strokePath()
        let x = left ? 0.04 : 0.96, align = left ? 0.0 : 1.0
        text(corner, x, y+0.075, 0.036, muted, align)
        text(OverlayRenderer.number(pressure, decimals: 1), x, y-0.015, 0.073, white, align)
        text(OverlayRenderer.number(temperature)+"°C", x, y-0.085, 0.046, heat, align)
      }
    default: return false
    }
    return true
  }
}
