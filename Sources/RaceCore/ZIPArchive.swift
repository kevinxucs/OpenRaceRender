import Compression
import Foundation

/// Bounded, in-memory ZIP access for telemetry containers. No files are extracted.
struct ZIPArchive {
  struct Entry {
    let name: String
    let method: Int
    let crc: UInt32
    let compressedSize: Int
    let size: Int
    let offset: Int
  }
  let data: Data
  let entries: [String: Entry]
  private let directoryOffset: Int
  static let maximumEntrySize = 64 * 1024 * 1024
  static let maximumExpandedSize = 256 * 1024 * 1024

  init(_ data: Data) throws {
    guard data.count >= 22 else { throw RaceError.invalid("Truncated RCZ ZIP archive.") }
    let first = max(0, data.count - 65_557)
    guard let end = stride(from: data.count - 22, through: first, by: -1).first(where: {
      data.u32($0) == 0x06054b50 && $0 + 22 + Self.word(data, $0 + 20) == data.count
    }) else { throw RaceError.invalid("RCZ is not a complete ZIP archive.") }
    let count = Self.word(data, end + 10)
    let directorySize = Int(data.u32(end + 12)), directory = Int(data.u32(end + 16))
    guard Self.word(data, end + 4) == 0, Self.word(data, end + 6) == 0,
      Self.word(data, end + 8) == count, count < 65_535,
      directorySize != Int(UInt32.max), directory != Int(UInt32.max) else {
      throw RaceError.invalid("Multi-volume and ZIP64 RCZ archives are not supported.")
    }
    guard count <= 4096, directory <= end, directorySize <= end - directory else {
      throw RaceError.invalid("Invalid or oversized RCZ ZIP directory.")
    }
    var cursor = directory, result: [String: Entry] = [:], expanded = 0
    for _ in 0..<count {
      guard cursor + 46 <= directory + directorySize, data.u32(cursor) == 0x02014b50 else {
        throw RaceError.invalid("Invalid RCZ ZIP entry.")
      }
      let flags = Self.word(data, cursor + 8), method = Self.word(data, cursor + 10)
      let compressed = Int(data.u32(cursor + 20)), size = Int(data.u32(cursor + 24))
      let nameLength = Self.word(data, cursor + 28)
      let next = cursor + 46 + nameLength + Self.word(data, cursor + 30) + Self.word(data, cursor + 32)
      guard flags & 1 == 0 else { throw RaceError.invalid("Encrypted RCZ archives are not supported.") }
      guard Self.word(data, cursor + 34) == 0, nameLength > 0, nameLength <= 4096,
        next <= directory + directorySize, size <= Self.maximumEntrySize,
        compressed <= data.count, expanded <= Self.maximumExpandedSize - size else {
        throw RaceError.invalid("Invalid or oversized RCZ ZIP member.")
      }
      let nameBytes = Data(data[cursor + 46..<cursor + 46 + nameLength])
      guard let rawName = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) else {
        throw RaceError.invalid("Unreadable RCZ ZIP member name.")
      }
      let name = rawName.replacingOccurrences(of: "\\", with: "/")
      guard !name.hasPrefix("/"), !name.contains("\0"),
        !name.split(separator: "/").contains(".."), result[name] == nil else {
        throw RaceError.invalid("Unsafe or duplicate RCZ ZIP member name.")
      }
      let offset = Int(data.u32(cursor + 42))
      guard offset < directory else { throw RaceError.invalid("Invalid RCZ ZIP member location.") }
      result[name] = Entry(name: name, method: method, crc: data.u32(cursor + 16),
        compressedSize: compressed, size: size, offset: offset)
      expanded += size; cursor = next
    }
    guard cursor == directory + directorySize else { throw RaceError.invalid("Invalid RCZ ZIP directory length.") }
    self.data = data; entries = result; directoryOffset = directory
  }
  func read(_ name: String) throws -> Data {
    guard let entry = entries[name] else { throw RaceError.invalid("Missing RCZ member: \(name).") }
    let at = entry.offset
    guard at + 30 <= data.count, data.u32(at) == 0x04034b50,
      Self.word(data, at + 6) & 1 == 0, Self.word(data, at + 8) == entry.method else {
      throw RaceError.invalid("Invalid RCZ ZIP member header.")
    }
    let nameLength = Self.word(data, at + 26)
    let start = at + 30 + nameLength + Self.word(data, at + 28)
    guard start <= directoryOffset, entry.compressedSize <= directoryOffset - start else {
      throw RaceError.invalid("Truncated RCZ ZIP member.")
    }
    let nameBytes = Data(data[at + 30..<at + 30 + nameLength])
    let localName = (String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1))?.replacingOccurrences(of: "\\", with: "/")
    guard localName == entry.name else { throw RaceError.invalid("RCZ ZIP member names disagree.") }
    if Self.word(data, at + 6) & 8 == 0 {
      guard data.u32(at + 14) == entry.crc, Int(data.u32(at + 18)) == entry.compressedSize,
        Int(data.u32(at + 22)) == entry.size else { throw RaceError.invalid("RCZ ZIP member headers disagree.") }
    }
    let payload = Data(data[start..<start + entry.compressedSize])
    let result: Data
    switch entry.method {
    case 0: result = payload
    case 8: result = try Self.inflate(payload, size: entry.size)
    default: throw RaceError.invalid("Unsupported RCZ ZIP compression method \(entry.method).")
    }
    guard result.count == entry.size, Self.checksum(result) == entry.crc else {
      throw RaceError.invalid("RCZ ZIP member size or checksum mismatch.")
    }
    return result
  }
  private static func word(_ data: Data, _ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
  private static func inflate(_ bytes: Data, size: Int) throws -> Data {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
    defer { buffer.deallocate() }
    var stream = compression_stream(dst_ptr: buffer, dst_size: 0, src_ptr: UnsafePointer(buffer), src_size: 0, state: nil)
    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
      throw RaceError.invalid("Could not initialize RCZ decompression.")
    }
    defer { compression_stream_destroy(&stream) }
    return try bytes.withUnsafeBytes { raw in
      guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { throw RaceError.invalid("Empty RCZ compressed member.") }
      stream.src_ptr = source; stream.src_size = bytes.count
      var output = Data(); output.reserveCapacity(size)
      while true {
        stream.dst_ptr = buffer; stream.dst_size = 65_536
        let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
        let count = 65_536 - stream.dst_size
        guard status != COMPRESSION_STATUS_ERROR, count <= size - output.count else {
          throw RaceError.invalid("Invalid or oversized RCZ compressed member.")
        }
        output.append(buffer, count: count)
        if status == COMPRESSION_STATUS_END {
          guard stream.src_size == 0 else { throw RaceError.invalid("Trailing bytes in RCZ compressed member.") }
          return output
        }
        guard count > 0 else { throw RaceError.invalid("Truncated RCZ compressed member.") }
      }
    }
  }
  private static let crcTable: [UInt32] = (0..<256).map { n in
    var value = UInt32(n)
    for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 0 ? 0 : 0xedb88320) }
    return value
  }
  static func checksum(_ bytes: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
    return crc ^ UInt32.max
  }
}
