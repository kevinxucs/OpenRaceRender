import Foundation

/// Reads only the movie index and metadata packets; video/audio payloads are skipped.
enum CameraMP4 {
  struct Packet { var offset:UInt64; var size:Int; var time:Double; var duration:Double }
  struct Index { var packets:[Packet]; var duration:Double;var activeRange:ClosedRange<Double>? }
  struct Box { var type:String; var start:Int; var end:Int }
  static func invalid(_ message:String) -> RaceError { .invalid("Camera telemetry: " + message) }
  static func uint(_ d:Data,_ p:Int,_ n:Int = 4) throws -> UInt64 {
    guard p >= 0,n > 0,n <= 8,p <= d.count-n else {throw invalid("truncated movie index.")}
    return d[p..<p+n].reduce(UInt64(0)) {($0 << 8) | UInt64($1)}
  }
  static func boxes(_ d:Data,_ range:Range<Int>) throws -> [Box] {
    var p = range.lowerBound;var result:[Box] = []
    while p < range.upperBound {
      guard range.upperBound-p >= 8 else {throw invalid("truncated atom.")}
      let size = try uint(d,p),type = String(decoding:d[p+4..<p+8],as:UTF8.self)
      let header = size == 1 ? 16 : 8
      let length = size == 0 ? UInt64(range.upperBound-p) : (size == 1 ? try uint(d,p+8,8) : size)
      guard length >= UInt64(header),length <= UInt64(range.upperBound-p) else {throw invalid("invalid atom size.")}
      result.append(Box(type:type,start:p+header,end:p+Int(length)));p += Int(length)
      guard result.count <= 1_000_000 else {throw invalid("too many atoms.")}
    }
    return result
  }
  static func child(_ type:String,_ d:Data,_ b:Box) throws -> Box {
    guard let found = try boxes(d,b.start..<b.end).first(where:{$0.type == type}) else {throw invalid("missing \(type) sample table.")};return found
  }
  static func table(_ type:String,_ d:Data,_ parent:Box,_ stride:Int) throws -> (Box,Int) {
    let box = try child(type,d,parent);let count = Int(try uint(d,box.start+4))
    guard count <= 2_000_000,box.end-box.start >= 8,count <= (box.end-box.start-8)/stride else {throw invalid("invalid \(type) table.")}
    return (box,count)
  }
  static func clock(_ d:Data,_ box:Box) throws -> (Double,Double) {
    let version = try uint(d,box.start,1)
    guard version <= 1 else {throw invalid("unsupported movie clock version.")}
    let p = box.start + (version == 1 ? 20 : 12)
    let scale = Double(try uint(d,p)),duration = Double(try uint(d,p+4,version == 1 ? 8 : 4))
    guard scale > 0,duration/scale <= 1_000_000 else {throw invalid("zero movie timescale.")};return (scale,duration/scale)
  }
  static func read(_ url:URL) throws -> Index? {
    let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
    let length = try file.seekToEnd();var offset:UInt64 = 0;var movie:Data?
    while offset < length {
      guard length-offset >= 8 else {throw invalid("truncated file.")}
      try file.seek(toOffset:offset);let h = try file.read(upToCount:16) ?? Data()
      let raw = try uint(h,0),header:UInt64 = raw == 1 ? 16 : 8
      let size = raw == 0 ? length-offset : (raw == 1 ? try uint(h,8,8) : raw)
      guard size >= header,size <= length-offset else {throw invalid("invalid top-level atom.")}
      if String(decoding:h[4..<8],as:UTF8.self) == "moov" {
        guard movie == nil,size-header <= 64*1024*1024 else {throw invalid("oversized or duplicate movie index.")}
        try file.seek(toOffset:offset+header);movie = try file.read(upToCount:Int(size-header))
        guard movie?.count == Int(size-header) else {throw invalid("truncated movie index.")}
      }
      offset += size
    }
    guard let d = movie else {throw invalid("no movie index (fragmented files are not supported).")}
    let root = Box(type:"moov",start:0,end:d.count)
    let (movieScale,movieDuration) = try clock(d,child("mvhd",d,root))
    var candidates:[Index] = []
    for track in try boxes(d,0..<d.count).filter({$0.type == "trak"}) {
      let media = try child("mdia",d,track),info = try child("minf",d,media),sampleTable = try child("stbl",d,info)
      let description = try child("stsd",d,sampleTable)
      guard description.end-description.start >= 8 else {throw invalid("truncated sample description.")}
      let descriptions = try boxes(d,description.start+8..<description.end)
      guard descriptions.first?.type == "gpmd" else {continue}
      guard descriptions.count == 1 else {throw invalid("multiple camera sample descriptions are not supported.")}
      let (scale,_) = try clock(d,child("mdhd",d,media))
      var editOffset = 0.0;var activeRange:ClosedRange<Double>?
      if let edits = try boxes(d,track.start..<track.end).first(where:{$0.type == "edts"}) {
        let list = try child("elst",d,edits),version = try uint(d,list.start,1)
        guard version <= 1 else {throw invalid("unsupported edit version.")}
        let wide = version == 1,step = wide ? 20 : 12,count = Int(try uint(d,list.start+4));var active = false
        guard count > 0,count <= 32,list.end-list.start >= 8+step*count else {throw invalid("invalid edit list.")}
        for i in 0..<count {
          let p = list.start+8+i*step,n = wide ? 8 : 4
          let duration = try uint(d,p,n),raw = try uint(d,p+n,n)
          let mediaTime = wide ? Int64(bitPattern:raw) : Int64(Int32(bitPattern:UInt32(raw)))
          guard try uint(d,p+n*2,2) == 1,try uint(d,p+n*2+2,2) == 0 else {throw invalid("rate-edited telemetry is unsupported.")}
          if mediaTime == -1,!active {editOffset += Double(duration)/movieScale}
          else if mediaTime >= 0,!active {
            let end = editOffset+Double(duration)/movieScale
            guard end.isFinite,end <= 1_000_000 else {throw invalid("camera edit duration exceeds limits.")}
            activeRange = editOffset...end
            editOffset -= Double(mediaTime)/scale;active = true
          }
          else {throw invalid("complex camera edit list is unsupported.")}
        }
      }
      let sizesBox = try child("stsz",d,sampleTable),constant = Int(try uint(d,sizesBox.start+4)),count = Int(try uint(d,sizesBox.start+8))
      guard count > 0,count <= 2_000_000,constant > 0 || sizesBox.end-sizesBox.start >= 12+count*4 else {throw invalid("invalid metadata sample sizes.")}
      var sizes:[Int] = [];sizes.reserveCapacity(count);var total = 0
      for i in 0..<count {
        let size = constant > 0 ? constant : Int(try uint(d,sizesBox.start+12+i*4))
        guard size > 0,size <= 16*1024*1024,total <= 256*1024*1024-size else {throw invalid("metadata exceeds extraction limits.")}
        sizes.append(size);total += size
      }
      let (timesBox,timeCount) = try table("stts",d,sampleTable,8)
      var times:[(Double,Double)] = [];var ticks:UInt64 = 0
      for i in 0..<timeCount {
        let p = timesBox.start+8+i*8,n = Int(try uint(d,p)),delta = try uint(d,p+4)
        guard n <= count-times.count,delta > 0 else {throw invalid("invalid metadata timestamps.")}
        for _ in 0..<n {times.append((Double(ticks)/scale+editOffset,Double(delta)/scale));ticks += delta}
      }
      guard times.count == count else {throw invalid("incomplete metadata clock.")}
      if let composition = try boxes(d,sampleTable.start..<sampleTable.end).first(where:{$0.type == "ctts"}) {
        let version = try uint(d,composition.start,1),entries = Int(try uint(d,composition.start+4));var k = 0
        guard version <= 1,entries <= count,composition.end-composition.start >= 8+entries*8 else {throw invalid("invalid composition clock.")}
        for i in 0..<entries {
          let p = composition.start+8+i*8,n = Int(try uint(d,p)),raw = try uint(d,p+4)
          guard n <= count-k else {throw invalid("composition clock overflow.")}
          let shift = version == 1 ? Double(Int32(bitPattern:UInt32(raw))) : Double(raw)
          for _ in 0..<n {times[k].0 += shift/scale;k += 1}
        }
        guard k == count else {throw invalid("incomplete composition clock.")}
      }
      let children = try boxes(d,sampleTable.start..<sampleTable.end),wide = children.contains(where:{$0.type == "co64"})
      let (chunkBox,chunks) = try table(wide ? "co64" : "stco",d,sampleTable,wide ? 8 : 4)
      let (mapBox,maps) = try table("stsc",d,sampleTable,12)
      var mappings:[(Int,Int)] = []
      for i in 0..<maps {
        let p = mapBox.start+8+i*12,first = Int(try uint(d,p)),n = Int(try uint(d,p+4)),desc = try uint(d,p+8)
        guard first > (mappings.last?.0 ?? 0),first <= chunks,n > 0,n <= count,desc == 1 else {throw invalid("invalid chunk mapping.")}
        mappings.append((first,n))
      }
      guard mappings.first?.0 == 1 else {throw invalid("missing first metadata chunk.")}
      var packets:[Packet] = [];var mapping = 0;var k = 0
      for i in 0..<chunks {
        while mapping+1 < mappings.count,mappings[mapping+1].0 <= i+1 {mapping += 1}
        var p = try uint(d,chunkBox.start+8+i*(wide ? 8 : 4),wide ? 8 : 4)
        for _ in 0..<mappings[mapping].1 {
          guard k < count,p <= length,UInt64(sizes[k]) <= length-p else {throw invalid("metadata packet outside file.")}
          packets.append(Packet(offset:p,size:sizes[k],time:times[k].0,duration:times[k].1));p += UInt64(sizes[k]);k += 1
        }
      }
      guard k == count else {throw invalid("incomplete metadata chunks.")}
      candidates.append(Index(packets:packets,duration:movieDuration,activeRange:activeRange))
    }
    guard candidates.count <= 1 else {throw invalid("multiple camera metadata tracks are unsupported.")};return candidates.first
  }
}
