import Foundation

public struct GearEstimationSettings:Codable,Equatable,Sendable {
  /// RPM divided by speed in m/s, descending from first to last gear. Nil learns ratios.
  public var ratios:[Double]?
  public var minimumSpeed:Double?
  public var minimumRPM:Double?
  public var tolerance:Double?
  public var maximumGears:Int?
  public var minimumDwell:Double?
  public init() {}
  public var speedFloor:Double { minimumSpeed ?? 3 }
  public var rpmFloor:Double { minimumRPM ?? 500 }
  public var ratioTolerance:Double { tolerance ?? 0.12 }
  public var gearLimit:Int { maximumGears ?? 10 }
  public var dwell:Double { minimumDwell ?? 0.3 }
  public func validate() throws {
    guard speedFloor.isFinite,speedFloor > 0,rpmFloor.isFinite,rpmFloor >= 0,
      ratioTolerance.isFinite,(0.005...0.4).contains(ratioTolerance),(1...12).contains(gearLimit),
      dwell.isFinite,dwell > 0 else { throw RaceError.invalid("Use positive speed/dwell limits, nonnegative RPM, 0.5–40% tolerance and 1–12 detected gears.") }
    if let ratios {
      guard (1...12).contains(ratios.count),ratios.allSatisfy({$0.isFinite && $0 > 0}),
        zip(ratios,ratios.dropFirst()).allSatisfy({$0 > $1}) else {
        throw RaceError.invalid("Enter 1–12 positive ratios in descending order (RPM per m/s), from first to last gear.")
      }
    }
  }
}

public struct GearCalibration:Equatable,Sendable {
  public var ratios:[Double]
  public var supportingSeconds:[Double]
  public var manual:Bool
  public var matchedSamples:Int
  public var candidateSamples:Int
  public var matchedFraction:Double { candidateSamples > 0 ? Double(matchedSamples)/Double(candidateSamples) : 0 }
}

public enum GearEstimator {
  public struct Result:Sendable { public var values:[Double]; public var calibration:GearCalibration }
  public static func displayName(_ value:Double?) -> String {
    guard let value,value.isFinite,abs(value) < 1000 else { return "—" }
    if value == 0 { return "N" }; if value < 0 { return "R" }
    return String(Int(value.rounded()))
  }
  public static func estimate(times:[Double],speed:[Double],rpm:[Double],settings:GearEstimationSettings = .init()) throws -> Result {
    try settings.validate()
    guard times.count == speed.count,times.count == rpm.count,times.count >= 2,
      times.allSatisfy(\.isFinite),zip(times,times.dropFirst()).allSatisfy({$0 < $1}) else {
      throw RaceError.invalid("Gear estimation needs matching speed/RPM samples on an increasing time axis.")
    }
    let count = times.count
    let logs = (0..<count).map { i -> Double in
      guard speed[i].isFinite,rpm[i].isFinite,speed[i] >= settings.speedFloor,rpm[i] >= settings.rpmFloor else { return .nan }
      let value = rpm[i]/speed[i]; return value.isFinite && value > 0 ? log(value) : .nan
    }
    var ratios:[Double], supports:[Double]
    if let manual = settings.ratios { ratios = manual; supports = [Double](repeating:0,count:manual.count) }
    else {
      // Stable windows reject ordinary shift/clutch transitions. Time weighting avoids
      // treating a fast logger as stronger evidence than the same duration at low Hz.
      var histogram:[Int:Double] = [:], left = 0, right = 0
      let width = 0.01
      for i in 0..<count where logs[i].isFinite {
        while left+1 < i && times[left+1] < times[i]-0.15 { left += 1 }
        right = max(right,i)
        while right+1 < count && times[right] < times[i]+0.15 { right += 1 }
        guard logs[left].isFinite,logs[right].isFinite,times[right]-times[left] <= 2,
          abs(logs[left]-logs[i]) <= 0.04,abs(logs[right]-logs[i]) <= 0.04 else { continue }
        let duration = i+1 < count ? min(1,max(0,times[i+1]-times[i])) : 0
        histogram[Int((logs[i]/width).rounded()),default:0] += duration
      }
      func weight(_ bin:Int) -> Double { (-1...1).reduce(0) { $0+(histogram[bin+$1] ?? 0) } }
      let peaks = histogram.keys.filter { weight($0) >= settings.dwell && weight($0) >= weight($0-1) && weight($0) >= weight($0+1) }
        .sorted { weight($0) == weight($1) ? $0 > $1 : weight($0) > weight($1) }
      var centers:[(Double,Double)] = []
      for peak in peaks {
        var sum = 0.0, support = 0.0
        for bin in (peak-2)...(peak+2) { let w = histogram[bin] ?? 0; support += w; sum += Double(bin)*width*w }
        guard support >= settings.dwell else { continue }
        let center = sum/support
        if centers.allSatisfy({abs($0.0-center) > log(1.06)}) { centers.append((center,support)) }
        if centers.count == settings.gearLimit { break }
      }
      centers.sort{$0.0 > $1.0}; ratios = centers.map{exp($0.0)}; supports = centers.map{$0.1}
      guard !ratios.isEmpty else { throw RaceError.invalid("No stable gear ratios found. Check speed/RPM timing or enter manual ratios.") }
    }
    let centers = ratios.map(log), allowed = log(1+settings.ratioTolerance)
    var values = [Double](repeating:.nan,count:count), previous:Int?, candidates = 0, matched = 0
    for i in 0..<count {
      if i > 0,times[i]-times[i-1] > 2 { previous = nil }
      guard logs[i].isFinite else { previous = nil; continue }; candidates += 1
      guard var best = centers.indices.min(by:{abs(centers[$0]-logs[i]) < abs(centers[$1]-logs[i])}),
        abs(centers[best]-logs[i]) <= allowed else { previous = nil; continue }
      if let old = previous, abs(centers[old]-logs[i]) <= allowed,
        abs(centers[old]-logs[i]) <= abs(centers[best]-logs[i])+log(1.01) { best = old }
      values[i] = Double(best+1); previous = best; matched += 1
    }
    for i in 0..<(count-1) where times[i+1]-times[i] > 2 { values[i] = .nan }
    matched = values.reduce(0) { $0+($1.isFinite ? 1 : 0) }
    return Result(values:values,calibration:GearCalibration(ratios:ratios,supportingSeconds:supports,manual:settings.ratios != nil,matchedSamples:matched,candidateSamples:candidates))
  }
}

extension Telemetry {
  public func gearRatio(at time:Double,settings:GearEstimationSettings = .init()) -> Double? {
    guard let speed = speed(at:time,unit:"m/s"),let rpm = value("rpm",at:time),speed >= settings.speedFloor,rpm >= settings.rpmFloor else { return nil }
    let ratio = rpm/speed; return ratio.isFinite && ratio > 0 ? ratio : nil
  }
  func deriveGear(_ settings:DataSettings) {
    if let gear = aliases["gear"] { discreteColumns.insert(gear) }
    let mode = settings.gearDerivation ?? .automatic
    let recorded = aliases["gear"].map { columns[$0].contains(where:\.isFinite) } ?? false
    guard mode != .recordedOnly,mode == .calculate || !recorded else { return }
    var result:[Double]?
    do {
      guard let speed = aliases["speed"],let rpm = aliases["rpm"] else { throw RaceError.invalid("Gear estimation needs speed and RPM channels.") }
      let header = headers[speed].lowercased()
      let factor = header.contains("mph") ? 1/2.2369362921 : header.contains("knot") ? 0.514444 : (header.contains("km") || header == "kph") ? 1/3.6 : 1
      let output = try GearEstimator.estimate(times:times,speed:columns[speed].map{$0*factor},rpm:columns[rpm],settings:settings.gearEstimation ?? .init())
      gearCalibration = output.calibration; result = output.values
    } catch { gearEstimateMessage = error.localizedDescription }
    guard result != nil || mode == .calculate else { return }
    headers.append("Estimated gear"); columns.append(result ?? [Double](repeating:.nan,count:count))
    let index = headers.count-1; aliases["gear"] = index; discreteColumns.insert(index)
    provenance[index] = ChannelProvenance(kind:.gear,details:gearEstimateMessage ?? "Estimated from speed/RPM ratios")
  }
}
