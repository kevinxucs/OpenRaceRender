import AppKit
import CoreImage

public struct ChromaKeySettings:Codable,Equatable,Sendable {
  public var color = "#00FF00"
  public var colorTolerance:Double = 0.1
  public var brightnessTolerance:Double = 0.2
  public var softness:Double = 0.03
  public init() {}
}
public struct ColorizeSettings:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable { case tint,spectrum }
  public var mode:Mode = .tint
  public var color = "#FFFFFF"
  public var amount:Double = 1
  public init() {}
}

extension PictureSettings {
  public func validateEffects() throws {
    func valid(_ value:Double) -> Bool { value.isFinite && (0...1).contains(value) }
    if let key = chromaKey {
      guard PictureEffects.rgb(key.color) != nil,valid(key.colorTolerance),valid(key.brightnessTolerance),valid(key.softness) else {
        throw RaceError.invalid("Chroma key needs a six-digit RGB color and tolerances/softness from 0 to 1.")
      }
    }
    if let tint = colorize {
      guard (tint.mode == .spectrum || PictureEffects.rgb(tint.color) != nil),valid(tint.amount) else { throw RaceError.invalid("Colorize needs a six-digit RGB color and amount from 0 to 1.") }
    }
  }
}

enum PictureEffects {
  static func rgb(_ string:String) -> CIVector? {
    let value = string.hasPrefix("#") ? String(string.dropFirst()) : string
    guard value.count == 6,let number = UInt32(value,radix:16) else { return nil }
    return CIVector(x:Double(number>>16&255)/255,y:Double(number>>8&255)/255,z:Double(number&255)/255)
  }
  static let kernel = CIColorKernel(source:"""
    kernel vec4 pictureEffects(__sample source, float keyOn, vec3 key, float colorRange, float brightnessRange, float softness, float tintOn, vec3 tint, float spectrum, float amount) {
      vec4 pixel = unpremultiply(source);
      vec3 rgb = pixel.rgb;
      float alpha = pixel.a;
      float value = max(rgb.r, max(rgb.g, rgb.b));
      if (keyOn > 0.0) {
        float keyValue = max(key.r, max(key.g, key.b));
        vec3 chroma = rgb / max(value, 0.00001);
        vec3 keyChroma = key / max(keyValue, 0.00001);
        float difference = keyValue < 0.00001 ? 0.0 : length(chroma - keyChroma) / 1.7320508;
        float matchedColor = 1.0 - smoothstep(colorRange, colorRange + max(softness, 0.00001), difference);
        float matchedValue = 1.0 - smoothstep(brightnessRange, brightnessRange + max(softness, 0.00001), abs(value - keyValue));
        alpha *= 1.0 - matchedColor * matchedValue;
      }
      if (tintOn > 0.0) {
        vec3 color = tint;
        if (spectrum > 0.0) {
          float hue = fract(1.0 - value);
          color = clamp(abs(fract(vec3(hue) + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        }
        rgb = mix(rgb, color * value, amount);
      }
      return premultiply(vec4(rgb, alpha));
    }
    """)!
  static func apply(_ image:CIImage,settings:PictureSettings) -> CIImage {
    guard settings.chromaKey != nil || settings.colorize != nil,(try? settings.validateEffects()) != nil else { return image }
    let key = settings.chromaKey ?? ChromaKeySettings(),tint = settings.colorize ?? ColorizeSettings()
    return kernel.apply(extent:image.extent,arguments:[image,settings.chromaKey == nil ? 0.0 : 1.0,rgb(key.color)!,key.colorTolerance,key.brightnessTolerance,key.softness,
      settings.colorize == nil ? 0.0 : 1.0,rgb(tint.color) ?? CIVector(x:1,y:1,z:1),tint.mode == .spectrum ? 1.0 : 0.0,tint.amount]) ?? image
  }
}
