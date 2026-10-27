import AppKit

public struct TimerSettings:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable { case lap,manual,timeOfDay }
  public enum Clock:String,Codable,CaseIterable,Sendable { case source,project }
  public enum Format:String,Codable,CaseIterable,Sendable { case automatic,seconds,minutesSeconds,hoursMinutesSeconds }
  public var mode:Mode = .lap
  public var clock:Clock = .source
  public var format:Format = .automatic
  public var decimals:Int = 3
  public var compact = false
  public var startDelay:Double = 0
  public var startOffset:Double = 0
  public var stopValue:Double?
  public var anchorTime:Double?
  public var epoch:Double?
  public var timeZone = "UTC"
  public var twelveHour = false
  public var showTimeZone = false
  public var label = ""
  public var panel = true
  public init() {}
  public var usesSourceClock:Bool { mode == .lap || (mode == .timeOfDay && clock == .source) }
  public func validate() throws {
    guard (0...3).contains(decimals) else { throw RaceError.invalid("Choose 0–3 timer decimal places.") }
    if mode == .manual {
    guard startDelay.isFinite,startDelay >= 0,startDelay <= 1e9,
      startOffset.isFinite,abs(startOffset) <= 1e9,anchorTime.map({$0.isFinite && abs($0) <= 1e9}) ?? true,
      stopValue.map({$0.isFinite && $0 >= startOffset && abs($0) <= 1e9}) ?? true else { throw RaceError.invalid("Timer needs 0–3 decimals, nonnegative delay, finite values, and a stop value at or above its initial value.") }
    }
    guard mode == .timeOfDay else { return }
    guard TimeZone(identifier:timeZone) != nil,epoch.map({$0.isFinite && (-62135596800...253402300799).contains($0)}) ?? true else { throw RaceError.invalid("Choose a valid IANA timezone and a clock anchor between years 1 and 9999.") }
    if mode == .timeOfDay,clock == .project,epoch == nil { throw RaceError.invalid("Set the UTC clock anchor for project time zero.") }
  }
  public func value(projectTime:Double,sourceTime:Double,displayStart:Double,data:Telemetry?) -> Double? {
    guard (try? validate()) != nil else { return nil }
    switch mode {
    case .manual:
      let elapsed = max(0,projectTime-(anchorTime ?? displayStart)-startDelay)
      let value = startOffset+elapsed; return stopValue.map{min($0,value)} ?? value
    case .lap:
      return data?.lap(at:sourceTime).map{sourceTime-$0.start}
    case .timeOfDay:
      guard let start = epoch ?? (clock == .source ? data?.firstSampleUnixTime : nil) else { return nil }
      let elapsed = clock == .source ? sourceTime : projectTime
      guard elapsed.isFinite,clock != .source || (elapsed >= 0 && elapsed <= (data?.duration ?? .infinity)) else { return nil }
      let value = start+elapsed; return (-62135596800...253402300799).contains(value) ? value : nil
    }
  }
  public func string(projectTime:Double,sourceTime:Double,displayStart:Double,data:Telemetry?) -> String {
    guard let value = value(projectTime:projectTime,sourceTime:sourceTime,displayStart:displayStart,data:data),value.isFinite else { return "—" }
    if mode == .timeOfDay { return TimerClockFormatter.string(value,settings:self) }
    return Self.durationString(value,format:format,decimals:decimals,compact:compact)
  }
  public static func durationString(_ seconds:Double,format:Format = .automatic,decimals:Int = 3,compact:Bool = false) -> String {
    guard seconds.isFinite,abs(seconds) <= 1e10,(0...3).contains(decimals) else { return "—" }
    let factor = pow(10,Double(decimals)),ticks = Int64((abs(seconds)*factor+1e-7).rounded(.down))
    let whole = ticks/Int64(factor),fraction = ticks%Int64(factor)
    let style = format == .automatic ? (whole >= 3600 ? Format.hoursMinutesSeconds : .minutesSeconds) : format
    func leading(_ value:Int64) -> String { compact ? String(value) : String(format:"%02lld",value) }
    let value:String
    switch style {
    case .seconds:value = leading(whole)
    case .minutesSeconds,.automatic:value = leading(whole/60)+String(format:":%02lld",whole%60)
    case .hoursMinutesSeconds:value = leading(whole/3600)+String(format:":%02lld:%02lld",(whole/60)%60,whole%60)
    }
    let suffix = decimals == 0 ? "" : String(format:".%0*lld",decimals,fraction)
    return (seconds < 0 && ticks > 0 ? "−" : "")+value+suffix
  }
}

private final class TimerClockFormatter:NSObject {
  let formatter:DateFormatter
  let lock = NSLock()
  static let cache:NSCache<NSString,TimerClockFormatter> = { let c = NSCache<NSString,TimerClockFormatter>(); c.countLimit = 64; return c }()
  init(_ settings:TimerSettings) {
    let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.calendar = Calendar(identifier:.gregorian)
    f.timeZone = TimeZone(identifier:settings.timeZone)
    let hour = settings.twelveHour ? (settings.compact ? "h" : "hh") : (settings.compact ? "H" : "HH")
    let format = settings.format
    var pattern = format == .seconds ? (settings.compact ? "s" : "ss") : format == .minutesSeconds ? (settings.compact ? "m:ss" : "mm:ss") : hour+":mm:ss"
    if settings.decimals > 0 { pattern += "."+String(repeating:"S",count:settings.decimals) }
    if settings.twelveHour,![.seconds,.minutesSeconds].contains(format) { pattern += " a" }
    if settings.showTimeZone { pattern += " z" }; f.dateFormat = pattern; formatter = f
  }
  static func string(_ epoch:Double,settings:TimerSettings) -> String {
    let key = "\(settings.timeZone)|\(settings.format.rawValue)|\(settings.decimals)|\(settings.compact)|\(settings.twelveHour)|\(settings.showTimeZone)" as NSString
    let instance:TimerClockFormatter
    if let value = cache.object(forKey:key) { instance = value }
    else { instance = TimerClockFormatter(settings); cache.setObject(instance,forKey:key) }
    instance.lock.lock(); defer { instance.lock.unlock() }
    return instance.formatter.string(from:Date(timeIntervalSince1970:epoch))
  }
}

enum TimerDisplayRenderer {
  static func draw(_ c:CGContext,object:DisplayObject,rect:CGRect,data:Telemetry?,sourceTime:Double,projectTime:Double) -> Bool {
    guard object.kind == .timer,let settings = object.timerSettings else { return false }
    let valid = (try? settings.validate()) != nil
    let content = valid ? settings.string(projectTime:projectTime,sourceTime:sourceTime,displayStart:object.start,data:data) : "INVALID TIMER"
    let label = settings.label.isEmpty ? settings.mode == .manual ? "MANUAL TIME" : settings.mode == .timeOfDay ? "TIME OF DAY" : "LAP TIME" : settings.label
    if settings.panel { OverlayRenderer.panel(c,rect) }
    let fontSize = min(rect.height*0.48,rect.width/Double(max(4,content.count))*1.35)
    let font = NSFont.monospacedDigitSystemFont(ofSize:fontSize,weight:.semibold)
    let measured = NSAttributedString(string:content,attributes:[.font:font]).size().width
    let fit = min(1,rect.width*0.88/max(1,measured))
    OverlayRenderer.text(c,label,x:rect.minX+rect.width*0.06,y:rect.minY+rect.height*0.68,size:min(rect.height*0.16,rect.width/Double(max(10,label.count))*1.2),color:"#97A6BA",align:0)
    OverlayRenderer.text(c,content,x:rect.minX+rect.width*0.06,y:rect.minY+rect.height*0.12,size:fontSize*fit,color:object.color,align:0)
    return true
  }
}
