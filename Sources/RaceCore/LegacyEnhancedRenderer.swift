import AppKit

final class EnhancedProgram: NSObject {
  let background: [ScriptStatement]
  let foreground: [ScriptStatement]
  init(_ data: Data) throws {
    func source(_ offset: Int) -> String {
      let bytes = data[offset..<min(data.count,offset+32768)].prefix { $0 != 0 }
      return String(bytes: bytes,encoding:.utf8) ?? ""
    }
    var a = try ScriptParser(source(1632)), b = try ScriptParser(source(34400))
    background = try a.parse(); foreground = try b.parse()
    super.init()
  }
}

enum LegacyEnhancedRenderer {
  static let programs = NSCache<NSData,EnhancedProgram>()
  static let histories: NSCache<NSString,EnhancedHistory> = {
    let cache = NSCache<NSString,EnhancedHistory>();cache.countLimit = 16;return cache
  }()
  private static let historyLock = NSLock()
  static func draw(_ c: CGContext, object o: DisplayObject, rect: CGRect, data: Telemetry?, time: Double, unit: String, timeline: EnhancedTimeline = EnhancedTimeline(), failure: ((String) -> Void)? = nil, message:((String)->Void)? = nil) -> Bool {
    guard o.legacyType == 50, let payload = o.legacyPayload, payload.count >= 67168 else { return false }
    let key = payload as NSData
    let program: EnhancedProgram
    if let cached = programs.object(forKey:key) { program = cached }
    else {
      do { program = try EnhancedProgram(payload); programs.setObject(program,forKey:key,cost:payload.count) }
      catch { failure?(error.localizedDescription);return false }
    }
    let width = Int(payload[280]) | Int(payload[281]) << 8
    let height = Int(payload[282]) | Int(payload[283]) << 8
    guard width > 0, height > 0, width <= 2048, height <= 2048,
      let canvas = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
        space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo) else { return false }
    let rawMin = payload.f64(256),rawMax = payload.f64(264)
    let autoMin = !rawMin.isFinite || abs(rawMin) >= 9e7
    let autoMax = !rawMax.isFinite || abs(rawMax) >= 9e7
    let channel = o.resolvedChannel
    let measured = channelBounds(channel,data:data,unit:unit)
    let minimum = autoMin ? measured?.0 ?? o.minimum : rawMin
    let maximum = autoMax ? max(minimum+1,measured?.1 ?? o.maximum) : rawMax
    let trigger = payload.f64(272)
    let value = channelValue(channel,data:data,time:time,unit:unit,interpolate:o.kind != .gear)
    let range = max(0.00001,maximum-minimum)
    var vars: [String:ScriptValue] = [:]
    func number(_ name: String,_ value: Double) { vars[name.lowercased()] = .number(value) }
    let numbers: [String:Double] = ["SizeX":Double(width),"SizeY":Double(height),"CenterX":Double(width)/2,"CenterY":Double(height)/2,
      "DataMin":minimum,"DataMax":maximum,"DataRange":range,"DataValue":value,"DataFactor":(value-minimum)/range,
      "DataTrigger":trigger,"DataTriggerFactor":(trigger-minimum)/range,"IsTriggered":value >= trigger ? 1.0 : 0,
      "DataMinAuto":autoMin ? 1.0 : 0,"DataMaxAuto":autoMax ? 1.0 : 0,
      "SampleTime":time,"DisplayTime":timeline.displayTime(at:time),"FrameInterval":timeline.frameInterval,"True":1.0,"False":0.0,"Filled":0.0,
      "AlignH_Left":0.0,"AlignH_Center":1.0,"AlignH_Right":2.0,"Transparent":-1.0,"Invisible":-1.0]
    for (name,value) in numbers { number(name,value) }
    for (name,value) in ["White":0xffffff,"Gray":0x808080,"Black":0,"Red":0xff0000,"Green":0x00ff00,"Blue":0x0000ff,
      "Yellow":0xffff00,"Orange":0xff8000,"Brown":0x804000,"Cyan":0x00ffff,"Magenta":0xff00ff] { number(name,Double(value)) }
    for i in 0..<8 { number("Color"+String(UnicodeScalar(65+i)!),Double(payload.u32(576+i*4) & 0xffffff)) }
    let fields = ["posx","posy","posz","speed","heading","gforcex","gforcey","throttle","brake","rpm","gear","airfuel","power","torque"]
    for (i,field) in fields.enumerated() { number("dft_"+field,Double(-i-1)) }
    vars["speedunit"] = .string(unit == "mph" ? "MPH" : unit); vars["inputname"] = .string(timeline.inputName ?? data?.title ?? ""); vars["locname"] = .string(data?.locationName ?? "")
    let drawing = ScriptDrawing(context:canvas,font:payload.utf16(432,128),data:data,time:time,unit:unit)
    drawing.message = message
    let machine = ScriptMachine(variables:vars) { name,args in try drawing.call(name,args) }
    func frameValues(_ sample: Double) -> [String:ScriptValue] {
      let sampleValue = channelValue(channel,data:data,time:sample,unit:unit,interpolate:o.kind != .gear)
      return ["datavalue":.number(sampleValue),"datafactor":.number((sampleValue-minimum)/range),
        "istriggered":.number(payload[284] & 1 != 0 && sampleValue >= trigger ? 1 : 0),
        "sampletime":.number(sample),"displaytime":.number(timeline.displayTime(at:sample)),"frameinterval":.number(timeline.frameInterval)]
    }
    func drawLabel() {
      guard payload[569] != 0 else { return }
      let label = payload.utf16(128,128)
      let x = Double(payload.u32(296) & 0xffff),y = Double(payload.u32(296) >> 16)
      LegacyStyledRenderer.label(canvas,label,font:payload.utf16(304,128),size:payload.f32(560),
        color:LegacyStyledRenderer.rgb(payload.u32(288)),x:x,y:y-payload.f32(560),
        bold:payload[568] & 1 != 0,italic:payload[568] & 2 != 0)
    }
    do {
      machine.variables.merge(frameValues(time)) { _,new in new }
      if payload[284] & 4 != 0 {
        guard timeline.sourceStart.isFinite,timeline.sourceStep.isFinite,timeline.sourceStep > 0 else { throw RaceError.invalid("Invalid Enhanced history timing.") }
        let position = max(0,(time-timeline.sourceStart)/timeline.sourceStep)
        guard position.isFinite,position <= 1_000_000 else { throw RaceError.invalid("Enhanced history exceeds the replay limit.") }
        let frame = Int(floor(position+0.000001))
        let dataKey = data.map { String(describing:ObjectIdentifier($0))+":"+String($0.renderRevision) } ?? "none"
        let timingKey = [timeline.sourceStart,timeline.sourceStep,timeline.displayStart,timeline.frameInterval,minimum,maximum].map { String($0.bitPattern) }.joined(separator:":")
        let context = Data(((timeline.inputName ?? data?.title ?? "")+"\0"+(data?.locationName ?? "")).utf8).base64EncodedString()
        let cacheKey = "\(o.id)|\(ObjectIdentifier(program))|\(dataKey)|\(channel)|\(unit)|\(timingKey)|\(context)" as NSString
        historyLock.lock()
        let history: EnhancedHistory
        if let cached = histories.object(forKey:cacheKey) { history = cached;historyLock.unlock() }
        else {
          do {
            drawing.time = timeline.sourceStart
            machine.variables.merge(frameValues(timeline.sourceStart)) { _,new in new }
            try machine.run(program.background)
            if payload[284] & 2 == 0 { drawLabel() }
            guard let background = canvas.makeImage() else { throw RaceError.invalid("Cannot create Enhanced background.") }
            history = EnhancedHistory(program:program,background:background,telemetry:data,initial:EnhancedState(variables:machine.variables,outline:drawing.outline))
            histories.setObject(history,forKey:cacheKey);historyLock.unlock()
          } catch { historyLock.unlock();throw error }
        }
        canvas.clear(CGRect(x:0,y:0,width:width,height:height))
        canvas.draw(history.background,in:CGRect(x:0,y:0,width:width,height:height))
        _ = try history.render(frame:frame,drawing:drawing) { index in frameValues(timeline.sourceStart+Double(index)*timeline.sourceStep) }
        if payload[284] & 2 != 0 { drawLabel() }
        guard let image = canvas.makeImage() else { return false }
        c.draw(image,in:rect);return true
      }
      try machine.run(program.background)
      if payload[284] & 2 == 0 { drawLabel() }
      machine.stopped = false; try machine.run(program.foreground)
      if payload[284] & 2 != 0 { drawLabel() }
      guard let image = canvas.makeImage() else { return false }
      c.draw(image,in:rect); return true
    } catch { failure?(error.localizedDescription);return false }
  }
  static func defaultChannel(_ o: DisplayObject) -> String {
    o.automaticChannel
  }
  static func resolveChannel(_ raw: String,fallback: String) -> String {
    switch raw.lowercased().filter({ $0.isLetter || $0.isNumber }) {
    case "speed":return "speed"
    case "accelx","gforcex":return "gx"
    case "accely","gforcey":return "gy"
    case "rpm":return "rpm"
    case "gear":return "gear"
    case "throttle":return "throttle"
    case "brake":return "brake"
    case "coolant","coolanttemperature":return "coolant"
    case "oil","oiltemperature","engineoiltemperature":return "oil"
    case "intake","intaketemperature","intakeairtemperature":return "intake"
    case "heading":return "heading"
    case "posx":return "lon"
    case "posy":return "lat"
    case "", "automatic":return fallback
    default:return raw
    }
  }
  static func channelValue(_ channel: String,data: Telemetry?,time: Double,unit: String,interpolate: Bool = true) -> Double {
    channel == "speed" ? data?.speed(at:time,unit:unit) ?? 0 : data?.value(channel,at:time,interpolate:interpolate) ?? 0
  }
  static func channelBounds(_ channel: String,data: Telemetry?,unit: String) -> (Double,Double)? {
    guard let data,let bounds = data.bounds(channel) else { return nil }
    guard channel == "speed",let index = data.channelIndex(channel) else { return bounds }
    let header = data.headers[index].lowercased()
    let toMeters = header.contains("mph") ? 1/2.2369362921 : (header.contains("knot") ? 0.514444 : (header.contains("km") || header == "kph" ? 1/3.6 : 1))
    let fromMeters = unit == "mph" ? 2.2369362921 : (unit == "km/h" ? 3.6 : (unit == "knots" ? 1.94384449 : 1))
    return (bounds.0*toMeters*fromMeters,bounds.1*toMeters*fromMeters)
  }
}

struct EnhancedTimeline {
  var sourceStart: Double = 0
  var sourceStep: Double = 1.0/30
  var displayStart: Double = 0
  var frameInterval: Double = 1.0/30
  var inputName:String?
  func displayTime(at sample: Double) -> Double { displayStart+(sample-sourceStart)*frameInterval/sourceStep }
}

final class ScriptDrawing {
  private static let stringArguments:[String:Set<Int>] = ["drawtext":[0],"getdataindex":[0],"substr":[0],"strlen":[0],"toupper":[0],"tolower":[0],"trim":[0],"asc":[0]]
  let c: CGContext
  let font: String
  let data: Telemetry?
  var time: Double
  let unit: String
  var outline: Double = -1
  var renders = true
  var message:((String)->Void)?
  init(context: CGContext,font: String,data: Telemetry?,time: Double,unit: String) {
    c = context; self.font = font; self.data = data; self.time = time; self.unit = unit
  }
  func color(_ value: Double) -> CGColor {
    let v = UInt32(truncatingIfNeeded:ScriptMachine.int(value))
    return CGColor(colorSpace:OverlayRenderer.colorSpace,components:[Double((v>>16)&255)/255,
      Double((v>>8)&255)/255,Double(v&255)/255,value < 0 ? 0 : 1])!
  }
  func text(_ text: String,x: Double,y: Double,color value: Double,size: Double,alignment: Double) {
    guard size.isFinite,size > 0,size < 4096,x.isFinite,y.isFinite else { return }
    let f = NSFont(name:font,size:size) ?? NSFont(name:"Arial",size:size) ?? NSFont.systemFont(ofSize:size)
    var attributes: [NSAttributedString.Key:Any] = [.font:f,.foregroundColor:NSColor(cgColor:color(value)) ?? .white]
    if outline >= 0 { attributes[.strokeColor] = NSColor(cgColor:color(outline)); attributes[.strokeWidth] = -2 }
    let string = NSAttributedString(string:String(text.prefix(4096)),attributes:attributes)
    let align = alignment == 1 ? 0.5 : (alignment == 2 ? 1.0 : 0)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:false)
    string.draw(at:CGPoint(x:x-string.size().width*align,y:y == 0 ? 0 : y-string.size().height))
    NSGraphicsContext.restoreGraphicsState()
  }
  func call(_ name: String,_ args: [ScriptValue]) throws -> ScriptValue {
    if name != "print" {
      let strings = Self.stringArguments[name] ?? []
      for (index,value) in args.enumerated() {
        switch value {
        case .string where !strings.contains(index):throw RaceError.invalid("\(name) parameter \(index+1) needs a number.")
        case .number where strings.contains(index):throw RaceError.invalid("\(name) parameter \(index+1) needs a string.")
        default:break
        }
      }
    }
    if !renders && name.hasPrefix("draw") { return .number(0) }
    func n(_ i: Int,_ fallback: Double = 0) -> Double { args.indices.contains(i) ? args[i].number : fallback }
    func s(_ i: Int) -> String { args.indices.contains(i) ? args[i].string : "" }
    func result(_ value: Double) -> ScriptValue { .number(value) }
    if name.hasPrefix("draw"), args.contains(where:{ if case .number(let v) = $0 { return !v.isFinite || abs(v) > 1e9 }; return false }) { return .number(0) }
    switch name {
    case "print": if renders {message?(String(args.map(\.string).joined(separator:" ").prefix(2048)))};return .number(0)
    case "settextoutline": outline = n(0)
    case "drawnumber": text(n(0).isFinite ? String(format:"%.*f",max(0,min(8,ScriptMachine.int(n(1)))),n(0)) : "—",x:n(2),y:n(3),color:n(4),size:n(5),alignment:n(6))
    case "drawtext": text(s(0),x:n(1),y:n(2),color:n(3),size:n(4),alignment:n(5))
    case "drawchar": text(String(UnicodeScalar(max(0,min(127,ScriptMachine.int(n(0)))))!),x:n(1),y:n(2),color:n(3),size:n(4),alignment:n(5))
    case "drawtime": text(ScriptTimeFormat.string(n(0),decimals:ScriptMachine.int(n(1)),compact:ScriptMachine.int(n(7))),x:n(2),y:n(3),color:n(4),size:n(5),alignment:n(6))
    case "drawdot","drawsquare","drawcircle":
      let circle = name == "drawcircle", radius = max(0,min(4096,n(circle ? 2 : 3)))
      c.setFillColor(color(n(circle ? 3 : 2))); c.setStrokeColor(color(n(circle ? 3 : 2)))
      let r = CGRect(x:n(0)-radius,y:n(1)-radius,width:radius*2,height:radius*2)
      if name == "drawsquare" { c.fill(r) }
      else if circle && n(4) > 0 { c.setLineWidth(n(4)*2); c.strokeEllipse(in:r) }
      else { c.fillEllipse(in:r) }
    case "drawline","drawlineflat":
      c.setStrokeColor(color(n(4))); c.setLineWidth(max(0,min(4096,n(5)))*2)
      c.setLineCap(name == "drawlineflat" ? .butt : .round)
      c.move(to:CGPoint(x:n(0),y:n(1))); c.addLine(to:CGPoint(x:n(2),y:n(3))); c.strokePath()
    case "drawlinegradient","drawlinegradientrgb","drawcurve","drawcurvergb":
      let curved = name.hasPrefix("drawcurve")
      let limit = curved ? max(0,min(1,n(6))) : 1
      let colorA = curved ? n(7) : n(4),colorB = curved ? n(8) : n(5)
      let widthA = curved ? n(9) : n(6),widthB = curved ? n(10) : n(6)
      func point(_ t: Double) -> CGPoint {
        if curved { return CGPoint(x:(1-t)*(1-t)*n(0)+2*(1-t)*t*n(2)+t*t*n(4),y:(1-t)*(1-t)*n(1)+2*(1-t)*t*n(3)+t*t*n(5)) }
        return CGPoint(x:n(0)+(n(2)-n(0))*t,y:n(1)+(n(3)-n(1))*t)
      }
      c.setLineCap(.round)
      for i in 0..<96 {
        let a = Double(i)/96*limit,b = Double(i+1)/96*limit
        let blended = try call(name.hasSuffix("rgb") ? "blendcolorsrgb" : "blendcolors",[.number(colorA),.number(colorB),.number(a)])
        c.setStrokeColor(color(blended.number));c.setLineWidth(max(0,min(4096,widthA+(widthB-widthA)*a))*2)
        c.move(to:point(a));c.addLine(to:point(b));c.strokePath()
      }
    case "drawrect","drawrrect","draworect":
      let r = CGRect(x:min(n(0),n(2)),y:min(n(1),n(3)),width:abs(n(2)-n(0)),height:abs(n(3)-n(1)))
      let radius = name == "drawrrect" ? min(r.width,r.height)*0.08 : min(r.width,r.height)/2
      let path = name == "drawrect" ? CGPath(rect:r,transform:nil) : CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil)
      c.addPath(path); c.setFillColor(color(n(4))); c.setStrokeColor(color(n(4)))
      if n(5) <= 0 { c.fillPath() } else { c.setLineWidth(max(0,min(4096,n(5)))*2); c.strokePath() }
    case "drawpoly3","drawpoly4":
      let count = name == "drawpoly3" ? 3 : 4
      c.beginPath(); c.move(to:CGPoint(x:n(0),y:n(1)))
      for i in 1..<count { c.addLine(to:CGPoint(x:n(i*2),y:n(i*2+1))) }; c.closePath()
      c.setFillColor(color(n(count*2))); c.setStrokeColor(color(n(count*2)))
      if n(count*2+1) <= 0 { c.fillPath() } else { c.setLineWidth(max(0,min(4096,n(count*2+1)))*2); c.strokePath() }
    case "drawdotgradient","drawdotgradientrgb":
      let radius = max(0,min(4096,n(4)))
      var colors = [color(n(2)),color(n(3))],locations: [CGFloat] = [0,1]
      if name.hasSuffix("rgb") {
        let middle = try call("blendcolorsrgb",[.number(n(2)),.number(n(3)),.number(0.5)])
        colors.insert(color(middle.number),at:1);locations = [0,0.5,1]
      }
      if let gradient = CGGradient(colorsSpace:OverlayRenderer.colorSpace,colors:colors as CFArray,locations:locations) {
        c.saveGState();c.addEllipse(in:CGRect(x:n(0)-radius,y:n(1)-radius,width:radius*2,height:radius*2));c.clip()
        c.drawRadialGradient(gradient,startCenter:CGPoint(x:n(0),y:n(1)),startRadius:0,endCenter:CGPoint(x:n(0),y:n(1)),endRadius:radius,options:[]);c.restoreGState()
      }
    case "blendcolors","blendcolorsrgb":
      let a = UInt32(truncatingIfNeeded:ScriptMachine.int(n(0))), b = UInt32(truncatingIfNeeded:ScriptMachine.int(n(1)))
      let t = max(0,min(1,n(2))); var value: UInt32 = 0
      for shift in [0,8,16] {
        let x = Double((a>>shift)&255),y = Double((b>>shift)&255)
        let blended = name == "blendcolorsrgb" ? x*min(1,(1-t)*2)+y*min(1,t*2) : x+(y-x)*t
        value |= UInt32(max(0,min(255,blended))) << shift
      }
      return result(Double(value))
    case "getdataindex": return result(Double(data?.channelIndex(s(0)) ?? -1000))
    case "getdatavalue":
      let index = ScriptMachine.int(n(0))
      let keys = ["lon","lat","altitude","speed","heading","gx","gy","throttle","brake","rpm","gear","airfuel","power","torque"]
      let key = index < 0 && -index <= keys.count ? keys[-index-1] : (data?.headers.indices.contains(index) == true ? data!.headers[index] : "")
      return result(key == "speed" ? data?.speed(at:time,unit:unit) ?? .nan : data?.value(key,at:time) ?? .nan)
    case "getcurlapnum": return result(Double(data?.lap(at:time)?.number ?? 0))
    case "getcurlaptime": return result(data?.lap(at:time).map { time-$0.start } ?? 0)
    case "getbestlapnum": return result(Double(data?.bestLap?.number ?? 0))
    case "getbestlaptime": return result(data?.bestLap?.duration ?? 0)
    case "getcurbestlapnum": return result(Double(data?.bestLap(at:time)?.number ?? 0))
    case "getcurbestlaptime": return result(data?.bestLap(at:time)?.duration ?? 0)
    case "getprevbestlapnum": return result(Double(data?.previousBestLap(at:time)?.number ?? 0))
    case "getprevbestlaptime": return result(data?.previousBestLap(at:time)?.duration ?? 0)
    case "getlaptime": return result(data?.laps.first { $0.complete && $0.number == ScriptMachine.int(n(0)) }?.duration ?? 0)
    case "formatnumber": return .string(String(format:"%.*f",max(0,min(8,ScriptMachine.int(n(1)))),n(0)))
    case "formatheading":
      let headings = ["N","NE","E","SE","S","SW","W","NW"]
      let degrees = n(0).truncatingRemainder(dividingBy:360)
      return .string(headings[((ScriptMachine.int((degrees+360+22.5)/45))%8)])
    case "substr":
      let text = Array(s(0));let start = ScriptMachine.int(n(1));let length = ScriptMachine.int(n(2))
      guard start >= 0,start < text.count else { return .string("") }
      return .string(String(text[start..<min(text.count,start+(length < 0 ? text.count-start : length))]))
    case "strlen": return result(Double(s(0).count))
    case "toupper": return .string(s(0).uppercased())
    case "tolower": return .string(s(0).lowercased())
    case "trim": return .string(s(0).trimmingCharacters(in:.whitespacesAndNewlines))
    case "chr": return .string(String(UnicodeScalar(max(0,min(127,ScriptMachine.int(n(0)))))!))
    case "asc": return result(Double(s(0).utf8.first ?? 0))
    case "strobe": return result(n(0) > 0 && time.isFinite ? Double(ScriptMachine.int(time/max(0.001,n(0))) % 2) : 0)
    case "abs":return result(abs(n(0)))
    case "ceil":return result(ceil(n(0)))
    case "floor":return result(floor(n(0)))
    case "max":return result(max(n(0),n(1)))
    case "min":return result(min(n(0),n(1)))
    case "pow":return result(pow(n(0),n(1)))
    case "sqrt":return result(sqrt(n(0)))
    case "trunc":return result(n(0).rounded(.towardZero))
    case "round": let scale = pow(10,max(-8,min(8,n(1))));return result((n(0)*scale).rounded()/scale)
    case "sin":return result(sin(n(0) * .pi/180))
    case "cos":return result(cos(n(0) * .pi/180))
    case "tan":return result(tan(n(0) * .pi/180))
    case "asin":return result(asin(n(0))*180 / .pi)
    case "acos":return result(acos(n(0))*180 / .pi)
    case "atan":return result(atan(n(0))*180 / .pi)
    case "atan2":return result(atan2(n(1),n(0))*180 / .pi)
    case "hypot":return result(hypot(n(0),n(1)))
    default: throw RaceError.invalid("Unsupported Enhanced function: \(name)")
    }
    return .number(0)
  }
}
