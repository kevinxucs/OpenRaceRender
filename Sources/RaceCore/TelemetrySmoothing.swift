import Foundation

extension Telemetry {
  func prepareSmoothing(_ settings:DataSettings) {
    let intervals = stride(from:1,to:count,by:max(1,count/2048)).map{times[$0]-times[$0-1]}.filter{$0 > 0}.sorted()
    maximumInterpolationGap = max(2,(intervals.isEmpty ? 1 : intervals[intervals.count/2])*5)
    guard interpolationEnabled else { return }
    if settings.detectGPSUpdates == true {
      if let lat = aliases["lat"],let lon = aliases["lon"] { boostHeldGPS([lat,lon]) }
      if let speed = aliases["speed"],!(sourceHeaders["speed"] ?? headers[speed]).lowercased().contains("obd") { boostHeldGPS([speed]) }
    }
    guard settings.smoothCurves == true,let (x,y,_) = mapColumns else { return }
    for column in [x,y] {
      let v = columns[column]
      var slopes = [Double](repeating:0,count:count)
      func secant(_ a:Int,_ b:Int) -> Double? {
        guard a >= 0,b < count,v[a].isFinite,v[b].isFinite,times[b] > times[a],times[b]-times[a] <= maximumInterpolationGap else { return nil }
        return (v[b]-v[a])/(times[b]-times[a])
      }
      for i in times.indices {
        let before = secant(i-1,i),after = secant(i,i+1)
        if let a = before,let b = after {
          if a*b > 0 {
            let h0 = times[i]-times[i-1],h1 = times[i+1]-times[i]
            let w0 = 2*h1+h0,w1 = h1+2*h0
            slopes[i] = (w0+w1)/(w0/a+w1/b)
          }
        } else { slopes[i] = before ?? after ?? 0 }
      }
      positionSlopes[column] = slopes
    }
  }
  /// Reconstruct repeated GPS updates at their observed fix timestamps. Long holds remain stops/gaps.
  private func boostHeldGPS(_ indices:[Int]) {
    guard count >= 5,!indices.isEmpty else { return }
    var updates:[Int] = []
    for i in times.indices {
      guard indices.allSatisfy({columns[$0][i].isFinite}) else { continue }
      if i == 0 || indices.contains(where:{columns[$0][i] != columns[$0][i-1]}) { updates.append(i) }
    }
    guard updates.count >= 3,updates.count < count/2 else { return }
    let periods = zip(updates,updates.dropFirst()).map{times[$1]-times[$0]}.filter{$0 > 0 && $0 <= maximumInterpolationGap}.sorted()
    guard !periods.isEmpty else { return }
    let nominal = periods[periods.count/2],limit = min(maximumInterpolationGap,nominal*1.75)
    for (a,b) in zip(updates,updates.dropFirst()) {
      let duration = times[b]-times[a]
      guard b > a+1,duration > 0,duration <= limit,
        (a...b).allSatisfy({i in indices.allSatisfy{columns[$0][i].isFinite}}),
        (a..<b).allSatisfy({times[$0+1]-times[$0] <= maximumInterpolationGap}) else { continue }
      for column in indices {
        let first = columns[column][a],delta = columns[column][b]-first
        for i in (a+1)..<b { columns[column][i] = first+delta*(times[i]-times[a])/duration }
      }
    }
  }
  func curvedPosition(_ column:Int,index:Int,fraction:Double) -> Double? {
    guard let slopes = positionSlopes[column],index+1 < count else { return nil }
    let a = columns[column][index],b = columns[column][index+1],dt = times[index+1]-times[index]
    let u = fraction,u2 = u*u,u3 = u2*u
    let value = (2*u3-3*u2+1)*a+(u3-2*u2+u)*dt*slopes[index]+(-2*u3+3*u2)*b+(u3-u2)*dt*slopes[index+1]
    return min(max(a,b),max(min(a,b),value))
  }
  /// Centered time-weighted mean; independent of render order, FPS and chunk boundaries.
  public func averagedValue(_ channel:String,at time:Double,window:Double) -> Double? {
    guard let column = channelIndex(channel),let current = value(channel,at:time) else { return nil }
    guard window.isFinite,window > 0,!discreteColumns.contains(column),count > 1 else { return current }
    let span = min(10,window),start = max(0,time-span/2),end = min(duration,time+span/2)
    guard end > start else { return current }
    let key = String(column) as NSString
    let series:TelemetryAverageSeries
    if let cached = averageCache.object(forKey:key) { series = cached }
    else {
      series = TelemetryAverageSeries(times:times,values:columns[column],circular:circularColumns.contains(column),interpolate:interpolationEnabled,gap:maximumInterpolationGap)
      averageCache.setObject(series,forKey:key,cost:(count+1)*(series.circular ? 3 : 2)*8)
    }
    return series.average(from:start,to:end,first:index(at:start),last:index(at:end)) ?? current
  }
}

final class TelemetryAverageSeries:NSObject {
  let times:[Double],values:[Double],circular:Bool,interpolate:Bool,gap:Double
  var area:[Double],second:[Double],coverage:[Double]
  init(times:[Double],values:[Double],circular:Bool,interpolate:Bool,gap:Double) {
    self.times = times; self.values = values; self.circular = circular; self.interpolate = interpolate; self.gap = gap
    area = [Double](repeating:0,count:times.count); second = circular ? area : []; coverage = area
    super.init()
    for i in 0..<(times.count-1) {
      let integral = part(i,fraction:1)
      area[i+1] = area[i]+integral.0; coverage[i+1] = coverage[i]+integral.2
      if circular { second[i+1] = second[i]+integral.1 }
    }
  }
  private func part(_ i:Int,fraction u:Double) -> (Double,Double,Double) {
    guard i+1 < times.count else { return (0,0,0) }
    let dt = times[i+1]-times[i],a = values[i],b = values[i+1]
    guard dt > 0,dt <= gap,a.isFinite,!interpolate || b.isFinite else { return (0,0,0) }
    if circular {
      let theta = a * .pi/180,delta = interpolate ? Telemetry.headingDelta(from:a,to:b) * .pi/180 : 0
      if abs(delta) < 1e-12 { return (cos(theta)*dt*u,sin(theta)*dt*u,dt*u) }
      return ((sin(theta+delta*u)-sin(theta))*dt/delta,(cos(theta)-cos(theta+delta*u))*dt/delta,dt*u)
    }
    return (dt*(a*u+(interpolate ? (b-a)*u*u/2 : 0)),0,dt*u)
  }
  private func integral(at t:Double,index i:Int) -> (Double,Double,Double) {
    let dt = i+1 < times.count ? times[i+1]-times[i] : 0
    let p = part(i,fraction:dt > 0 ? min(1,max(0,(t-times[i])/dt)) : 0)
    return (area[i]+p.0,(circular ? second[i] : 0)+p.1,coverage[i]+p.2)
  }
  func average(from start:Double,to end:Double,first:Int,last:Int) -> Double? {
    let a = integral(at:start,index:first),b = integral(at:end,index:last),duration = end-start
    // A window touching a missing interval falls back to the current reading, never blends across gaps.
    guard abs((b.2-a.2)-duration) <= max(1e-8,duration*1e-8) else { return nil }
    if circular {
      let x = b.0-a.0,y = b.1-a.1
      guard hypot(x,y) > duration*1e-8 else { return nil }
      return Telemetry.normalHeading(atan2(y,x)*180 / .pi)
    }
    let result = (b.0-a.0)/duration
    return result.isFinite ? result : nil
  }
}
