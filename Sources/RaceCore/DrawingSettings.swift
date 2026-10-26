import AppKit

public struct TextSettings: Codable, Equatable, Sendable {
  public enum Alignment: String, Codable, CaseIterable, Sendable { case left, center, right }
  public var font = "Helvetica"
  public var size: Double = 48
  /// Point sizes are measured at this canvas height, keeping exports resolution independent.
  public var referenceHeight: Double = 1080
  public var bold = false
  public var italic = false
  public var underline = false
  public var strikethrough = false
  public var alignment: Alignment = .left
  public var fitToBox = false
  public var outline = false
  public var outlineColor = "#000000"
  public var outlineWidth: Double = 2
  public init() {}
}

public struct ShapeSettings: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case rectangle, roundedRectangle, rounderRectangle, ellipse, triangle, diamond, line
    public var title: String {
      switch self {
      case .roundedRectangle: return "Rounded rectangle"
      case .rounderRectangle: return "Rounder rectangle"
      default: return rawValue.capitalized
      }
    }
  }
  public var kind: Kind = .rectangle
  public var fill = true
  public var gradient = false
  public var gradientColor = "#000000"
  public var gradientAngle: Double = 90
  public var stroke = false
  public var strokeColor = "#FFFFFF"
  public var strokeWidth: Double = 3
  public var referenceHeight: Double = 1080
  public init() {}
}

enum DrawingRenderer {
  static func text(_ c: CGContext, object o: DisplayObject, rect r: CGRect, height: Double) {
    guard let settings = o.typography else { return }
    let content = o.text.isEmpty ? o.name : o.text
    let scale = height / max(1, settings.referenceHeight)
    let requested = settings.size.isFinite ? max(1, min(2000, settings.size)) * scale : 48 * scale
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = settings.alignment == .left ? .left : settings.alignment == .center ? .center : .right
    paragraph.lineBreakMode = .byWordWrapping
    func string(_ size: Double, outlined: Bool = false) -> NSAttributedString {
      var font = NSFont(name: settings.font, size: size) ?? NSFont.systemFont(ofSize: size)
      if settings.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
      if settings.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font, .paragraphStyle: paragraph,
        .foregroundColor: NSColor(cgColor: OverlayRenderer.color(o.color)) ?? .white,
      ]
      if settings.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      if settings.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if outlined {
        attributes[.strokeColor] = NSColor(cgColor: OverlayRenderer.color(settings.outlineColor))
        attributes[.strokeWidth] = -100 * max(0, min(30, settings.outlineWidth)) * scale / max(1, size)
      }
      return NSAttributedString(string: content, attributes: attributes)
    }
    let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    var size = requested
    if settings.fitToBox {
      var lower = max(0.5, requested / 200), upper = requested
      for _ in 0..<12 {
        let trial = (lower + upper) / 2
        let bounds = string(trial).boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude), options: options)
        if bounds.height <= r.height && bounds.width <= r.width + 0.5 { lower = trial } else { upper = trial }
      }
      size = lower
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    string(size, outlined: settings.outline).draw(with: r, options: options)
    NSGraphicsContext.restoreGraphicsState()
  }

  static func shape(_ c: CGContext, object o: DisplayObject, rect r: CGRect, height: Double) {
    guard let s = o.shape else { return }
    let width = s.strokeWidth.isFinite ? max(0, min(200, s.strokeWidth)) * height / max(1, s.referenceHeight) : 0
    let area = r.insetBy(dx: s.stroke ? min(r.width / 2, width / 2) : 0, dy: s.stroke ? min(r.height / 2, width / 2) : 0)
    guard area.width > 0, area.height > 0 else { return }
    let path = CGMutablePath()
    switch s.kind {
    case .rectangle: path.addRect(area)
    case .roundedRectangle, .rounderRectangle:
      let radius = min(area.width, area.height) * (s.kind == .roundedRectangle ? 0.15 : 0.5)
      path.addRoundedRect(in: area, cornerWidth: radius, cornerHeight: radius)
    case .ellipse: path.addEllipse(in: area)
    case .triangle:
      path.move(to: CGPoint(x: area.midX, y: area.maxY)); path.addLine(to: CGPoint(x: area.maxX, y: area.minY)); path.addLine(to: area.origin); path.closeSubpath()
    case .diamond:
      path.move(to: CGPoint(x: area.midX, y: area.maxY)); path.addLine(to: CGPoint(x: area.maxX, y: area.midY)); path.addLine(to: CGPoint(x: area.midX, y: area.minY)); path.addLine(to: CGPoint(x: area.minX, y: area.midY)); path.closeSubpath()
    case .line: path.move(to: area.origin); path.addLine(to: CGPoint(x: area.maxX, y: area.maxY))
    }
    if s.fill && s.kind != .line {
      c.saveGState(); c.addPath(path); c.clip()
      if s.gradient, let gradient = CGGradient(colorsSpace: OverlayRenderer.colorSpace,
        colors: [OverlayRenderer.color(o.color), OverlayRenderer.color(s.gradientColor)] as CFArray, locations: [0, 1]) {
        let angle = (s.gradientAngle.isFinite ? s.gradientAngle : 90) * .pi / 180
        let dx = cos(angle), dy = sin(angle), extent = (abs(dx) * area.width + abs(dy) * area.height) / 2
        c.drawLinearGradient(gradient, start: CGPoint(x: area.midX - dx * extent, y: area.midY - dy * extent),
          end: CGPoint(x: area.midX + dx * extent, y: area.midY + dy * extent), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      } else { c.setFillColor(OverlayRenderer.color(o.color)); c.fill(area) }
      c.restoreGState()
    }
    if s.stroke || s.kind == .line {
      c.setStrokeColor(OverlayRenderer.color(s.strokeColor)); c.setLineWidth(max(0.5, width)); c.setLineJoin(.round); c.setLineCap(.round)
      c.addPath(path); c.strokePath()
    }
  }
}
