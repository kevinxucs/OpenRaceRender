import AppKit
import CoreImage

public struct ImageControlSettings: Codable, Equatable, Sendable {
  public enum Mode: String, Codable, CaseIterable, Sendable {
    case simple, proportional, greaterOrEqual, lessOrEqual
    public var title: String {
      switch self { case .simple:return "Static image"; case .proportional:return "Proportional data"
      case .greaterOrEqual:return "At or above threshold"; case .lessOrEqual:return "At or below threshold" }
    }
  }
  public enum Output: String, Codable, CaseIterable, Sendable {
    case visibility, opacity, rotation, brightness, hue
    public var title: String {
      switch self { case .visibility:return "Visibility"; case .opacity:return "Opacity (%)"
      case .rotation:return "Rotation (degrees)"; case .brightness:return "Brightness (%; 100 = normal)"; case .hue:return "Hue (degrees)" }
    }
  }
  public var mode: Mode = .simple
  public var output: Output = .opacity
  public var inputMinimum: Double = 0
  public var inputMaximum: Double = 100
  public var outputMinimum: Double = 0
  public var outputMaximum: Double = 100
  /// Seconds per on/off phase. Zero disables flashing; no frame history is needed.
  public var pulseInterval: Double = 0
  public init() {}
  public var usesData: Bool { mode != .simple }
  public func mappedValue(_ value: Double?) -> Double? {
    guard usesData, let value, value.isFinite,
      [inputMinimum,inputMaximum,outputMinimum,outputMaximum].allSatisfy(\.isFinite) else { return nil }
    let fraction: Double
    switch mode {
    case .simple: return nil
    case .greaterOrEqual: fraction = value >= inputMaximum ? 1 : 0
    case .lessOrEqual: fraction = value <= inputMinimum ? 1 : 0
    case .proportional:
      let span = inputMaximum-inputMinimum
      fraction = abs(span) > 1e-12 ? max(0,min(1,(value-inputMinimum)/span)) : value >= inputMaximum ? 1 : 0
    }
    return outputMinimum + fraction*(outputMaximum-outputMinimum)
  }
  public func isPulseOn(at time: Double) -> Bool {
    guard pulseInterval.isFinite, pulseInterval > 0, time.isFinite else { return true }
    // Floating remainder avoids integer overflow on long sessions/tiny intervals.
    return max(0,time).truncatingRemainder(dividingBy:2*max(0.001,pulseInterval)) < max(0.001,pulseInterval)
  }
  static func legacy(_ o: DisplayObject) -> ImageControlSettings? {
    guard let b = o.legacyPayload, b.count >= 164 else { return nil }
    var s = ImageControlSettings()
    s.mode = b[160] == 1 ? .proportional : b[160] == 2 ? .greaterOrEqual : b[160] == 3 ? .lessOrEqual : .simple
    s.output = b[161] == 2 ? .rotation : b[161] == 4 ? .brightness : b[161] == 5 ? .hue : .opacity
    s.inputMinimum = b.f64(128); s.inputMaximum = b.f64(136)
    s.outputMinimum = b.f64(144); s.outputMaximum = b.f64(152)
    if s.output == .opacity { s.outputMinimum = 100-s.outputMinimum; s.outputMaximum = 100-s.outputMaximum }
    s.pulseInterval = Double(b[162])/10
    return s
  }
}

extension DisplayObject {
  public var imageUsesData: Bool { kind == .image && (imageControl?.usesData == true) }
}

public struct ImageControlState: Equatable, Sendable {
  public var visible = true
  public var opacity: Double = 1
  public var rotation: Double = 0
  public var brightness: Double = 1
  public var hue: Double = 0
  public init() {}
  public static func resolve(_ settings: ImageControlSettings?, value: Double?, sourceAvailable: Bool, projectTime: Double) -> Self {
    var state = Self()
    guard let s = settings else { return state }
    if !s.isPulseOn(at:projectTime) { state.visible = false }
    guard s.usesData else { return state }
    guard sourceAvailable, let mapped = s.mappedValue(value), mapped.isFinite else { state.visible = false; return state }
    switch s.output {
    case .visibility: state.visible = state.visible && mapped >= 50
    case .opacity: state.opacity = max(0,min(1,mapped/100)); state.visible = state.visible && state.opacity > 0
    case .rotation: state.rotation = mapped.truncatingRemainder(dividingBy:360)
    case .brightness: state.brightness = max(0,min(2,mapped/100))
    case .hue: state.hue = mapped.truncatingRemainder(dividingBy:360)
    }
    return state
  }
}

/// Immutable decoded artwork is shared by preview/export. Color/rotation remain
/// per-frame operations, preserving both transparent pixels and the image center.
public enum ImageRenderer {
  private static let images = NSCache<NSData, ImageBox>()
  private static let fileImages = NSCache<NSString, ImageBox>()
  private static let context = CIContext(options:[.cacheIntermediates:false])
  private final class ImageBox: NSObject { let image: CGImage; init(_ image: CGImage) { self.image = image } }
  private static func image(_ data: Data) -> CGImage? {
    let key = data as NSData
    if let found = images.object(forKey:key) { return found.image }
    guard let ns = NSImage(data:data), let cg = ns.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
    images.totalCostLimit = 64*1024*1024
    images.setObject(ImageBox(cg),forKey:key,cost:cg.bytesPerRow*cg.height); return cg
  }
  @discardableResult public static func draw(_ c: CGContext, object o: DisplayObject, rect: CGRect,
    data: Telemetry?, sourceTime: Double, projectTime: Double) -> Bool {
    let available = data.map { sourceTime >= 0 && sourceTime <= $0.duration } ?? false
    let state = ImageControlState.resolve(o.imageControl,value:available ? data?.value(o.resolvedChannel,at:sourceTime) : nil,
      sourceAvailable:available,projectTime:projectTime)
    guard state.visible else { return true }
    let cg: CGImage
    if let bytes = o.artwork ?? o.embeddedImage, let decoded = image(bytes) { cg = decoded }
    else if !o.text.isEmpty,
      let attributes = try? FileManager.default.attributesOfItem(atPath:o.text),
      let date = attributes[.modificationDate] as? Date {
      let key = "\(o.text):\(date.timeIntervalSince1970):\(attributes[.size] ?? 0)" as NSString
      if let cached = fileImages.object(forKey:key) { cg = cached.image }
      else {
        guard let bytes = try? Data(contentsOf:URL(fileURLWithPath:o.text)), let decoded = image(bytes) else { return false }
        fileImages.totalCostLimit = 64*1024*1024
        fileImages.setObject(ImageBox(decoded),forKey:key,cost:decoded.bytesPerRow*decoded.height); cg = decoded
      }
    } else { return false }
    var picture = o.picture ?? PictureSettings()
    picture.brightness = max(0,min(2,picture.brightness*state.brightness))
    let hue = ((picture.hue ?? 0)+state.hue).truncatingRemainder(dividingBy:360)
    picture.hue = hue > 180 ? hue-360 : hue < -180 ? hue+360 : hue
    c.saveGState()
    if state.rotation != 0 { c.translateBy(x:rect.midX,y:rect.midY); c.rotate(by:state.rotation * .pi/180); c.translateBy(x:-rect.midX,y:-rect.midY) }
    PictureProcessor.draw(c,image:CIImage(cgImage:cg),in:rect,opacity:o.opacity*state.opacity,object:picture,context:context)
    c.restoreGState(); return true
  }
}
