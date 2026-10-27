import AppKit
import CoreImage

/// The background editor works on a private copy and bakes its result into the
/// existing portable artwork layer. Projects need no external editing paths.
public struct BackgroundDraft: Equatable, Sendable {
  public var image: Data?
  public var zoom: Double = 1
  public var offsetX: Double = 0
  public var offsetY: Double = 0
  public var rotation: Double = 0
  public var maintainAspect = true
  public var keyColor: String?
  public var keyTolerance: Double = 0.1
  public var keySoftness: Double = 0.05
  public init(image: Data? = nil) { self.image = image }
  public mutating func resetTransform() { zoom = 1; offsetX = 0; offsetY = 0; rotation = 0; maintainAspect = true; keyColor = nil }
  private static let context = CIContext(options:[.cacheIntermediates:false])
  private static let keyer = CIColorKernel(source:"""
    kernel vec4 keyBackground(__sample pixel, vec3 key, float tolerance, float softness) {
      vec4 p = unpremultiply(pixel);
      float distance = length(p.rgb - key) / 1.7320508;
      float alpha = smoothstep(tolerance, tolerance + max(softness, 0.00001), distance);
      return premultiply(vec4(p.rgb, p.a * alpha));
    }
    """)!
  public func png(width: Int, height: Int) throws -> Data? {
    guard let image else { return nil }
    guard width > 0, height > 0, width <= 4096, height <= 4096,
      let source = NSImage(data:image)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
      throw RaceError.invalid("Choose a readable background image and a canvas no larger than 4096 × 4096.")
    }
    var ci = CIImage(cgImage:source)
    if let keyColor {
      let color = NSColor(cgColor:OverlayRenderer.color(keyColor))!.usingColorSpace(.deviceRGB)!
      ci = Self.keyer.apply(extent:ci.extent,arguments:[ci,CIVector(x:color.redComponent,y:color.greenComponent,z:color.blueComponent),
        max(0,min(1,keyTolerance.isFinite ? keyTolerance : 0.1)),max(0,min(1,keySoftness.isFinite ? keySoftness : 0.05))]) ?? ci
    }
    guard let cg = Self.context.createCGImage(ci,from:ci.extent,format:.RGBA8,colorSpace:OverlayRenderer.colorSpace),
      let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
        space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo) else { throw RaceError.invalid("Could not render the background.") }
    let scale = zoom.isFinite ? max(0.01,min(100,zoom)) : 1
    var sx = Double(width)/Double(cg.width), sy = Double(height)/Double(cg.height)
    if maintainAspect { sx = min(sx,sy); sy = sx }
    let w = Double(cg.width)*sx*scale, h = Double(cg.height)*sy*scale
    func offset(_ value: Double) -> Double { value.isFinite ? max(-1000,min(1000,value))/100 : 0 }
    c.interpolationQuality = .high
    c.translateBy(x:Double(width)*(0.5+offset(offsetX)),y:Double(height)*(0.5+offset(offsetY)))
    c.rotate(by:(rotation.isFinite ? rotation.truncatingRemainder(dividingBy:360) : 0) * .pi/180)
    c.draw(cg,in:CGRect(x:-w/2,y:-h/2,width:w,height:h))
    guard let output = c.makeImage(), let png = NSBitmapImageRep(cgImage:output).representation(using:.png,properties:[:]) else {
      throw RaceError.invalid("Could not encode the background PNG.")
    }
    return png
  }
}

public enum WidgetBackground {
  public static func data(for o: DisplayObject) -> Data? {
    if let data = o.gauge?.backgroundImage { return data }
    if let path = o.gauge?.backgroundPath, let data = try? Data(contentsOf:URL(fileURLWithPath:path)) { return data }
    if let data = o.artwork { return data.isEmpty ? nil : data }
    return o.embeddedImage.flatMap { LegacyArtwork.png($0) ?? (NSImage(data:$0) != nil ? $0 : nil) }
  }
  public static func replacing(_ image: Data?, in original: DisplayObject) -> DisplayObject {
    var o = original
    // Empty data is an explicit timeline clear, distinct from nil/inherit.
    o.artwork = image ?? Data(); o.embeddedImage = nil
    if [.speed,.rpm,.gauge].contains(o.kind) {
      var g = o.gauge ?? GaugeSettings()
      if o.legacyType == 30, g.design == nil { g.design = o.editableGaugeDesign }
      g.backgroundImage = nil; g.backgroundPath = nil
      if image != nil { g.showFace = false }
      o.gauge = g
    }
    if o.kind == .graph, image != nil {
      if o.graph == nil { o.graph = GraphSettings() }; o.graph?.background = false
    }
    return o
  }
  public static func canvasSize(for o: DisplayObject, project: RaceProject, width: Int = 1200) -> CGSize {
    let rawAspect = o.width*Double(project.width)/max(0.001,o.height*Double(project.height))
    let aspect = rawAspect.isFinite && rawAspect > 0 ? rawAspect : 1
    let w = min(4096,max(1,width)), h = min(4096,max(1,Int((Double(w)/max(0.01,aspect)).rounded())))
    return CGSize(width:w,height:h)
  }
}
