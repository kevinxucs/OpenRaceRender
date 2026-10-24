import AppKit
import CoreImage

public enum PictureProcessor {
  static func legacy601(_ image: CIImage) -> CIImage {
    // Recover Y'CbCr from decoded Rec.709 RGB, then use the legacy decoder's
    // BT.601 coefficients. This is a standards-based matrix, not a fitted tint.
    let y = [0.2126,0.7152,0.0722]
    let cb = [-y[0]/1.8556,-y[1]/1.8556,(1-y[2])/1.8556]
    let cr = [(1-y[0])/1.5748,-y[1]/1.5748,-y[2]/1.5748]
    let red = (0..<3).map { y[$0]+1.402*cr[$0] }
    let green = (0..<3).map { y[$0]-0.344136*cb[$0]-0.714136*cr[$0] }
    let blue = (0..<3).map { y[$0]+1.772*cb[$0] }
    return image.applyingFilter("CIColorMatrix",parameters:[
      "inputRVector":CIVector(x:red[0],y:red[1],z:red[2],w:0),
      "inputGVector":CIVector(x:green[0],y:green[1],z:green[2],w:0),
      "inputBVector":CIVector(x:blue[0],y:blue[1],z:blue[2],w:0)]).applyingFilter("CIColorClamp")
  }
  static func source(_ frame: CVPixelBuffer, settings: PictureSettings?) -> CIImage {
    let image = CIImage(cvPixelBuffer:frame,options:[.colorSpace:NSNull()])
    let matrix = CVBufferCopyAttachment(frame,kCVImageBufferYCbCrMatrixKey,nil) as? String
    let primaries = CVBufferCopyAttachment(frame,kCVImageBufferColorPrimariesKey,nil) as? String
    return settings?.legacyColorInterpretation == true && (matrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String || (matrix == nil && primaries == kCVImageBufferColorPrimaries_ITU_R_709_2 as String)) ? legacy601(image) : image
  }
  static func source(_ cg: CGImage,settings: PictureSettings?) -> CIImage {
    let image = CIImage(cgImage:cg,options:[.colorSpace:NSNull()])
    let name = cg.colorSpace?.name as String? ?? ""
    return settings?.legacyColorInterpretation == true && name.contains("709") ? legacy601(image) : image
  }
  /// Apply picture controls in encoded RGB without an implicit exposure change.
  static func context() -> CIContext {
    CIContext(options:[.cacheIntermediates:false,.workingColorSpace:NSNull(),.outputColorSpace:NSNull()])
  }
  private static let colorControls = CIColorKernel(source:"""
    kernel vec4 racePicture(__sample source, float brightness, float contrast, float saturation, float hue) {
      vec4 pixel = unpremultiply(source);
      vec3 rgb = clamp(pixel.rgb * brightness, 0.0, 1.0);
      rgb = clamp((rgb - vec3(128.0 / 255.0)) * contrast + vec3(128.0 / 255.0), 0.0, 1.0);
      float value = max(rgb.r, max(rgb.g, rgb.b));
      rgb = clamp(vec3(value) + (rgb - vec3(value)) * saturation, 0.0, 1.0);
      if (hue != 0.0) {
        float hi = max(rgb.r, max(rgb.g, rgb.b));
        float lo = min(rgb.r, min(rgb.g, rgb.b));
        float chroma = hi - lo;
        if (chroma > 0.0) {
          float h;
          if (hi == rgb.r) { h = (rgb.g - rgb.b) / chroma; }
          else if (hi == rgb.g) { h = (rgb.b - rgb.r) / chroma + 2.0; }
          else { h = (rgb.r - rgb.g) / chroma + 4.0; }
          h = fract(h / 6.0 + hue / 360.0);
          vec3 wheel = clamp(abs(fract(vec3(h) + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
          rgb = vec3(lo) + chroma * wheel;
        }
      }
      return premultiply(vec4(rgb, pixel.a));
    }
    """)!
  static func positioned(_ original: CIImage, in rect: CGRect, opacity: Double,
    input: PictureSettings?, object: PictureSettings?) -> CIImage {
    var image = original
    if let input { image = apply(image,settings:input) }
    if let object { image = apply(image,settings:object) }
    let b = image.extent
    guard b.width > 0,b.height > 0,rect.width > 0,rect.height > 0 else { return CIImage.empty() }
    var sx = rect.width/b.width,sy = rect.height/b.height
    if object?.maintainAspect ?? true { sx = min(sx,sy);sy = sx }
    let destination = CGRect(x:rect.midX-b.width*sx/2,y:rect.midY-b.height*sy/2,width:b.width*sx,height:b.height*sy)
    image = image.transformed(by:CGAffineTransform(translationX:-b.minX,y:-b.minY))
    if sx < 1 || sy < 1 {
      image = image.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:sy,kCIInputAspectRatioKey:sx/sy])
    } else { image = image.transformed(by:CGAffineTransform(scaleX:sx,y:sy)) }
    image = image.transformed(by:CGAffineTransform(translationX:destination.minX,y:destination.minY)).cropped(to:rect)
    if opacity < 1 { image = image.applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:max(0,opacity))]) }
    return image
  }
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
    if s.brightness != 1 || s.contrast != 1 || s.saturation != 1 || s.hueAdjustment != 0 {
      image = colorControls.apply(extent:image.extent,arguments:[image,max(0,min(2,s.brightness)),max(0,min(2,s.contrast)),max(0,min(2,s.saturation)),s.hueAdjustment]) ?? image
    }
    let sharpness = s.sharpness.flatMap { $0.isFinite ? max(0, min(2, $0)) : nil } ?? 1
    if sharpness < 1 {
      image = image.clampedToExtent().applyingFilter("CIGaussianBlur",
        parameters:[kCIInputRadiusKey: (1 - sharpness) * 2]).cropped(to: image.extent)
    } else if sharpness > 1 {
      image = image.clampedToExtent().applyingFilter("CISharpenLuminance",
        parameters:[kCIInputSharpnessKey: sharpness - 1]).cropped(to: image.extent)
    }
    return image
  }
  public static func draw(_ c: CGContext, image: CIImage, in rect: CGRect, opacity: Double,
    input: PictureSettings? = nil, object: PictureSettings? = nil, context: CIContext) {
    var image = image
    if let settings = input { image = apply(image, settings: settings) }
    if let settings = object { image = apply(image, settings: settings) }
    guard rect.width > 0, rect.height > 0, !image.extent.isEmpty,
      let cg = context.createCGImage(image, from: image.extent,format:.RGBA8,colorSpace:OverlayRenderer.colorSpace) else { return }
    var destination = rect
    if object?.maintainAspect ?? true {
      let scale = min(rect.width / Double(cg.width), rect.height / Double(cg.height))
      let w = Double(cg.width)*scale, h = Double(cg.height)*scale
      destination = CGRect(x: rect.midX-w/2, y: rect.midY-h/2, width: w, height: h)
    }
    c.saveGState(); c.clip(to: rect); c.setAlpha(max(0, min(1, opacity))); c.draw(cg, in: destination); c.restoreGState()
  }
}
