import Foundation

/// Independent reader of timestamped activity records in Garmin's public FIT protocol.
/// Unknown messages and developer fields are skipped using their declared lengths.
enum FITReader {
  struct Field { var number: Int; var size: Int; var type: Int }
  struct Definition { var message: Int; var bigEndian: Bool; var fields: [Field]; var developerBytes: Int }
  static func crc(_ bytes: Data) -> UInt16 {
    var value: UInt16 = 0
    for byte in bytes {
      value ^= UInt16(byte)
      for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) != 0 ? 0xa001 : 0) }
    }
    return value
  }
  static func csv(_ data: Data) throws -> String {
    var base = 0
    var rows: [[Int: Double]] = []
    var lapStarts: [Double] = []
    while base < data.count {
      guard base + 12 <= data.count else { throw RaceError.invalid("Truncated FIT header.") }
      let headerSize = Int(data[base]), length = Int(data.u32(base+4))
      let end = base + headerSize + length
      guard headerSize >= 12, base+headerSize <= data.count, end+2 <= data.count,
        String(data: data[base+8..<base+12], encoding: .ascii) == ".FIT" else { throw RaceError.invalid("Invalid FIT file size or signature.") }
      if headerSize >= 14, data[base+12] != 0 || data[base+13] != 0 {
        guard crc(Data(data[base..<base+headerSize])) == 0 else { throw RaceError.invalid("FIT header checksum mismatch.") }
      }
      guard crc(Data(data[base..<end+2])) == 0 else { throw RaceError.invalid("FIT checksum mismatch.") }
      var cursor = base+headerSize, definitions: [Int: Definition] = [:], previousTime: UInt32?
      func take(_ size: Int) throws -> Data {
        guard size >= 0, cursor+size <= end else { throw RaceError.invalid("Truncated FIT message.") }
        defer { cursor += size }
        return Data(data[cursor..<cursor+size])
      }
      while cursor < end {
        let header = Int(try take(1)[0])
        let compressed = header & 0x80 != 0
        let local = compressed ? (header >> 5) & 3 : header & 15
        if !compressed && header & 0x40 != 0 {
          let bytes = try take(5)
          guard bytes[1] <= 1 else { throw RaceError.invalid("Unsupported FIT byte order.") }
          let big = bytes[1] == 1
          let message = big ? Int(bytes[2])*256+Int(bytes[3]) : Int(bytes[3])*256+Int(bytes[2])
          var fields: [Field] = []
          for _ in 0..<Int(bytes[4]) {
            let f = try take(3); fields.append(Field(number: Int(f[0]), size: Int(f[1]), type: Int(f[2]) & 31))
          }
          var developer = 0
          if header & 0x20 != 0 {
            let count = Int(try take(1)[0])
            for _ in 0..<count { developer += Int(try take(3)[1]) }
          }
          definitions[local] = Definition(message: message, bigEndian: big, fields: fields, developerBytes: developer)
          continue
        }
        guard let def = definitions[local] else { throw RaceError.invalid("FIT data message has no definition.") }
        var values: [Int: Double] = [:]
        if compressed {
          guard let previous = previousTime else { throw RaceError.invalid("FIT compressed timestamp has no reference.") }
          let offset = UInt32(header & 31)
          let time = (previous & ~31) + offset + (offset < previous & 31 ? 32 : 0)
          values[253] = Double(time)
        }
        for f in def.fields {
          if compressed && f.number == 253 { continue }
          let bytes = try take(f.size)
          if let v = number(bytes, type: f.type, bigEndian: def.bigEndian) { values[f.number] = v }
        }
        _ = try take(def.developerBytes)
        if let t = values[253], t >= 0, t <= Double(UInt32.max) { previousTime = UInt32(t) }
        if def.message == 20, values[253] != nil { rows.append(values) }
        if def.message == 19, let start = values[2] { lapStarts.append(start) }
      }
      base = end+2
    }
    guard !rows.isEmpty else { throw RaceError.invalid("FIT file contains no timestamped activity records.") }
    let headings = ["Time", "Latitude", "Longitude", "Altitude", "Speed (m/s)", "Distance (m)", "Heart Rate", "Cadence", "Power", "Temperature", "Lap #"]
    let starts = Array(Set(lapStarts)).sorted()
    let lines = rows.map { row -> String in
      let time = row[253]!
      let lat = row[0].map { $0*180/2147483648 }, lon = row[1].map { $0*180/2147483648 }
      let altitude = (row[78] ?? row[2]).map { $0/5-500 }
      let speed = (row[73] ?? row[6]).map { $0/1000 }
      let distance = row[5].map { $0/100 }
      let lap = starts.isEmpty ? nil : Double(starts.prefix { $0 <= time }.count)
      let fields: [Double?] = [time, lat, lon, altitude, speed, distance, row[3], row[4], row[7], row[13], lap]
      return fields.map { $0.map { String($0) } ?? "" }.joined(separator: ",")
    }
    return ([headings.joined(separator: ",")]+lines).joined(separator: "\n")
  }
  static func number(_ bytes: Data, type: Int, bigEndian: Bool) -> Double? {
    let sizes = [1,1,1,2,2,4,4,1,4,8,1,2,4,1,8,8,8]
    guard sizes.indices.contains(type), type != 7, bytes.count == sizes[type] else { return nil }
    let sequence = bigEndian ? Array(bytes) : Array(bytes.reversed())
    let bits = sequence.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    let width = bytes.count*8
    let signed = [1,3,5,14].contains(type)
    let maximum = width == 64 ? UInt64.max : (UInt64(1) << width)-1
    let invalid = signed ? maximum >> 1 : ([10,11,12,16].contains(type) ? 0 : maximum)
    guard bits != invalid else { return nil }
    if type == 8 { let value = Double(Float(bitPattern: UInt32(bits))); return value.isFinite ? value : nil }
    if type == 9 { let value = Double(bitPattern: bits); return value.isFinite ? value : nil }
    if signed {
      let shifted = Int64(bitPattern: bits << (64-width)) >> (64-width)
      return Double(shifted)
    }
    return Double(bits)
  }
}
