import Foundation

public struct HUDSettings: Codable, Equatable, Sendable {
  public enum Role: String, Codable, CaseIterable, Sendable {
    case speed, rpm, gear, pedal, lights, gforce, map, metric, odometer, lap, timer, delta, bestLap, bestTime, elapsed, peakSpeed, baseSpeed, peakG, tyres, steering
  }
  public var role: Role
  public var label: String
  public var unit: String
  public var decimals: Int
  public var multiplier: Double
  public var presentation: String?
  public init(_ role: Role, label: String = "", unit: String = "", decimals: Int = 0, multiplier: Double = 1) {
    self.role = role; self.label = label; self.unit = unit; self.decimals = decimals; self.multiplier = multiplier
  }
}

/// Original vector instruments; no vendor artwork, fonts or scripts are required.
public enum ApexTemplate {
  public static func make(road: Bool = false, gt: Bool = false) -> RaceProject {
    var p = RaceProject(); p.name = "Apex Telemetry"
    p.inputs = [MediaInput(name: "Telemetry", path: "", kind: "data", legacyIndex: 1)]
    func add(_ name: String, _ kind: ObjectKind, _ role: HUDSettings.Role,
      _ x: Double, _ y: Double, _ w: Double, _ h: Double, channel: String = "", unit: String = "", decimals: Int = 0, multiplier: Double = 1, color: String = "#66D9EF") {
      var o = DisplayObject(name: name, kind: kind)
      o.style = "Apex / " + role.rawValue; o.hud = HUDSettings(role, label: name, unit: unit, decimals: decimals, multiplier: multiplier)
      o.inputIndex = 1; o.x = x; o.y = y; o.width = w; o.height = h; o.channel = channel; o.color = color
      if role == .gforce { o.maximum = 1.5 }
      if [.rpm, .lights].contains(kind) { o.maximum = 8000; var g = GaugeSettings(); g.redline = 6800; o.gauge = g }
      p.objects.append(o)
    }
    // The central road view stays clear. Major driving controls sit below it.
    add("Speed", .speed, .speed, 38, 3, 13, 12)
    add("Gear", .gear, .gear, 51.5, 3, 7, 12)
    add("Engine RPM", .rpm, .rpm, 30, 16, 40, 4)
    add("Shift lights", .lights, .lights, 44, 21, 12, 1.1)
    add("Throttle", .throttle, .pedal, 28, 3, 8, 11, color: "#83E7A6")
    add("Brake", .brake, .pedal, 18, 3, 8, 11, color: "#FF666A")
    add("Steering", .enhanced, .steering, 61, 3, 9, 12, channel: "Steering angle", unit: "°")
    add("Yaw rate", .enhanced, .metric, 71.5, 3, 6.5, 7, channel: "Yaw rate", unit: "°/s", decimals: 1)
    add("G-Force", .gforce, .gforce, 3, 3, 12, 21)
    add("Track map", .map, .map, 80, 73, 17, 24)
    add("Lap", .lap, .lap, 3, 91, 6, 6)
    add("Lap time", .timer, .timer, 10, 91, 13, 6)
    add("Delta / best", .delta, .delta, 24, 91, 12, 6)
    add("Best lap", .bestLap, .bestLap, 3, 84, 6, 5)
    add("Best time", .bestTime, .bestTime, 10, 84, 13, 5)
    add("Session time", .enhanced, .elapsed, 24, 84, 12, 5)
    add("Distance", .enhanced, .metric, 3, 76, 10, 5, channel: "distance", unit: "mi", decimals: 2, multiplier: 1/1609.344)
    add("Altitude", .enhanced, .metric, 14, 76, 10, 5, channel: "Altitude", unit: "m", decimals: 0)
    add("Heading", .enhanced, .metric, 25, 76, 11, 5, channel: "heading", unit: "°")
    add("Peak speed", .speed, .peakSpeed, 80, 67, 17, 4.5)
    add("Corner minimum", .speed, .baseSpeed, 80, 61.5, 17, 4.5)
    add("Turn peak G", .gforce, .peakG, 80, 56, 17, 4.5)
    add("Oil", .temperature, .metric, 80, 47.5, 3.7, 6, channel: "oil", unit: "°C")
    add("Coolant", .temperature, .metric, 84.4, 47.5, 3.7, 6, channel: "coolant", unit: "°C")
    add("Intake", .temperature, .metric, 88.8, 47.5, 3.7, 6, channel: "intake", unit: "°C")
    add("Air", .temperature, .metric, 93.2, 47.5, 3.8, 6, channel: "Air temperature", unit: "°C")
    add("GPS accuracy", .enhanced, .metric, 80, 40, 6, 5, channel: "GPS accuracy", unit: "m", decimals: 1)
    add("Satellites", .enhanced, .metric, 86.5, 40, 4.5, 5, channel: "Satellites")
    add("Logger battery", .enhanced, .metric, 91.5, 40, 5.5, 5, channel: "Device battery", unit: "%")
    add("Tyres", .enhanced, .tyres, 80, 3, 17, 24)
    if road {
      p.name = "Apex Road"
      for i in p.objects.indices {
        guard let role = p.objects[i].hud?.role else { continue }
        if [.lap, .timer, .delta, .bestLap, .bestTime].contains(role) { p.objects[i].visible = false }
        switch p.objects[i].name {
        case "Session time": p.objects[i].x = 3; p.objects[i].y = 91; p.objects[i].width = 16; p.objects[i].height = 6
        case "Distance": p.objects[i].x = 20; p.objects[i].y = 91; p.objects[i].width = 16; p.objects[i].height = 6
        case "Altitude": p.objects[i].x = 3; p.objects[i].y = 84; p.objects[i].width = 16; p.objects[i].height = 5
        case "Heading": p.objects[i].x = 20; p.objects[i].y = 84; p.objects[i].width = 16; p.objects[i].height = 5
        default: break
        }
      }
    }
    if gt {
      p.name = road ? "Apex GT Road" : "Apex GT"
      for i in p.objects.indices {
        p.objects[i].hud?.presentation = "gt"
        func place(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
          p.objects[i].x = x; p.objects[i].y = y; p.objects[i].width = width; p.objects[i].height = height
        }
        switch p.objects[i].name {
        case "Speed": place(29, 2, 15, 26.6666666667); p.objects[i].maximum = 160
        case "Engine RPM": place(56, 2, 15, 26.6666666667)
        case "Gear": place(46.5, 9, 7, 10)
        case "Brake": place(44.5, 4, 2, 18)
        case "Throttle": place(53.5, 4, 2, 18)
        case "Shift lights": place(44, 23, 12, 1.1)
        case "Steering": place(47, 1, 6, 7)
        case "Distance":
          place(32, 4, 9, 3.2); p.objects[i].hud?.role = .odometer
          p.objects[i].hud?.label = "Trip distance"; p.objects[i].style = "Apex GT / odometer"
        case "Heading" where road: place(20, 91, 16, 6)
        case "Tyres": place(80, 2, 17, 25)
        default: break
        }
        if p.objects[i].name != "Distance" { p.objects[i].style = "Apex GT / " + (p.objects[i].hud?.role.rawValue ?? "metric") }
      }
    }
    return p
  }
}
