import AppKit

/// A quiet, original motorsport HUD built from vector shapes and system fonts.
enum HUDRenderer {
  static let white = "#F5F7FA", muted = "#AEB8C5", red = "#FF666A"
  static func tyrePressure(_ value: Double, header: String, unit: String) -> Double {
    let header = header.lowercased(), unit = unit.lowercased()
    let kpa = header.contains("psi") ? value*6.894757293 : header.contains("bar") ? value*100 : value
    return unit == "psi" ? kpa/6.894757293 : unit == "bar" ? kpa/100 : kpa
  }
  static func draw(_ c: CGContext, object o: DisplayObject, rect r: CGRect, data d: Telemetry?, time t: Double, unit: String) -> Bool {
    guard let hud = o.hud else { return false }
    let w = r.width, h = r.height, cx = r.midX, cy = r.midY
    let scale = max(0.1, min(w/100, h/60))
    func text(_ s: String, _ x: Double, _ y: Double, _ size: Double, _ color: String = white, _ align: Double = 0.5, _ weight: NSFont.Weight = .medium) {
      OverlayRenderer.text(c, s, x: r.minX+x*w, y: r.minY+y*h, size: size*h, color: color, align: align, weight: weight)
    }
    func label(_ title: String? = nil) {
      let size = [.map, .gforce, .tyres].contains(hud.role) ? min(0.16, (w*0.05+h*0.015)/h) : 0.16
      text((title ?? hud.label).uppercased(), 0.07, 0.74, size, muted, 0, .semibold)
    }
    func value(_ channel: String) -> Double? { d?.value(channel, at: t, interpolate: o.kind != .gear) }
    func format(_ v: Double?, decimals: Int? = nil) -> String { OverlayRenderer.number(v, decimals: max(0, min(4, decimals ?? hud.decimals))) }
    func fill(_ color: String, _ rect: CGRect, _ alpha: Double = 1) { c.setFillColor(OverlayRenderer.color(color, alpha: alpha)); c.fill(rect) }
    func line(_ a: CGPoint, _ b: CGPoint, _ color: String = muted, _ width: Double = 1, _ alpha: Double = 1) {
      c.setStrokeColor(OverlayRenderer.color(color, alpha: alpha)); c.setLineWidth(width); c.move(to: a); c.addLine(to: b); c.strokePath()
    }
    func panel() {
      c.setFillColor(OverlayRenderer.color("#080E16", alpha: 0.64))
      c.addPath(CGPath(roundedRect: r, cornerWidth: min(7*scale, h*0.12), cornerHeight: min(7*scale, h*0.12), transform: nil)); c.fillPath()
    }
    switch hud.role {
    case .speed:
      panel(); label(hud.label + " · " + unit.uppercased())
      text(format(d?.speed(at: t, unit: unit, channel: o.resolvedChannel)), 0.5, 0.02, 0.66, white, 0.5, .light)
    case .gear:
      panel(); label()
      let v = value(o.resolvedChannel)
      text(v == 0 ? "N" : format(v), 0.5, 0.02, 0.66, o.color, 0.5, .semibold)
    case .rpm:
      panel()
      let rpm = value(o.resolvedChannel), maximum = max(1, o.maximum), redline = o.gauge?.redline ?? maximum*0.85
      text(hud.label.uppercased(), 0.018, 0.12, 0.26, muted, 0)
      text(format(rpm), 0.98, 0.12, 0.28, white, 1)
      let count = 64, area = CGRect(x: r.minX+w*0.02, y: r.minY+h*0.55, width: w*0.96, height: h*0.28)
      for i in 0..<count {
        let boundary = Double(i+1)/Double(count)*maximum
        let color = boundary >= redline ? red : o.color
        fill(color, CGRect(x: area.minX+Double(i)*area.width/Double(count), y: area.minY,
          width: max(0.5, area.width/Double(count)-max(1, scale)), height: area.height), (rpm ?? -1) >= boundary ? 1 : 0.13)
      }
    case .lights:
      let rpm = value(o.resolvedChannel), maximum = max(1, o.maximum), redline = o.gauge?.redline ?? maximum*0.85
      for i in 0..<10 {
        let size = min(h, w/13), x = r.minX+(Double(i)+0.5)*w/10
        let threshold = redline-1800+Double(i)*200
        c.setFillColor(OverlayRenderer.color(i >= 8 ? red : i >= 5 ? "#FFD17A" : o.color, alpha: (rpm ?? -1) >= threshold ? 1 : 0.16))
        c.fillEllipse(in: CGRect(x: x-size/2, y: cy-size/2, width: size, height: size))
      }
    case .pedal:
      panel(); label()
      let v = value(o.resolvedChannel), factor = max(0, min(1, ((v ?? 0)-o.minimum)/max(1, o.maximum-o.minimum)))
      let bar = CGRect(x: r.minX+w*0.12, y: r.minY+h*0.18, width: w*0.12, height: h*0.45)
      fill(o.color, bar, 0.16); fill(o.color, CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height*factor))
      text(format(v), 0.62, 0.21, 0.38, white, 0.5, .light)
      text("%", 0.62, 0.07, 0.13, muted)
    case .metric:
      panel(); label()
      let v = value(o.resolvedChannel).map { $0*hud.multiplier }
      let digits = format(v)
      let font = min(0.44, 0.14*w/max(1, Double(digits.count))/h*4)
      text(digits, 0.08, 0.12, font, white, 0, .medium)
      text(hud.unit, 0.94, 0.17, 0.19, muted, 1)
    case .steering:
      panel(); label()
      let v = value(o.resolvedChannel), radius = min(w*0.27, h*0.22)
      c.saveGState(); c.translateBy(x: cx, y: r.minY+h*0.48); c.rotate(by: -(v ?? 0)*Double.pi/180)
      c.setStrokeColor(OverlayRenderer.color(v == nil ? muted : o.color)); c.setLineWidth(max(1.2, radius*0.07))
      c.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius*2, height: radius*2))
      line(CGPoint(x: -radius, y: 0), CGPoint(x: radius, y: 0), o.color, max(1, radius*0.05))
      line(.zero, CGPoint(x: 0, y: -radius), o.color, max(1, radius*0.05))
      fill(white, CGRect(x: -radius*0.05, y: radius*0.8, width: radius*0.1, height: radius*0.2)); c.restoreGState()
      text(format(v)+"°", 0.5, 0.05, 0.18)
    case .gforce:
      panel(); label()
      let radius = min(w*0.36, h*0.24), center = CGPoint(x: cx, y: r.minY+h*0.47)
      c.setStrokeColor(OverlayRenderer.color(muted, alpha: 0.45)); c.setLineWidth(max(0.7, scale*0.7))
      for factor in [0.5, 1.0] { c.strokeEllipse(in: CGRect(x: center.x-radius*factor, y: center.y-radius*factor, width: radius*factor*2, height: radius*factor*2)) }
      line(CGPoint(x: center.x-radius, y: center.y), CGPoint(x: center.x+radius, y: center.y), muted, 0.6, 0.4)
      line(CGPoint(x: center.x, y: center.y-radius), CGPoint(x: center.x, y: center.y+radius), muted, 0.6, 0.4)
      let longitudinal = value("gx"), lateral = value(o.resolvedChannel)
      if let longitudinal, let lateral {
        let limit = max(0.5, o.maximum), x = center.x+max(-1, min(1, lateral/limit))*radius
        let y = center.y+max(-1, min(1, longitudinal/limit))*radius
        c.setFillColor(OverlayRenderer.color(o.color)); c.fillEllipse(in: CGRect(x: x-3*scale, y: y-3*scale, width: 6*scale, height: 6*scale))
        text(String(format: "%.2f G", hypot(longitudinal, lateral)), 0.5, 0.105, 0.12)
        text(String(format: "X %+.2f   Y %+.2f", longitudinal, lateral), 0.5, 0.02, 0.07, muted)
      } else { text("— G", 0.5, 0.08, 0.13, muted) }
    case .map:
      panel(); label()
      if let d, let route = HUDRoute.get(d) {
        let area = CGRect(x: r.minX+w*0.09, y: r.minY+h*0.10, width: w*0.82, height: h*0.58)
        let fit = min(area.width/route.width, area.height/route.height)
        let target = CGRect(x: area.midX-route.width*fit/2, y: area.midY-route.height*fit/2, width: route.width*fit, height: route.height*fit)
        var transform = CGAffineTransform(translationX: target.minX, y: target.minY).scaledBy(x: target.width, y: target.height)
        if let path = route.path.copy(using: &transform) {
          c.addPath(path); c.setStrokeColor(OverlayRenderer.color(white, alpha: 0.85)); c.setLineWidth(max(1.5, 1.6*scale)); c.setLineJoin(.round); c.setLineCap(.round); c.strokePath()
        }
        if let lat = value("lat"), let lon = value("lon"), t >= 0 {
          let p = route.point(lat: lat, lon: lon), x = target.minX+p.x*target.width, y = target.minY+p.y*target.height
          c.setFillColor(OverlayRenderer.color(o.color)); c.fillEllipse(in: CGRect(x: x-4*scale, y: y-4*scale, width: 8*scale, height: 8*scale))
        }
      } else { text("NO GPS", 0.5, 0.35, 0.09, muted) }
    case .lap, .timer, .delta, .bestLap, .bestTime, .elapsed:
      panel(); label()
      let lap = d?.lap(at: t), best = d?.bestLap(at: t)
      var content = "—", color = white
      switch hud.role {
      case .lap: content = lap.map { String($0.number) } ?? "—"
      case .timer: content = lap.map { clockText(t-$0.start) } ?? "—"
      case .bestLap: content = best.map { String($0.number) } ?? "—"
      case .bestTime: content = best.map { clockText($0.duration) } ?? "—"
      case .elapsed: content = t >= 0 && d != nil ? clockText(t) : "—"
      case .delta:
        if let delta = d?.delta(at: t, reference: best) { content = String(format: "%+.3f", delta); color = delta > 0 ? red : o.color }
      default: break
      }
      text(content, 0.07, 0.10, min(0.45, w/h/max(3, Double(content.count))*1.45), color, 0)
    case .peakSpeed, .baseSpeed, .peakG:
      panel(); label()
      let isSpeed = hud.role != .peakG
      let peak = d.flatMap { HUDPeaks.get($0, channel: o.resolvedChannel, speed: isSpeed, minimum: hud.role == .baseSpeed).value(at: t) }
      let result = isSpeed ? peak.map { $0*(unit == "mph" ? 2.2369362921 : unit == "km/h" ? 3.6 : unit == "knots" ? 1.94384449 : 1) } : peak
      let suffix = isSpeed ? unit.uppercased() : "G"
      text(format(result, decimals: hud.role == .peakG ? 2 : 0), 0.94, 0.10, 0.44, o.color, 1)
      text(suffix + " · COMPLETED", 0.07, 0.13, 0.16, muted, 0)
    case .tyres:
      panel(); label(hud.label + " · " + (hud.unit.isEmpty ? "PSI" : hud.unit.uppercased()) + " / °C")
      let pressureUnit = hud.unit.isEmpty ? "psi" : hud.unit
      for (i, corner) in ["FL", "FR", "RL", "RR"].enumerated() {
        let x = i%2 == 0 ? 0.07 : 0.56, y = i<2 ? 0.40 : 0.08
        let pressureName = "Tyre pressure " + corner, temperatureName = "Tyre temperature " + corner
        let pressure = value(pressureName).map { value in
          let header = d?.channelIndex(pressureName).map { d!.headers[$0].lowercased() } ?? ""
          return tyrePressure(value, header: header, unit: pressureUnit)
        }
        let temperature = value(temperatureName)
        text(corner, x, y+0.19, 0.075, muted, 0, .semibold)
        text(format(pressure, decimals: 1), x, y+0.055, 0.10, white, 0)
        text(format(temperature)+"°", x+0.31, y+0.065, 0.08, temperature.map { $0 > 90 ? red : o.color } ?? muted, 1)
        fill(o.color, CGRect(x: r.minX+x*w, y: r.minY+(y+0.005)*h, width: w*0.32, height: max(1, h*0.008)), 0.45)
      }
      // A small, neutral vehicle silhouette establishes wheel orientation.
      c.setStrokeColor(OverlayRenderer.color(muted, alpha: 0.45)); c.setLineWidth(max(0.7, scale))
      c.stroke(CGRect(x: cx-w*0.045, y: r.minY+h*0.22, width: w*0.09, height: h*0.3))
    }
    return true
  }
}

private final class HUDRoute: NSObject {
  static let cache: NSCache<NSString, HUDRoute> = NSCache()
  let telemetry: Telemetry, path: CGPath, minX: Double, minY: Double, width: Double, height: Double, longitudeFactor: Double
  init?(_ data: Telemetry) {
    guard !data.mapPoints.isEmpty, let lat = data.aliases["lat"] else { return nil }
    telemetry = data; longitudeFactor = cos((data.columns[lat].first(where: \.isFinite) ?? 0)*Double.pi/180)
    let xs = data.mapPoints.map(\.0), ys = data.mapPoints.map(\.1)
    minX = xs.min()!; minY = ys.min()!; width = max(0.000001, xs.max()!-minX); height = max(0.000001, ys.max()!-minY)
    let p = CGMutablePath()
    for (i, point) in data.mapPoints.enumerated() {
      let value = CGPoint(x: (point.0-minX)/width, y: (point.1-minY)/height)
      if i == 0 { p.move(to: value) } else { p.addLine(to: value) }
    }
    path = p; super.init()
  }
  static func get(_ data: Telemetry) -> HUDRoute? {
    let key = "\(ObjectIdentifier(data)):\(data.renderRevision)" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    guard let route = HUDRoute(data) else { return nil }; cache.countLimit = 8; cache.setObject(route, forKey: key); return route
  }
  func point(lat: Double, lon: Double) -> CGPoint { CGPoint(x: (lon*longitudeFactor-minX)/width, y: (lat-minY)/height) }
}

/// Completed extrema are indexed once, so seeking and chunk exports agree.
final class HUDPeaks: NSObject {
  static let cache = NSCache<NSString, HUDPeaks>()
  let telemetry: Telemetry
  var events: [(Double, Double)] = []
  init(_ data: Telemetry, channel: String, speed: Bool, minimum: Bool = false) {
    telemetry = data; super.init()
    guard let index = data.channelIndex(channel) else { return }
    let header = data.headers[index].lowercased()
    let factor = !speed ? 1 : header.contains("km") ? 1/3.6 : header.contains("mph") ? 1/2.2369362921 : header.contains("knot") ? 0.514444 : 1
    var candidate = 0.0, low = Double.infinity, armed = true
    let threshold = speed ? 0.45 : 0.06
    for i in data.times.indices {
      let raw = data.columns[index][i]*factor, v = minimum ? -raw : speed ? raw : abs(raw)
      guard v.isFinite else { continue }
      if !speed && v < 0.08 { armed = true; candidate = 0; low = v; continue }
      if v < low { low = v; if speed { candidate = v } }
      if v > candidate { candidate = v }
      if armed && candidate-v > threshold && candidate-low > threshold && (minimum || candidate > (speed ? 1 : 0.12)) {
        events.append((data.times[i], minimum ? max(0, -candidate) : candidate))
        if speed { candidate = v; low = v } else { armed = false }
      }
    }
  }
  static func get(_ data: Telemetry, channel: String, speed: Bool, minimum: Bool = false) -> HUDPeaks {
    let key = "\(ObjectIdentifier(data)):\(data.renderRevision):\(channel):\(speed):\(minimum)" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let result = HUDPeaks(data, channel: channel, speed: speed, minimum: minimum); cache.countLimit = 24; cache.setObject(result, forKey: key); return result
  }
  func value(at time: Double) -> Double? {
    guard time >= 0, time <= telemetry.duration+0.1 else { return nil }
    var low = 0, high = events.count
    while low < high { let mid = (low+high)/2; if events[mid].0 <= time { low = mid+1 } else { high = mid } }
    return low > 0 ? events[low-1].1 : nil
  }
}
