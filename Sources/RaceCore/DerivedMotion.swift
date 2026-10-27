import Foundation

public struct ChannelProvenance:Equatable,Sendable {
  public enum Kind:String,Sendable { case recorded,gps,position,speed,heading,calculated }
  public var kind:Kind
  public var details:String
}

struct TelemetryRecordedState:Sendable {
  var headers:[String]
  var columns:[[Double]]
  var aliases:[String:Int]
  var times:[Double]
  var laps:[TelemetryLap]
  var mapPoints:[(Double,Double)]
  var discreteColumns:Set<Int>
}

extension Telemetry {
  var mapColumns:(Int,Int,Bool)? {
    if let x = aliases["x"], let y = aliases["y"] { return (x,y,false) }
    if let lon = aliases["lon"], let lat = aliases["lat"] { return (lon,lat,true) }
    return nil
  }
  func rebuildMapPoints() {
    guard let (xi,yi,gps) = mapColumns else { mapPoints = []; mapLongitudeFactor = 1; return }
    let x = columns[xi], y = columns[yi]
    mapLongitudeFactor = gps ? cos((y.first(where:\.isFinite) ?? 0) * .pi/180) : 1
    mapPoints = stride(from:0,to:count,by:max(1,count/4000)).compactMap { i in
      x[i].isFinite && y[i].isFinite ? (x[i]*mapLongitudeFactor,y[i]) : nil
    }
  }
  public var recordedHeaders:[String] { recordedState?.headers ?? headers }
  public func provenance(for channel:String) -> ChannelProvenance? {
    guard let index = channelIndex(channel) else { return nil }
    return provenance[index] ?? ChannelProvenance(kind:.recorded,details:"Recorded: "+headers[index])
  }
  func restoreRecordedData() {
    if let source = recordedState {
      headers = source.headers; columns = source.columns; aliases = source.aliases
      times = source.times; laps = source.laps; mapPoints = source.mapPoints; discreteColumns = source.discreteColumns
    } else {
      recordedState = TelemetryRecordedState(headers:headers,columns:columns,aliases:aliases,times:times,laps:laps,mapPoints:mapPoints,discreteColumns:discreteColumns)
    }
    provenance.removeAll(); circularColumns.removeAll(); invalidateValueCaches()
  }
  static func normalHeading(_ degrees:Double) -> Double { (degrees.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360) }
  static func headingDelta(from a:Double,to b:Double) -> Double { normalHeading(b-a+180)-180 }
  func deriveMotion(_ settings:DataSettings) {
    if let heading = aliases["heading"] { circularColumns.insert(heading) }
    func needs(_ alias:String,_ mode:DataDerivationMode?) -> Bool {
      mode == .calculate || ((mode ?? .automatic) == .automatic && aliases[alias] == nil)
    }
    let headingNeeded = needs("heading",settings.headingDerivation)
    let xNeeded = needs("gx",settings.longitudinalDerivation), yNeeded = needs("gy",settings.lateralDerivation)
    let speedNeeded = aliases["speed"] == nil
    guard count >= 2, headingNeeded || xNeeded || yNeeded || speedNeeded else { return }
    // O(n) neighbors skip duplicate timestamps. Break derivatives across large gaps.
    let intervals = stride(from:1,to:count,by:max(1,count/2048)).map { times[$0]-times[$0-1] }.filter{$0.isFinite && $0 > 0}.sorted()
    let maximumGap = max(2,(intervals.isEmpty ? 1 : intervals[intervals.count/2])*5)
    var previous = [Int](repeating:0,count:count), next = [Int](repeating:count-1,count:count)
    for i in 1..<count { previous[i] = times[i-1] < times[i] ? i-1 : previous[i-1] }
    for i in stride(from:count-2,through:0,by:-1) { next[i] = times[i+1] > times[i] ? i+1 : next[i+1] }
    func neighbors(_ i:Int) -> (Int,Int)? {
      let a = previous[i], b = next[i], dt = times[b]-times[a]
      guard b > a, dt > 0, dt <= maximumGap else { return nil }; return (a,b)
    }
    var positionSpeed = [Double](repeating:.nan,count:count), positionHeading = positionSpeed
    let gps = aliases["lat"] != nil && aliases["lon"] != nil
    let xi = gps ? aliases["lon"] : aliases["x"], yi = gps ? aliases["lat"] : aliases["y"]
    func positionAxis(_ index:Int?,letter:String) -> Bool {
      guard let index else { return false }
      let h = headers[index].lowercased(); return h.contains("position") || [letter,letter+" (m)"].contains(h)
    }
    let positionAvailable = gps || (positionAxis(xi,letter:"x") && positionAxis(yi,letter:"y"))
    if positionAvailable, let xi, let yi {
      let x = columns[xi], y = columns[yi]
      for i in 0..<count {
        guard x[i].isFinite,y[i].isFinite,let (a,b) = neighbors(i),
          [x[a],x[b],y[a],y[b]].allSatisfy(\.isFinite) else { continue }
        let dt = times[b]-times[a], distance:Double, bearing:Double
        if gps {
          guard abs(y[a]) <= 90, abs(y[b]) <= 90, abs(x[a]) <= 180, abs(x[b]) <= 180 else { continue }
          distance = Self.distance(lat1:y[a],lon1:x[a],lat2:y[b],lon2:x[b])
          let latitude1 = y[a] * .pi/180, latitude2 = y[b] * .pi/180, longitude = (x[b]-x[a]) * .pi/180
          bearing = atan2(sin(longitude)*cos(latitude2),cos(latitude1)*sin(latitude2)-sin(latitude1)*cos(latitude2)*cos(longitude))*180 / .pi
        } else { distance = hypot(x[b]-x[a],y[b]-y[a]); bearing = atan2(x[b]-x[a],y[b]-y[a])*180 / .pi }
        positionSpeed[i] = distance/dt
        if distance > 0.01 { positionHeading[i] = Self.normalHeading(bearing) }
      }
    }
    func append(_ alias:String,_ name:String,_ values:[Double],_ origin:ChannelProvenance.Kind,_ detail:String,force:Bool = false) {
      guard force || values.contains(where:\.isFinite) else { return }
      headers.append(name); columns.append(values); aliases[alias] = headers.count-1
      provenance[headers.count-1] = ChannelProvenance(kind:origin,details:detail)
      if alias == "heading" { circularColumns.insert(headers.count-1) }
    }
    let positionOrigin:ChannelProvenance.Kind = gps ? .gps : .position
    let positionName = gps ? "GPS" : "position"
    if speedNeeded { append("speed","Estimated speed (m/s)",positionSpeed,positionOrigin,"Estimated from \(positionName) positions") }
    let speed:[Double]
    if let index = aliases["speed"] {
      let header = headers[index].lowercased()
      let factor = header.contains("mph") ? 1/2.2369362921 : header.contains("knot") ? 0.514444 : (header.contains("km") || header == "kph") ? 1/3.6 : 1
      speed = columns[index].map{$0*factor}
    } else { speed = positionSpeed }
    // Use physical GPS/XY course for lateral G, independent of display heading adjustment.
    var course = positionHeading
    let positionCourse = course.contains(where:\.isFinite)
    var recordedCourse = false
    if !positionCourse, settings.headingDerivation != .calculate, let recorded = aliases["heading"] {
      let adjustment = settings.headingAdjustment.flatMap{$0.isFinite ? $0 : nil} ?? 0
      course = columns[recorded].map { Self.normalHeading($0*(settings.reverseHeading == true ? -1 : 1)+adjustment) }
      recordedCourse = true
    }
    var longitudinal = [Double](repeating:.nan,count:count), lateral = longitudinal
    for i in 0..<count {
      guard let (a,b) = neighbors(i),speed[i].isFinite else { continue }
      let dt = times[b]-times[a]
      if speed[a].isFinite,speed[b].isFinite { longitudinal[i] = (speed[b]-speed[a])/dt/9.80665 }
      if abs(speed[i]) < 0.1 && (positionAvailable || recordedCourse) { lateral[i] = 0 }
      else if course[a].isFinite,course[b].isFinite {
        lateral[i] = speed[i]*Self.headingDelta(from:course[a],to:course[b]) * .pi/180/dt/9.80665
      }
    }
    if headingNeeded { append("heading","Estimated heading (deg)",positionHeading,positionOrigin,"Estimated from \(positionName) motion",force:settings.headingDerivation == .calculate) }
    if xNeeded { append("gx","Estimated longitudinal acceleration (G)",longitudinal,.speed,"Estimated from speed changes",force:settings.longitudinalDerivation == .calculate) }
    let lateralUsesPosition = positionAvailable && !recordedCourse
    if yNeeded { append("gy","Estimated lateral acceleration (G)",lateral,lateralUsesPosition ? positionOrigin : .heading,"Estimated from \(lateralUsesPosition ? positionName : "heading") course and speed",force:settings.lateralDerivation == .calculate) }
  }
}
