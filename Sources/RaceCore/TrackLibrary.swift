import Foundation

extension FinishLine {
  public func validate() throws {
    guard latitude.isFinite,abs(latitude) <= 90,longitude.isFinite,abs(longitude) <= 180,
      heading.isFinite,width.isFinite,width > 0,minimumLap.isFinite,minimumLap > 0,
      headingTolerance.map({$0.isFinite && (0...180).contains($0)}) ?? true,
      eastTolerance.map({$0.isFinite && $0 > 0}) ?? true,
      northTolerance.map({$0.isFinite && $0 > 0}) ?? true else {
      throw RaceError.invalid("Use valid GPS coordinates, positive gate/tolerance sizes and minimum lap time, and heading tolerance from 0° to 180°.")
    }
  }
  static func longitudeDelta(_ degrees:Double) -> Double { (degrees+540).truncatingRemainder(dividingBy:360)-180 }
  public func localPosition(latitude:Double,longitude:Double) -> (Double,Double) {
    (Self.longitudeDelta(longitude-self.longitude)*111195*cos(self.latitude * .pi/180),(latitude-self.latitude)*111195)
  }
  public func point(east:Double,north:Double) -> (latitude:Double,longitude:Double) {
    (latitude+north/111195,Self.longitudeDelta(longitude+east/(111195*max(1e-8,cos(latitude * .pi/180)))))
  }
}

public struct SavedTrack:Identifiable,Codable,Equatable,Sendable {
  public var id = UUID()
  public var name:String
  public var finishLine:FinishLine
  public init(name:String,finishLine:FinishLine) { self.name = name; self.finishLine = finishLine }
}

/// Portable original/user-defined finish lines; no vendor catalogue or media.
public struct TrackLibrary:Codable,Equatable,Sendable {
  public var formatVersion:Int = 1
  public var tracks:[SavedTrack] = []
  public init() {}
  public static func userURL(homeDirectory:URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    homeDirectory.appendingPathComponent("Library/Application Support/OpenRaceRender/Tracks.json")
  }
  public func validate() throws {
    guard formatVersion == 1,tracks.count <= 1000,Set(tracks.map(\.id)).count == tracks.count else {
      throw RaceError.invalid("Unsupported track-library version, duplicate track IDs, or more than 1000 tracks.")
    }
    for track in tracks {
      guard !track.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,track.name.utf8.count <= 1024 else { throw RaceError.invalid("Give each saved track a name (up to 1024 bytes).") }
      try track.finishLine.validate()
    }
  }
  public static func read(_ url:URL) throws -> Self {
    let bytes = try Data(contentsOf:url)
    guard bytes.count <= 1_048_576 else { throw RaceError.invalid("Track libraries must be smaller than 1 MB.") }
    let value = try JSONDecoder().decode(Self.self,from:bytes); try value.validate(); return value
  }
  public func save(_ url:URL) throws {
    try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    try encoder.encode(self).write(to:url,options:.atomic)
  }
  public func nearby(latitude:Double,longitude:Double,radius:Double = 50_000) -> [(track:SavedTrack,distance:Double)] {
    guard latitude.isFinite,abs(latitude) <= 90,longitude.isFinite,abs(longitude) <= 180,radius.isFinite,radius >= 0 else { return [] }
    return tracks.map { track in
      (track:track,distance:Telemetry.distance(lat1:latitude,lon1:longitude,lat2:track.finishLine.latitude,lon2:track.finishLine.longitude))
    }.filter{$0.distance <= radius}.sorted{a,b in a.distance == b.distance ? a.track.name < b.track.name : a.distance < b.distance}
  }
  /// Imported collisions preserve existing entries. Identical entries are skipped.
  public func merging(_ other:Self) throws -> Self {
    try validate(); try other.validate(); var result = self
    for var track in other.tracks {
      if result.tracks.contains(where:{$0.name == track.name && $0.finishLine == track.finishLine}) { continue }
      if result.tracks.contains(where:{$0.id == track.id}) { track.id = UUID() }
      result.tracks.append(track)
    }
    try result.validate(); return result
  }
}

public struct GPSTrackSample:Identifiable,Sendable {
  public var id:Double { time }
  public var time:Double
  public var latitude:Double
  public var longitude:Double
  public init(time:Double,latitude:Double,longitude:Double) { self.time = time; self.latitude = latitude; self.longitude = longitude }
}
extension Telemetry {
  public func gpsTrackSamples(maximum:Int = 4000) -> [GPSTrackSample] {
    guard aliases["lat"] != nil,aliases["lon"] != nil,maximum > 1 else { return [] }
    let step = max(1,Int(ceil(Double(count)/Double(maximum))))
    return stride(from:0,to:count,by:step).compactMap { i in
      guard let lat = value("lat",at:times[i]),abs(lat) <= 90,let lon = value("lon",at:times[i]),abs(lon) <= 180 else { return nil }
      return GPSTrackSample(time:times[i],latitude:lat,longitude:lon)
    }
  }
}
