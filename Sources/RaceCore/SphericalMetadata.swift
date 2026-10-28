import Foundation

/// Independent Google Spherical Video V1 marker tool; media samples and chunk offsets are retained.
public enum SphericalMetadata {
  public struct Info:Sendable {
    public var hasV1:Bool;public var hasV2:Bool;public var stereo:Bool;public var width:Int;public var height:Int
    public var marked:Bool {hasV1 || hasV2}
  }
  private struct Atom {
    var type:String;var start:Int;var end:Int;var header:Int
    var payload:Int {start+header}
  }
  private struct Movie {var data:Data;var offset:UInt64;var length:UInt64;var zeroHeaders:[(UInt64,UInt64)]}
  private static let uuid = Data([0xff,0xcc,0x82,0x63,0xf8,0x55,0x4a,0x93,0x88,0x14,0x58,0x7a,0x02,0x52,0x1f,0xdd])
  private static func invalid(_ message:String) -> RaceError {.invalid("360 metadata: "+message)}
  private static func atoms(_ data:Data,_ range:Range<Int>) throws -> [Atom] {
    var p = range.lowerBound,result:[Atom] = []
    while p < range.upperBound {
      guard range.upperBound-p >= 8 else {throw invalid("truncated atom.")}
      let raw = try CameraMP4.uint(data,p),header = raw == 1 ? 16 : 8
      let count = raw == 0 ? UInt64(range.upperBound-p) : (raw == 1 ? try CameraMP4.uint(data,p+8,8) : raw)
      guard count >= header,count <= UInt64(range.upperBound-p) else {throw invalid("invalid atom size.")}
      result.append(Atom(type:String(decoding:data[p+4..<p+8],as:UTF8.self),start:p,end:p+Int(count),header:header));p += Int(count)
      guard result.count <= 1_000_000 else {throw invalid("too many atoms.")}
    }
    return result
  }
  private static func child(_ name:String,_ data:Data,_ parent:Atom) throws -> Atom {
    guard let found = try atoms(data,parent.payload..<parent.end).first(where:{$0.type == name}) else {throw invalid("missing \(name) box.")};return found
  }
  private static func word(_ value:UInt64,_ bytes:Int = 4) -> Data {Data((0..<bytes).reversed().map{UInt8(truncatingIfNeeded:value >> ($0*8))})}
  private static func box(_ type:String,_ contents:Data) throws -> Data {
    guard contents.count <= 64*1024*1024 else {throw invalid("movie index exceeds 64 MiB.")}
    return word(UInt64(contents.count+8))+Data(type.utf8)+contents
  }
  private static func read(_ url:URL) throws -> Movie {
    let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
    let length = try file.seekToEnd();var p:UInt64 = 0,movie:Movie?,zero:[(UInt64,UInt64)] = [];var count = 0
    while p < length {
      try Task.checkCancellation()
      guard length-p >= 8 else {throw invalid("truncated file.")}
      try file.seek(toOffset:p);let header = try file.read(upToCount:16) ?? Data()
      let raw = try CameraMP4.uint(header,0),size = raw == 0 ? length-p : (raw == 1 ? try CameraMP4.uint(header,8,8) : raw)
      let head:UInt64 = raw == 1 ? 16 : 8,type = String(decoding:header[4..<8],as:UTF8.self)
      guard size >= head,size <= length-p else {throw invalid("invalid top-level size.")}
      if type == "moof" {throw invalid("fragmented MP4 is unsupported.")}
      if raw == 0 {zero.append((p,size))}
      if type == "moov" {
        guard movie == nil,size <= 64*1024*1024 else {throw invalid("oversized or duplicate movie index.")}
        try file.seek(toOffset:p);let data = try file.read(upToCount:Int(size)) ?? Data()
        guard data.count == size else {throw invalid("truncated movie index.")}
        movie = Movie(data:data,offset:p,length:length,zeroHeaders:[])
      }
      p += size;count += 1;guard count <= 1_000_000 else {throw invalid("too many top-level boxes.")}
    }
    guard var result = movie else {throw invalid("no movie index.")};result.zeroHeaders = zero;return result
  }
  private static func edit(_ movie:Movie,enabled:Bool?) throws -> (Data,Info) {
    let data = movie.data,root = try atoms(data,0..<data.count)[0]
    let children = try atoms(data,root.payload..<root.end)
    guard !children.contains(where:{$0.type == "mvex"}) else {throw invalid("fragmented movie indexes are unsupported.")}
    var videoCount = 0,info = Info(hasV1:false,hasV2:false,stereo:false,width:0,height:0),output = Data()
    let supported:Set<String> = ["avc1","avc3","hvc1","hev1","mp4v","vp09","av01","jpeg","png ","apch","apcn","apcs","apco","ap4h","ap4x"]
    for track in children {
      guard track.type == "trak" else {output += data[track.start..<track.end];continue}
      let media = try child("mdia",data,track),handler = try child("hdlr",data,media)
      guard handler.end-handler.payload >= 12 else {throw invalid("truncated track handler.")}
      guard String(decoding:data[handler.payload+8..<handler.payload+12],as:UTF8.self) == "vide" else {output += data[track.start..<track.end];continue}
      videoCount += 1
      let tkhd = try child("tkhd",data,track)
      guard tkhd.end-tkhd.payload >= 8 else {throw invalid("truncated video dimensions.")}
      info.width = Int(try CameraMP4.uint(data,tkhd.end-8)) >> 16;info.height = Int(try CameraMP4.uint(data,tkhd.end-4)) >> 16
      var trackData = Data()
      for member in try atoms(data,track.payload..<track.end) {
        if member.type == "uuid",member.end-member.payload >= 16,Data(data[member.payload..<member.payload+16]) == uuid {
          info.hasV1 = true
          if enabled == nil {trackData += data[member.start..<member.end]}
          continue
        }
        guard member.type == "mdia" else {trackData += data[member.start..<member.end];continue}
        var mediaData = Data()
        for section in try atoms(data,member.payload..<member.end) {
          guard section.type == "minf" else {mediaData += data[section.start..<section.end];continue}
          var infoData = Data()
          for table in try atoms(data,section.payload..<section.end) {
            guard table.type == "stbl" else {infoData += data[table.start..<table.end];continue}
            var tableData = Data()
            for entry in try atoms(data,table.payload..<table.end) {
              guard entry.type == "stsd" else {tableData += data[entry.start..<entry.end];continue}
              guard entry.end-entry.payload >= 8 else {throw invalid("truncated sample description.")}
              var descriptions = Data(data[entry.payload..<entry.payload+8])
              for description in try atoms(data,entry.payload+8..<entry.end) {
                guard supported.contains(description.type),description.end-description.payload >= 78 else {throw invalid("unsupported video sample entry \(description.type).")}
                var contents = Data(data[description.payload..<description.payload+78])
                for property in try atoms(data,description.payload+78..<description.end) {
                  if property.type == "sv3d" {info.hasV2 = true;if enabled != nil {continue}}
                  if property.type == "st3d",property.end-property.payload >= 5,data[property.payload+4] != 0 {info.stereo = true}
                  contents += data[property.start..<property.end]
                }
                descriptions += try box(description.type,contents)
              }
              tableData += try box("stsd",descriptions)
            }
            infoData += try box("stbl",tableData)
          }
          mediaData += try box("minf",infoData)
        }
        trackData += try box("mdia",mediaData)
      }
      if enabled == true {
        let xml = "<rdf:SphericalVideo xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" xmlns:GSpherical=\"http://ns.google.com/videos/1.0/spherical/\"><GSpherical:Spherical>true</GSpherical:Spherical><GSpherical:Stitched>true</GSpherical:Stitched><GSpherical:StitchingSoftware>OpenRaceRender</GSpherical:StitchingSoftware><GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType></rdf:SphericalVideo>"
        trackData += try box("uuid",uuid+Data(xml.utf8))
      }
      output += try box("trak",trackData)
    }
    guard videoCount == 1 else {throw invalid("exactly one video track is required.")}
    if enabled == true {
      guard !info.stereo else {throw invalid("stereoscopic footage requires a separate stereo workflow.")}
      guard info.width > 0,info.height > 0,info.width == info.height*2 else {throw invalid("marking 360 video requires a 2:1 equirectangular frame.")}
    }
    return (try box("moov",output),info)
  }
  public static func inspect(_ url:URL) throws -> Info {try edit(read(url),enabled:nil).1}
  public static func copy(_ source:URL,to destination:URL,enabled:Bool) throws {
    guard source.standardizedFileURL != destination.standardizedFileURL,!FileManager.default.fileExists(atPath:destination.path) else {throw invalid("choose a new output file; the original is never overwritten.")}
    let movie = try read(source);_ = try edit(movie,enabled:enabled)
    try FileManager.default.copyItem(at:source,to:destination)
    do {
      // copyItem preserves read-only source permissions. Only the new copy
      // needs to be writable; the original is never changed.
      let attributes = try FileManager.default.attributesOfItem(atPath:destination.path)
      if let mode = attributes[.posixPermissions] as? NSNumber {
        try FileManager.default.setAttributes([.posixPermissions:mode.intValue | 0o200],ofItemAtPath:destination.path)
      }
      try updateOwnedOutput(destination,enabled:enabled)
    } catch {try? FileManager.default.removeItem(at:destination);throw error}
  }
  /// Only for a newly created output owned by the caller. A failed write restores its original index/length.
  static func updateOwnedOutput(_ url:URL,enabled:Bool) throws {
    let movie = try read(url),modified = try edit(movie,enabled:enabled).0
    for (_,length) in movie.zeroHeaders where length > UInt32.max {throw invalid("a >4 GiB zero-sized box cannot be relocated safely.")}
    try Task.checkCancellation()
    let file = try FileHandle(forUpdating:url);defer {try? file.close()}
    do {
      try file.seek(toOffset:movie.length);try file.write(contentsOf:modified);try file.synchronize()
      for (offset,length) in movie.zeroHeaders {try file.seek(toOffset:offset);try file.write(contentsOf:word(length))}
      try file.seek(toOffset:movie.offset+4);try file.write(contentsOf:Data("free".utf8));try file.synchronize()
    } catch {
      try? file.seek(toOffset:movie.offset);try? file.write(contentsOf:movie.data)
      for (offset,_) in movie.zeroHeaders where offset != movie.offset {try? file.seek(toOffset:offset);try? file.write(contentsOf:Data(repeating:0,count:4))}
      try? file.truncate(atOffset:movie.length);throw error
    }
  }
}
