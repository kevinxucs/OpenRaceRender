import Foundation
import GoProGPMF

/// Progressive GoPro MP4/MOV telemetry. Camera sensor axes deliberately have no vehicle-G aliases.
public enum CameraTelemetry {
  public static let extensions = ["mp4","mov","m4v","360"]
  struct Series { var times:[Double] = [];var rows:[[Double]] = [] }
  struct Table {
    var headers:[String];var times:[Double];var columns:[[Double]];var aliases:[String:Int]
    var epoch:Double?;var warnings:[String]
  }
  public static func isAvailable(in url:URL) throws -> Bool {try CameraMP4.read(url) != nil}
  static func key(_ s:String) -> UInt32 {s.utf8.enumerated().reduce(UInt32(0)) {$0 | (UInt32($1.element) << ($1.offset*8))}}
  static func metadata(_ key:String,_ stream:GPMF_stream) -> Data? {
    var copy = stream
    guard GPMF_FindPrev(&copy,self.key(key),GPMF_CURRENT_LEVEL) == GPMF_OK.rawValue,
      let pointer = GPMF_RawData(&copy) else {return nil}
    let size = Int(GPMF_RawDataSize(&copy));guard size <= 4096 else {return nil}
    return Data(bytes:pointer,count:size)
  }
  static func read(_ url:URL) throws -> Table {
    guard let index = try CameraMP4.read(url) else {throw RaceError.invalid("No GoPro gpmd metadata track in this movie.")}
    let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
    var series:[String:Series] = [:];var epoch:Double?;var rows = 0
    let utc = DateFormatter();utc.locale = Locale(identifier:"en_US_POSIX");utc.timeZone = TimeZone(secondsFromGMT:0);utc.dateFormat = "yyMMddHHmmss.SSS"
    for packet in index.packets {
      try Task.checkCancellation()
      try file.seek(toOffset:packet.offset)
      let bytes = try file.read(upToCount:packet.size) ?? Data()
      guard bytes.count == packet.size,bytes.count % 4 == 0 else {throw RaceError.invalid("Truncated or unaligned GPMF packet.")}
      var words = [UInt32](repeating:0,count:bytes.count/4)
      _ = words.withUnsafeMutableBytes {bytes.copyBytes(to:$0)}
      try words.withUnsafeMutableBufferPointer {buffer in
        var stream = GPMF_stream()
        guard GPMF_Init(&stream,buffer.baseAddress,UInt32(bytes.count)) == GPMF_OK.rawValue else {throw RaceError.invalid("Invalid GPMF packet header.")}
        defer {GPMF_Free(&stream)}
        guard GPMF_Validate(&stream,GPMF_RECURSE_LEVELS) == GPMF_OK.rawValue else {throw RaceError.invalid("Malformed camera GPMF metadata.")}
        var decoded:[String:Series] = [:]
        for name in ["GPS9","GPS5","ACCL","GYRO"] {
          GPMF_ResetState(&stream)
          guard GPMF_FindNext(&stream,key(name),GPMF_RECURSE_LEVELS) == GPMF_OK.rawValue else {continue}
          let count = Int(GPMF_PayloadSampleCount(&stream)),width = Int(GPMF_ElementsInStruct(&stream))
          let expected = name == "GPS9" ? 9 : (name == "GPS5" ? 5 : 3)
          guard count > 0,count <= 100_000,width == expected else {throw RaceError.invalid("Unsupported \(name) camera sample layout.")}
          var values = [Double](repeating:0,count:count*width)
          let result = values.withUnsafeMutableBytes {GPMF_ScaledData(&stream,$0.baseAddress,UInt32($0.count),0,UInt32(count),GPMF_TYPE_DOUBLE)}
          guard result == GPMF_OK.rawValue else {throw RaceError.invalid("Could not decode scaled \(name) camera samples.")}
          let fixData = metadata("GPSF",stream),fix = fixData.flatMap {try? CameraMP4.uint($0,0,min(4,$0.count))} ?? 0
          let dopData = metadata("GPSP",stream),dop = dopData.flatMap {try? CameraMP4.uint($0,0,min(4,$0.count))}.map{Double($0)/100} ?? .nan
          if name == "GPS5",epoch == nil,let stamp = metadata("GPSU",stream),let text = String(data:stamp,encoding:.ascii),let date = utc.date(from:text.trimmingCharacters(in:.controlCharacters)) {
            epoch = date.timeIntervalSince1970-packet.time
          }
          var run = Series()
          for i in 0..<count {
            let time = packet.time+Double(i)*packet.duration/Double(count)
            guard time >= 0,time <= index.duration+0.01,index.activeRange.map({time >= $0.lowerBound && time < $0.upperBound}) ?? true else {continue}
            var row = Array(values[i*width..<(i+1)*width])
            if name.hasPrefix("GPS") {
              let gpsFix = name == "GPS9" ? row[8] : Double(fix)
              let gpsDop = name == "GPS9" ? row[7] : dop
              if name == "GPS9",epoch == nil,row[5].isFinite,row[6].isFinite,(0...100_000).contains(row[5]),(0...86401).contains(row[6]),gpsFix >= 2 {
                epoch = 946684800+row[5]*86400+row[6]-time
              }
              let valid = gpsFix >= 2 && row[0].isFinite && row[1].isFinite && abs(row[0]) <= 90 && abs(row[1]) <= 180
              row = Array(row.prefix(5))+[gpsDop,gpsFix]
              if !valid {for j in 0..<5 {row[j] = .nan}}
            }
            run.times.append(time);run.rows.append(row)
          }
          decoded[name] = run
        }
        if decoded["GPS9"] != nil {decoded.removeValue(forKey:"GPS5")}
        for (name,run) in decoded {
          let key = name.hasPrefix("GPS") ? "GPS" : name
          rows += run.times.count
          guard rows <= 2_000_000 else {throw RaceError.invalid("Camera extraction exceeds two million sensor samples; split the movie first.")}
          var current = series.removeValue(forKey:key) ?? Series()
          for i in run.times.indices where run.times[i] > (current.times.last ?? -.infinity) {current.times.append(run.times[i]);current.rows.append(run.rows[i])}
          series[key] = current
        }
      }
    }
    guard series.values.contains(where:{$0.rows.contains(where:{$0.contains(where:\.isFinite)})}) else {throw RaceError.invalid("Camera track contains no supported GPS or motion samples.")}
    let names = ["GPS","ACCL","GYRO"].filter{series[$0]?.times.isEmpty == false}
    var timeline = Set<Int64>([0,Int64((index.duration*1_000_000).rounded())])
    for name in names {for t in series[name]!.times {timeline.insert(Int64((t*1_000_000).rounded()))}}
    guard timeline.count <= 1_000_000 else {throw RaceError.invalid("Camera telemetry exceeds one million output rows; split the movie first.")}
    let times = timeline.sorted().map{Double($0)/1_000_000}
    var headers = ["Time (s)"],columns = [times],aliases:[String:Int] = [:]
    for name in names {
      let run = series[name]!
      let labels:[String]
      if name == "GPS" {
        let start = headers.count
        labels = ["Latitude (deg)","Longitude (deg)","Altitude (m)","Speed (m/s)","3D speed (m/s)","GPS DOP","GPS fix"]
        aliases["lat"] = start;aliases["lon"] = start+1;aliases["altitude"] = start+2;aliases["speed"] = start+3
      } else {labels = (1...3).map {"Camera \(name == "ACCL" ? "acceleration" : "gyro") axis \($0) (\(name == "ACCL" ? "m/s²" : "rad/s"))"}}
      var output = Array(repeating:[Double](repeating:.nan,count:times.count),count:labels.count);var k = 0
      for (i,t) in times.enumerated() {
        while k+1 < run.times.count,run.times[k+1] <= t+0.000001 {k += 1}
        guard t >= run.times[k]-0.000001,t <= run.times.last!+0.000001 else {continue}
        for j in labels.indices {
          let a = run.rows[k][j]
          if abs(t-run.times[k]) < 0.000002 {output[j][i] = a}
          else if k+1 < run.times.count,run.times[k+1]-run.times[k] <= 2,a.isFinite,run.rows[k+1][j].isFinite {
            if name == "GPS",j == 6 {output[j][i] = a}
            else {output[j][i] = a+(run.rows[k+1][j]-a)*(t-run.times[k])/(run.times[k+1]-run.times[k])}
          }
        }
      }
      headers += labels;columns += output
    }
    return Table(headers:headers,times:times,columns:columns,aliases:aliases,epoch:epoch,warnings:[
      "GoPro camera telemetry: packet times are retained relative to movie zero; sensor samples are spaced within each packet. Verify synchronization against a visible event (sensor latency can differ).",
      "Camera acceleration/gyro axes describe the camera, not vehicle longitudinal/lateral G. GPS DOP is dimensionless, not accuracy in meters."])
  }
}
