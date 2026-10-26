import Foundation

public struct GaugeSettings: Codable, Equatable, Sendable {
  public var sweep: Double = 270
  public var rotation: Double = 0
  public var counterClockwise = false
  public var showFace = true
  public var showNumber = true
  public var showLabels = true
  public var divisions: Int = 8
  public var decimals: Int = 0
  public var numberingScale: Double = 1
  public var tickInterval: Double?
  public var label = ""
  public var redline: Double?
  public var warningColor = "#FF616D"
  public var backgroundPath: String?
  public var backgroundImage: Data?
  public var design: GaugeDesign?
  public init() {}
  public func resolvedLabel(unit: String) -> String {
    label.replacingOccurrences(of: "%su%", with: unit == "mph" ? "MPH" : unit, options: .caseInsensitive)
  }
}

public struct GaugeColorChange: Codable, Equatable, Sendable {
  public var enabled = false
  public var threshold: Double = 6500
  public var color = "#FF4444"
  public var gradient = false
  public var start: Double = 6000
  public var secondEnabled = false
  public var secondThreshold: Double = 7500
  public var secondColor = "#FF0000"
  public init() {}
}

public struct GaugeCaption: Codable, Equatable, Sendable {
  public var font = "Helvetica"
  public var size: Double = 12
  public var color = "#FFFFFF"
  public var bold = false
  public var italic = false
  public var automaticPosition = true
  public var x: Double = 50
  public var y: Double = 40
  public init() {}
}

public struct GaugeDesign: Codable, Equatable, Sendable {
  public enum Mode: String, Codable, CaseIterable, Sendable { case needle, dualNeedle, filled }
  public enum Mark: String, Codable, CaseIterable, Sendable { case dash, dot, triangle }
  public var mode: Mode = .needle
  public var automaticMinimum = false
  public var automaticMaximum = false
  public var smoothing: Double = 0
  public var splitValue: Double?
  public var splitAngle: Double = 135
  public var faceColor = "#121820"
  public var faceGradient = false
  public var faceSecondColor = "#000000"
  public var trim = true
  public var trimColor = "#FFFFFF"
  public var trimWidth: Double = 1
  public var needleColor = "#FFFFFF"
  public var centerColor = "#FFFFFF"
  public var centerSize: Double = 5
  public var tip: Double = 85
  public var tail: Double = 12
  public var needleWidth: Double = 2
  public var taper: Double = 0
  public var dualColor = "#FFB44D"
  public var dualTip: Double = 55
  public var dualTail: Double = 8
  public var dualWidth: Double = 3
  public var dualInterval: Double = 1000
  public var fillInnerRadius: Double = 70
  public var marksColor = "#FFFFFF"
  public var minorColor = "#AAAAAA"
  public var majorStyle: Mark = .dash
  public var minorStyle: Mark = .dash
  public var majorLength: Double = 10
  public var minorLength: Double = 5
  public var majorWidth: Double = 1
  public var minorWidth: Double = 0.5
  public var minorInterval: Double?
  public var minorDivisions: Int = 4
  public var showMajor = true
  public var showMinor = true
  public var pins = false
  public var pinColor = "#FFFFFF"
  public var pinSize: Double = 3
  public var everyOtherNumber = false
  public var numberExtremes = true
  public var limitClutter = true
  public var numberStyle = GaugeCaption()
  public var labelStyle = GaugeCaption()
  public var valueStyle: GaugeCaption = { var c = GaugeCaption(); c.size = 30; return c }()
  public var needleChange = GaugeColorChange()
  public var markingChange = GaugeColorChange()
  public var faceChange = GaugeColorChange()
  public init() {}

  public func fraction(_ value: Double, minimum: Double, maximum: Double, sweep: Double) -> Double {
    guard value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum else { return 0 }
    let v = max(minimum, min(maximum, value))
    if let split = splitValue, split.isFinite, split > minimum, split < maximum {
      let position = max(0.001, min(0.999, splitAngle / max(1, sweep)))
      return v <= split ? (v - minimum) / (split - minimum) * position : position + (v - split) / (maximum - split) * (1 - position)
    }
    return (v - minimum) / (maximum - minimum)
  }
}

extension DisplayObject {
  /// Keep imported payloads on their established renderer until the user edits the expanded design.
  public var editableGaugeDesign: GaugeDesign {
    if let design = gauge?.design { return design }
    var g = GaugeDesign(); g.needleColor = color; g.centerColor = color
    guard legacyType == 30, let d = legacyPayload, d.count >= 640 else { return g }
    func hex(_ p: Int) -> String { String(format: "#%06X", d.u32(p) & 0xffffff) }
    let width = Double((legacyCommon?.u32(296) ?? 0) & 0xffff)
    let height = Double((legacyCommon?.u32(296) ?? 0) >> 16)
    let radius = max(1, min(width, height) * 0.24)
    func percent(_ v: Double) -> Double { v / radius * 100 }
    g.automaticMinimum = abs(d.f64(256)) >= 9e7
    g.automaticMaximum = abs(d.f64(264)) >= 9e7
    g.faceColor = hex(300); g.faceSecondColor = hex(304); g.faceGradient = d.u32(304) >> 24 != 255
    g.trimColor = hex(316); g.trim = d.u32(316) >> 24 != 255
    g.needleColor = hex(308); g.centerColor = hex(312); g.marksColor = hex(320)
    g.needleWidth = percent(Double(d[623]) * 2); g.tip = percent(Double(d[624]))
    g.tail = percent(Double(Int8(bitPattern: d[625]))); g.centerSize = percent(Double(d[626]))
    g.trimWidth = percent(Double(d[622])); g.taper = Double(d[635])
    g.majorWidth = percent(Double(d[629]) / 2); g.minorWidth = percent(Double(d[630]) / 2)
    g.everyOtherNumber = d[633] & 2 != 0
    g.numberExtremes = d[633] & 4 != 0
    g.limitClutter = d[619] & 8 != 0
    g.smoothing = d[619] & 2 != 0 ? 0.2 : 0
    if d.count >= 658, d.f64(648).isFinite, d.f64(648) > minimum, d.f64(648) < maximum, d[656] != 0 || d[657] != 0 {
      g.splitValue = d.f64(648); g.splitAngle = Double(d[656]) + Double(d[657]) * 256
    }
    let minor = d.f64(280); g.minorInterval = minor.isFinite && minor > 0 && minor < 9e7 ? minor : nil
    g.labelStyle.font = d.utf16(352, 128); g.labelStyle.size = percent(d.f32(608)); g.labelStyle.color = hex(332)
    g.valueStyle.font = d.utf16(480, 128); g.valueStyle.size = percent(d.f32(612)); g.valueStyle.color = hex(336)
    g.numberStyle = g.labelStyle
    g.labelStyle.bold = d[616] & 1 != 0; g.labelStyle.italic = d[616] & 2 != 0
    g.valueStyle.bold = d[617] & 1 != 0; g.valueStyle.italic = d[617] & 2 != 0
    let designWidth = max(1, width / 2), designHeight = max(1, height / 2)
    func position(_ style: inout GaugeCaption, _ offset: Int) {
      let xy = d.u32(offset)
      if xy != UInt32.max {
        style.automaticPosition = false; style.x = Double(xy & 0xffff) / designWidth * 100
        style.y = (1 - Double(xy >> 16) / designHeight) * 100
      }
    }
    position(&g.labelStyle, 344); position(&g.valueStyle, 348)
    if d.count >= 696 {
      g.numberStyle.size = percent(d.f32(664)); g.numberStyle.color = hex(692)
      g.minorColor = hex(684); g.majorLength = percent(Double(d[688])); g.minorLength = percent(Double(d[689]))
      g.dualColor = hex(680); g.dualWidth = percent(Double(d[669])); g.dualTip = percent(Double(d[670]))
      g.dualTail = percent(Double(Int8(bitPattern: d[671])))
      g.dualInterval = d.f64(672) > 0 ? d.f64(672) : gauge?.tickInterval ?? 1000
    }
    if d[619] & 0x70 == 0x10 { g.mode = .dualNeedle }
    if d[619] & 0x70 == 0x30 { g.mode = .filled }
    g.pins = d.u32(340) >> 24 != 255; g.pinColor = hex(340); g.pinSize = percent(Double(d[628]))
    for (key, bit) in [(\GaugeDesign.markingChange, UInt8(1)), (\GaugeDesign.needleChange, 4), (\GaugeDesign.faceChange, 16)] {
      g[keyPath: key].enabled = d[634] & bit != 0
      g[keyPath: key].gradient = d[634] & (bit << 1) != 0
      g[keyPath: key].threshold = d.f64(288); g[keyPath: key].color = hex(328)
    }
    return g
  }
}
