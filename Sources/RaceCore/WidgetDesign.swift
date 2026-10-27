import AppKit

/// A reusable display, without the source paths or timeline of its originating session.
public struct WidgetStyle: Identifiable, Sendable {
  public var id: String
  public var name: String
  public var object: DisplayObject
  public init(id: String, name: String, object: DisplayObject) {
    self.id = id; self.name = name; self.object = object
  }
  public static func read(_ url: URL) throws -> [WidgetStyle] {
    let layout = try RaceProject.read(url).reusableLayout()
    return layout.objects.enumerated().filter { ![.video, .audio, .group].contains($0.element.kind) }.map {
      WidgetStyle(id: url.path + "#\($0.offset)", name: $0.element.name, object: $0.element)
    }
  }
}

extension DisplayObject {
  public var hasStyleRange: Bool { [31, 50].contains(legacyType ?? -1) && (legacyPayload?.count ?? 0) >= 280 }
  public var hasScriptStyleSettings: Bool { legacyType == 50 && (legacyPayload?.count ?? 0) >= 67168 }
  public var styleMinimum: Double? {
    get { styleBound(256) }
    set { setStyleBound(newValue, at: 256); if let newValue { minimum = newValue } }
  }
  public var styleMaximum: Double? {
    get { styleBound(264) }
    set { setStyleBound(newValue, at: 264); if let newValue { maximum = newValue } }
  }
  private func styleBound(_ offset: Int) -> Double? {
    guard hasStyleRange, let value = legacyPayload?.f64(offset), value.isFinite, abs(value) < 9e7 else { return nil }
    return value
  }
  private mutating func setStyleBound(_ value: Double?, at offset: Int) {
    guard hasStyleRange, value == nil || value!.isFinite else { return }
    let bits = (value ?? 100_000_000).bitPattern
    legacyPayload?.putU32(UInt32(truncatingIfNeeded: bits), offset)
    legacyPayload?.putU32(UInt32(bits >> 32), offset+4)
  }
  public var styleLabel: String {
    get { hasScriptStyleSettings ? legacyPayload!.utf16(128, 128) : "" }
    set { guard hasScriptStyleSettings else { return }; legacyPayload?.putUTF16(newValue, 128, 128) }
  }
  public var styleLabelVisible: Bool {
    get { hasScriptStyleSettings && legacyPayload![569] != 0 }
    set { guard hasScriptStyleSettings else { return }; legacyPayload?[569] = newValue ? 1 : 0 }
  }
  public var styleLabelSize: Double {
    get { hasScriptStyleSettings ? legacyPayload!.f32(560) : 20 }
    set { guard hasScriptStyleSettings, newValue.isFinite else { return }; legacyPayload?.putFloat(max(1, min(1000, newValue)), 560) }
  }
  public var styleTrigger: Double {
    get { hasScriptStyleSettings ? legacyPayload!.f64(272) : 0 }
    set {
      guard hasScriptStyleSettings, newValue.isFinite else { return }
      let bits = newValue.bitPattern
      legacyPayload?.putU32(UInt32(truncatingIfNeeded: bits), 272); legacyPayload?.putU32(UInt32(bits >> 32), 276)
    }
  }
  public func styleColor(_ index: Int) -> String {
    guard hasScriptStyleSettings, (0..<8).contains(index) else { return color }
    return String(format: "#%06X", legacyPayload!.u32(576+index*4) & 0xffffff)
  }
  public mutating func setStyleColor(_ color: String, index: Int) {
    guard hasScriptStyleSettings, (0..<8).contains(index), let rgb = UInt32(color.replacingOccurrences(of: "#", with: ""), radix: 16) else { return }
    legacyPayload?.putU32(rgb & 0xffffff, 576+index*4)
  }
  /// Appearance changes retain the instance's position, source and timeline.
  public func applyingStyle(_ style: DisplayObject) -> DisplayObject {
    var result = style
    result.id = id; result.name = name; result.kind = kind
    result.inputIndex = inputIndex; result.channel = channel
    result.mapComparison = mapComparison
    result.x = x; result.y = y; result.width = width; result.height = height
    result.opacity = opacity; result.visible = visible; result.start = start; result.end = end
    result.segments = segments; result.parentIndex = parentIndex; result.parentID = parentID
    result.legacyIndex = legacyIndex; result.legacyOffset = nil
    result.picture = picture
    if style.hasScriptStyleSettings,let aspect = style.picture?.maintainAspect {
      var settings = picture ?? PictureSettings();settings.maintainAspect = aspect;result.picture = settings
    }
    if result.hud != nil, let hud {
      result.hud?.label = hud.label
      if [.metric, .odometer].contains(hud.role), let role = result.hud?.role, [.metric, .odometer].contains(role) {
        result.hud?.unit = hud.unit; result.hud?.decimals = hud.decimals; result.hud?.multiplier = hud.multiplier
      }
      if hud.role == .tyres && result.hud?.role == .tyres { result.hud?.unit = hud.unit }
    }
    if kind == .text { result.text = text }
    if kind == .image, style.artwork == nil, style.embeddedImage == nil, style.text.isEmpty {
      result.artwork = artwork; result.embeddedImage = embeddedImage; result.text = text
    }
    return result
  }
  public func placed(at point: CGPoint) -> DisplayObject {
    var result = self
    result.x = max(0, min(max(0, 100-width), point.x-width/2))
    result.y = max(0, min(max(0, 100-height), point.y-height/2))
    return result
  }
}

/// Sample values are used only for design previews, never saved or exported.
public enum WidgetDesign {
  public static let telemetry: Telemetry = {
    var rows = ["Time,Speed (km/h),RPM,Gear,Throttle,Brake,Accel X,Accel Y,Latitude,Longitude,Distance,Lap,Engine oil temperature (.C),Coolant temperature (.C),Intake temperature (.C)"]
    for i in 0...120 {
      let t = Double(i), angle = t / 60 * 2 * Double.pi
      rows.append("\(t),\(90+40*sin(angle)),\(4500+2000*sin(angle)),3,75,0,0.2,\(sin(angle)),\(36+0.001*cos(angle)),\(-121+0.001*sin(angle)),\(t*25),\(i/60+1),105,92,32")
    }
    return try! Telemetry(text: rows.joined(separator: "\n"))
  }()
  public static func scene(_ project: RaceProject) -> RenderScene {
    var preview = project
    // Give empty source roles a placement, including the -1 role of unbound widgets.
    var indices = Set(preview.objects.filter { ![.video, .audio, .image, .shape, .text, .group].contains($0.kind) }.map(\.inputIndex))
    for i in preview.inputs.indices where preview.inputs[i].kind == "data" {
      indices.insert(preview.inputs[i].legacyIndex)
      preview.inputs[i].duration = 120; preview.inputs[i].offset = 0; preview.inputs[i].timing = nil
    }
    for index in indices where !preview.inputs.contains(where: { $0.legacyIndex == index }) {
      var input = MediaInput(name: "Design sample", path: "", kind: "data", legacyIndex: index)
      input.duration = 120; preview.inputs.append(input)
    }
    return RenderScene(project: preview, telemetry: Dictionary(uniqueKeysWithValues: indices.map { ($0, telemetry) }))
  }
  public static func thumbnail(_ object: DisplayObject) -> NSImage? {
    var p = RaceProject(), o = object
    p.width = 240; p.height = 140
    o.x = 3; o.y = 3; o.width = 94; o.height = 94
    o.visible = true; o.opacity = 1; o.start = 0; o.end = 1_000_000; o.segments = nil
    p.objects = [o]
    guard let c = CGContext(data: nil, width: 240, height: 140, bitsPerComponent: 8, bytesPerRow: 0,
      space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    OverlayRenderer.draw(c, scene: scene(p), time: 18, size: CGSize(width: 240, height: 140))
    return c.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: 240, height: 140)) }
  }
}
