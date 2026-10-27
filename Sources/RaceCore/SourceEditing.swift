import Foundation
import CoreGraphics

/// Source-pixel rectangle with a top-left origin, matching the visual crop tool.
public struct CropSelection: Equatable, Sendable {
  public private(set) var sourceSize: CGSize
  public private(set) var rect: CGRect
  public init(size: CGSize, picture: PictureSettings? = nil) {
    sourceSize = CGSize(width:max(1,size.width.isFinite ? size.width : 1),height:max(1,size.height.isFinite ? size.height : 1))
    let s = picture ?? PictureSettings()
    func edge(_ v: Double) -> Double { v.isFinite ? max(0,min(0.95,v)) : 0 }
    let l = edge(s.left), r = min(edge(s.right),0.95-l), t = edge(s.top), b = min(edge(s.bottom),0.95-t)
    rect = CGRect(x:l*sourceSize.width,y:t*sourceSize.height,width:(1-l-r)*sourceSize.width,height:(1-t-b)*sourceSize.height)
    set(rect)
  }
  public mutating func set(_ value: CGRect) {
    guard [value.minX,value.minY,value.width,value.height].allSatisfy(\.isFinite) else { return }
    let value = value.standardized
    let w = min(sourceSize.width,max(max(1,ceil(sourceSize.width*0.05)),value.width.rounded()))
    let h = min(sourceSize.height,max(max(1,ceil(sourceSize.height*0.05)),value.height.rounded()))
    rect = CGRect(x:max(0,min(sourceSize.width-w,value.minX.rounded())),y:max(0,min(sourceSize.height-h,value.minY.rounded())),width:w,height:h)
  }
  public var left: Double { rect.minX }
  public var right: Double { sourceSize.width-rect.maxX }
  public var top: Double { rect.minY }
  public var bottom: Double { sourceSize.height-rect.maxY }
  public mutating func edges(left: Double? = nil, right: Double? = nil, top: Double? = nil, bottom: Double? = nil) {
    var l = self.left, r = self.right, t = self.top, b = self.bottom
    func edge(_ value: Double?, old: Double, maximum: Double) -> Double {
      guard let value, value.isFinite else { return old }; return max(0,min(maximum,value))
    }
    let minW = max(1,ceil(sourceSize.width*0.05)), minH = max(1,ceil(sourceSize.height*0.05))
    l = edge(left,old:l,maximum:sourceSize.width-minW-r)
    r = edge(right,old:r,maximum:sourceSize.width-minW-l)
    t = edge(top,old:t,maximum:sourceSize.height-minH-b)
    b = edge(bottom,old:b,maximum:sourceSize.height-minH-t)
    set(CGRect(x:l,y:t,width:sourceSize.width-l-r,height:sourceSize.height-t-b))
  }
  public mutating func nudge(x: Double, y: Double) { set(rect.offsetBy(dx:x,dy:y)) }
  public mutating func zoom(_ factor: Double) {
    guard factor.isFinite, factor > 0 else { return }
    let lower = max(max(1,ceil(sourceSize.width*0.05))/rect.width,max(1,ceil(sourceSize.height*0.05))/rect.height)
    let upper = min(sourceSize.width/rect.width,sourceSize.height/rect.height)
    let scale = max(lower,min(upper,1/factor))
    let w = rect.width*scale, h = rect.height*scale
    set(CGRect(x:rect.midX-w/2,y:rect.midY-h/2,width:w,height:h))
  }
  public func picture(from original: PictureSettings? = nil) -> PictureSettings {
    var p = original ?? PictureSettings()
    p.left = left/sourceSize.width; p.right = right/sourceSize.width
    p.top = top/sourceSize.height; p.bottom = bottom/sourceSize.height
    return p
  }
  public static func fit(_ source: CGSize, in bounds: CGSize) -> CGRect {
    let scale = min(bounds.width/max(1,source.width),bounds.height/max(1,source.height))
    let w = source.width*scale, h = source.height*scale
    return CGRect(x:(bounds.width-w)/2,y:(bounds.height-h)/2,width:w,height:h)
  }
  public mutating func drag(from: CGPoint, to: CGPoint, imageRect: CGRect) {
    guard imageRect.width > 0, imageRect.height > 0 else { return }
    func point(_ p: CGPoint) -> CGPoint {
      CGPoint(x:max(0,min(1,(p.x-imageRect.minX)/imageRect.width))*sourceSize.width,
        y:max(0,min(1,(p.y-imageRect.minY)/imageRect.height))*sourceSize.height)
    }
    let a = point(from), b = point(to)
    set(CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)))
  }
}

/// Physical source bounds, keeping synchronization/rate/delay and export marks separate.
public struct SourceTrimDraft: Equatable, Sendable {
  public var start: Double
  public var end: Double
  public let duration: Double
  public let frameRate: Double
  public let synchronizationFloor: Double
  public let rate: Double
  public init(input: MediaInput, duration: Double, frameRate: Double) {
    self.duration = duration.isFinite ? max(0,duration) : 0
    self.frameRate = frameRate.isFinite && frameRate > 0 ? frameRate : 30
    synchronizationFloor = max(0,input.offset)
    rate = input.timing?.safeRate ?? 1
    start = min(self.duration,max(0,input.timing?.trimStart ?? 0)+synchronizationFloor)
    end = max(start,min(self.duration,input.timing?.trimEnd ?? self.duration))
  }
  public var minimumFrame: Double { 1/frameRate }
  public var effectiveLength: Double { max(0,end-start)/rate }
  public var endPreviewTime: Double { max(start,end-minimumFrame) }
  public func applying(to input: MediaInput) throws -> MediaInput {
    guard start.isFinite, end.isFinite, start >= synchronizationFloor, start >= 0,
      end <= duration, end-start >= min(minimumFrame,duration) - 1e-8, end > start else {
      throw RaceError.invalid("Choose source bounds with at least one frame, within the file and after its synchronization offset.")
    }
    var result = input, t = input.timing ?? InputTiming()
    t.trimStart = max(0,start-synchronizationFloor)
    t.trimEnd = end >= duration-1e-8 ? nil : end
    result.timing = t == InputTiming() && input.timing == nil ? nil : t
    result.duration = duration
    return result
  }
}
