import CoreGraphics
import CoreImage
import Foundation

/// Write enables, rather than a tint: disabled components retain the underlying layer.
public struct RGBWriteMask:Codable,Equatable,Sendable {
  public var red = true
  public var green = true
  public var blue = true
  public init() {}
  public init(bits:UInt8) {red = bits & 1 != 0;green = bits & 2 != 0;blue = bits & 4 != 0}
  public var bits:UInt8 {(red ? 1 : 0) | (green ? 2 : 0) | (blue ? 4 : 0)}
}

enum RGBChannelCompositor {
  /// The compositor and preview use 8-bit RGB bitmap canvases. Preserve disabled
  /// destination bytes around the normal alpha-blended draw, including soft edges.
  /// Ordinary RGB draws allocate nothing and retain their existing fast path.
  static func draw(_ context:CGContext,mask:RGBWriteMask?,body:() -> Void) {
    guard let mask,mask.bits != 7 else {body();return}
    guard mask.bits != 0 else {return}
    guard let base = context.data,context.bitsPerComponent == 8,context.bitsPerPixel == 32 else {return}
    let first = context.alphaInfo == .premultipliedFirst || context.alphaInfo == .first || context.alphaInfo == .noneSkipFirst
    var offsets = first ? [1,2,3] : [0,1,2]
    if context.bitmapInfo.contains(.byteOrder32Little) {offsets = offsets.map{3-$0}}
    var preserve:UInt32 = 0
    for (index,enabled) in [mask.red,mask.green,mask.blue].enumerated() where !enabled {preserve |= UInt32(255) << (offsets[index]*8)}
    context.flush()
    let bytes = context.bytesPerRow*context.height
    var previous = [UInt32](repeating:0,count:bytes/4)
    previous.withUnsafeMutableBytes { $0.copyMemory(from:UnsafeRawBufferPointer(start:base,count:bytes)) }
    body();context.flush()
    previous.withUnsafeBufferPointer {old in
      for y in 0..<context.height {
        let row = base.advanced(by:y*context.bytesPerRow).assumingMemoryBound(to:UInt32.self)
        let source = old.baseAddress!.advanced(by:y*context.bytesPerRow/4)
        for x in 0..<context.width {row[x] = (row[x] & ~preserve) | (source[x] & preserve)}
      }
    }
  }
  /// The first camera is composited directly over opaque black by Core Image.
  static func overBlack(_ image:CIImage,mask:RGBWriteMask?) -> CIImage {
    guard let mask,mask.bits != 7 else {return image}
    return image.applyingFilter("CIColorMatrix",parameters:[
      "inputRVector":CIVector(x:mask.red ? 1 : 0,y:0,z:0,w:0),
      "inputGVector":CIVector(x:0,y:mask.green ? 1 : 0,z:0,w:0),
      "inputBVector":CIVector(x:0,y:0,z:mask.blue ? 1 : 0,w:0)])
  }
}
