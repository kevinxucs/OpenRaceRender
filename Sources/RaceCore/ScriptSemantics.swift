import Foundation

enum ScriptTimeFormat {
  /// Compact chooses the minimum unit; larger nonzero units remain visible.
  static func string(_ seconds:Double,decimals:Int,compact:Int) -> String {
    guard seconds.isFinite,abs(seconds) <= 1e10 else {return "—"}
    let places = max(0,min(8,decimals)),mode = max(0,min(2,compact))
    let scale = Int64(pow(10,Double(places)))
    let ticks = Int64((abs(seconds)*Double(scale)).rounded())
    let whole = ticks/scale,hours = whole/3600,minutes = (whole/60)%60,remaining = whole%60
    let value:String
    if mode == 0 || hours > 0 {value = String(format:"%02lld:%02lld:%02lld",hours,minutes,remaining)}
    else if mode == 1 || whole >= 60 {value = String(format:"%02lld:%02lld",whole/60,remaining)}
    else {value = String(remaining)}
    let fraction = places == 0 ? "" : String(format:".%0*lld",places,ticks%scale)
    return (seconds < 0 && ticks > 0 ? "-" : "")+value+fraction
  }
}

extension Telemetry {
  /// Best record before the most recently finished lap began. During the next
  /// lap this differs from current-best precisely when the latest lap improved it.
  public func previousBestLap(at time:Double) -> TelemetryLap? {
    guard time.isFinite,let latest = laps.filter({$0.complete && $0.end <= time && $0.end > $0.start}).max(by:{$0.end < $1.end}) else {return nil}
    return bestLap(at:latest.start)
  }
  static func normalizedLocation(_ name:String?) -> String? {
    guard let name else {return nil}
    let value = name.trimmingCharacters(in:.whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value.prefix(1024))
  }
  public func inferredLocationName(library:TrackLibrary) -> String? {
    guard let lat = channelIndex("lat"),let lon = channelIndex("lon"),
      let index = times.indices.first(where:{columns[lat][$0].isFinite && abs(columns[lat][$0]) <= 90 && columns[lon][$0].isFinite && abs(columns[lon][$0]) <= 180}) else {return nil}
    return library.nearby(latitude:columns[lat][index],longitude:columns[lon][index],radius:5000).first?.track.name
  }
  func resolveLocation(_ settings:DataSettings) {
    if let override = settings.locationName {locationName = Self.normalizedLocation(override);return}
    if let recorded = Self.normalizedLocation(recordedLocationName) {locationName = recorded;return}
    // No filesystem work for sources without GPS, and none in the frame renderer.
    guard channelIndex("lat") != nil,channelIndex("lon") != nil,let library = try? TrackLibrary.read(TrackLibrary.userURL()) else {locationName = nil;return}
    locationName = inferredLocationName(library:library)
  }
}
