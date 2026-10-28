import CoreGraphics
import CoreImage
import Foundation

public struct SphericalProjection:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable {case equirectangular,fisheye}
  public enum Axis:String,Codable,CaseIterable,Sendable {case up,forward}
  public var mode:Mode = .equirectangular
  public var pan:Double = 0
  public var fieldOfView:Double = 240
  public var centerX:Double = 0.5
  public var centerY:Double = 0.5
  public var radius:Double = 0.5
  public var axis:Axis = .up
  public init() {}
  public func validate() throws {
    guard pan.isFinite,(-360...360).contains(pan),fieldOfView.isFinite,(1...360).contains(fieldOfView),
      centerX.isFinite,centerY.isFinite,(0...1).contains(centerX),(0...1).contains(centerY),radius.isFinite,(0.01...1).contains(radius) else {throw RaceError.invalid("Invalid spherical projection: pan ±360°, field of view 1–360°, center 0–1 and radius 0.01–1 of the shorter source dimension.")}
    if SphericalProjectionRenderer.unwrap == nil {throw RaceError.invalid("The fisheye projection kernel is unavailable on this system.")}
  }
}

enum SphericalProjectionRenderer {
  /// Equidistant single-lens model. Uncovered rays sample transparent pixels; no fake hemisphere is generated.
  static let unwrap = CIKernel(source:"""
    kernel vec4 raceFisheye(sampler picture, vec4 dimensions, vec4 lens, float fov, float pan, float fisheye, float upAxis) {
      vec2 p = destCoord();
      if (fisheye < 0.5) {
        vec2 wrapped = vec2(fract(p.x / dimensions.z + pan / 6.28318530718) * dimensions.z, p.y);
        if (wrapped.x < 0.5 || wrapped.x > dimensions.z - 0.5) {
          vec4 left = sample(picture, samplerTransform(picture, vec2(dimensions.z - 0.5, wrapped.y)));
          vec4 right = sample(picture, samplerTransform(picture, vec2(0.5, wrapped.y)));
          float blend = wrapped.x < 0.5 ? wrapped.x + 0.5 : wrapped.x - (dimensions.z - 0.5);
          return mix(left, right, blend);
        }
        return sample(picture, samplerTransform(picture, wrapped));
      }
      float longitude = (p.x / dimensions.x - 0.5) * 6.28318530718 + pan;
      float latitude = (p.y / dimensions.y - 0.5) * 3.14159265359;
      float x = sin(longitude) * cos(latitude);
      float y = sin(latitude);
      float z = cos(longitude) * cos(latitude);
      if (upAxis > 0.5) { float previousY = y; y = z; z = previousY; }
      float theta = acos(clamp(z, -1.0, 1.0));
      if (theta > fov * 0.5) { return vec4(0.0); }
      float magnitude = length(vec2(x, y));
      vec2 direction = magnitude > 0.0000001 ? vec2(x, y) / magnitude : vec2(0.0);
      float distance = theta / (fov * 0.5) * lens.z;
      vec2 source = vec2(lens.x, lens.y) + direction * distance;
      if (source.x < 0.0 || source.y < 0.0 || source.x >= dimensions.z || source.y >= dimensions.w) {return vec4(0.0);}
      return sample(picture, samplerTransform(picture, source));
    }
    """)
  static func apply(_ source:CIImage,settings:SphericalProjection?) -> CIImage {
    guard let settings,(try? settings.validate()) != nil else {return source}
    let bounds = source.extent
    guard !bounds.isEmpty,bounds.width.isFinite,bounds.height.isFinite else {return source}
    let image = source.transformed(by:CGAffineTransform(translationX:-bounds.minX,y:-bounds.minY))
    let size = CGRect(x:0,y:0,width:bounds.width,height:bounds.height)
    let diameter = min(bounds.width,bounds.height)
    let output = settings.mode == .fisheye ? CGRect(x:0,y:0,width:diameter*2,height:diameter) : size
    let dimensions = CIVector(x:output.width,y:output.height,z:bounds.width,w:bounds.height)
    let lens = CIVector(x:bounds.width*CGFloat(settings.centerX),y:bounds.height*CGFloat(settings.centerY),z:diameter*CGFloat(settings.radius),w:0)
    let fov = settings.fieldOfView * Double.pi/180
    let pan = settings.pan * Double.pi/180
    let axis:Double = settings.axis == .up ? 1 : 0
    let arguments:[Any] = [image,dimensions,lens,fov,pan,settings.mode == .fisheye ? 1.0 : 0.0,axis]
    return unwrap?.apply(extent:output,roiCallback:{_,_ in size},arguments:arguments) ?? image
  }
}

extension RaceProject {
  public var coordinateSpan:Double {sphericalWorkspace == true ? 300 : 100}
  public var workspaceBounds:CGRect {CGRect(x:coordinateOrigin,y:coordinateOrigin,width:coordinateSpan,height:coordinateSpan)}
  public var coordinateOrigin:Double {sphericalWorkspace == true ? -100 : 0}
  public func canvasRect(_ rect:CGRect,size:CGSize) -> CGRect {
    CGRect(x:(rect.minX-coordinateOrigin)/coordinateSpan*size.width,y:(rect.minY-coordinateOrigin)/coordinateSpan*size.height,
      width:rect.width/coordinateSpan*size.width,height:rect.height/coordinateSpan*size.height)
  }
  public func workspacePoint(_ point:CGPoint,size:CGSize) -> CGPoint {
    CGPoint(x:point.x/max(1,size.width)*coordinateSpan+coordinateOrigin,y:point.y/max(1,size.height)*coordinateSpan+coordinateOrigin)
  }
  public mutating func setSphericalWorkspace(_ enabled:Bool) {
    sphericalWorkspace = enabled ? true : nil
    if enabled {
      width = 3840;height = 1920
      exportSettings?.output?.width = nil;exportSettings?.output?.height = nil;exportSettings?.output?.border = 0
      exportSettings?.profileID = nil;exportSettings?.sphericalMetadata = nil
    } else {width = 1920;height = 1080;exportSettings?.sphericalMetadata = nil}
  }
}
