import AppKit
import Compression

/// Decode artwork supplied by a user's local legacy library; no vendor assets are bundled.
enum LegacyArtwork {
  static func png(_ container: Data) -> Data? {
    guard container.count >= 8 else { return nil }
    var raw = container
    if container.count >= 12, Int(container.u32(0)) == container.count-4, container.u32(4) & 0xffff == 8 {
      raw = Data(container.dropFirst(4))
    }
    if container.u32(0) & 0x8000_0000 != 0 {
      let count = Int(container.u32(0) & 0x7fff_ffff)
      guard count > 0, count <= 32*1024*1024, count+4 <= container.count,
        let decoded = inflate(Data(container[4..<4+count])) else { return nil }
      raw = decoded
    }
    guard raw.count >= 8 else { return nil }
    let type = Int(raw[0]) | Int(raw[1]) << 8
    let width = Int(raw[2]) | Int(raw[3]) << 8
    let height = Int(raw[4]) | Int(raw[5]) << 8
    guard type == 8, width > 0, height > 0, width <= 4096, height <= 4096,
      raw.count >= 8+width*height*4 else { return nil }
    // Native bitmaps store the bottom scanline first; CGImage/PNG expects top first.
    let pixels = reversedRows(Data(raw[8..<8+width*height*4]),width:width,height:height)
    guard let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width*4, space: OverlayRenderer.colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
  static func reversedRows(_ pixels:Data,width:Int,height:Int) -> Data {
    let stride = width*4
    var result = Data(capacity:pixels.count)
    for row in (0..<height).reversed() { result.append(pixels[row*stride..<(row+1)*stride]) }
    return result
  }
  static func inflate(_ data: Data) -> Data? {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
    defer { buffer.deallocate() }
    var stream = compression_stream(dst_ptr:buffer,dst_size:0,src_ptr:UnsafePointer(buffer),src_size:0,state:nil)
    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else { return nil }
    defer { compression_stream_destroy(&stream) }
    return data.withUnsafeBytes { source -> Data? in
      guard let src = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
      stream.src_ptr = src; stream.src_size = data.count
      var result = Data()
      var status = COMPRESSION_STATUS_OK
      while status == COMPRESSION_STATUS_OK {
        stream.dst_ptr = buffer; stream.dst_size = 65536
        status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
        let count = 65536-stream.dst_size
        guard result.count+count <= 64*1024*1024, status != COMPRESSION_STATUS_ERROR else { return nil }
        result.append(buffer, count: count)
        if count == 0 && status != COMPRESSION_STATUS_END { return nil }
      }
      return status == COMPRESSION_STATUS_END ? result : nil
    }
  }
}
