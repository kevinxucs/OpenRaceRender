import AppKit
import CoreImage

public enum PictureProcessor {
  public static func apply(_ original: CIImage, settings s: PictureSettings) -> CIImage {
    let b = original.extent
    let left = max(0, min(0.95, s.left)), right = max(0, min(0.95-left, s.right))
    let bottom = max(0, min(0.95, s.bottom)), top = max(0, min(0.95-bottom, s.top))
    let crop = CGRect(x: b.minX+b.width*left, y: b.minY+b.height*bottom,
      width: b.width*(1-left-right), height: b.height*(1-top-bottom))
    var image = original.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    if s.flipX { image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: crop.width, ty: 0)) }
    if s.flipY { image = image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: crop.height)) }
    if s.rotation.isFinite && s.rotation != 0 {
      image = image.transformed(by: CGAffineTransform(rotationAngle: s.rotation * .pi / 180))
      image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
    if s.brightness != 1 || s.contrast != 1 || s.saturation != 1 {
      image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: max(-1, min(1, s.brightness-1)), kCIInputContrastKey: max(0, min(2, s.contrast)), kCIInputSaturationKey: max(0, min(2, s.saturation))])
    }
    return image
  }
  public static func draw(_ c: CGContext, image: CIImage, in rect: CGRect, opacity: Double,
    input: PictureSettings? = nil, object: PictureSettings? = nil, context: CIContext) {
    var image = image
    if let settings = input { image = apply(image, settings: settings) }
    if let settings = object { image = apply(image, settings: settings) }
    guard rect.width > 0, rect.height > 0, !image.extent.isEmpty,
      let cg = context.createCGImage(image, from: image.extent) else { return }
    var destination = rect
    if object?.maintainAspect ?? true {
      let scale = min(rect.width / Double(cg.width), rect.height / Double(cg.height))
      let w = Double(cg.width)*scale, h = Double(cg.height)*scale
      destination = CGRect(x: rect.midX-w/2, y: rect.midY-h/2, width: w, height: h)
    }
    c.saveGState(); c.clip(to: rect); c.setAlpha(max(0, min(1, opacity))); c.draw(cg, in: destination); c.restoreGState()
  }
}
