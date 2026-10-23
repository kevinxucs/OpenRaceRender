import AppKit

/// Honor traditional widget styling from the imported payload instead of applying the native theme.
enum LegacyStyledRenderer {
  static func rgb(_ value: UInt32) -> CGColor { OverlayRenderer.color(String(format:"#%06X",value & 0xffffff)) }
  static func label(_ c: CGContext,_ value: String,font: String,size: Double,color: CGColor,x: Double,y: Double,center: Bool = true) {
    guard size > 0,size.isFinite else { return }
    let face = font == "Microsoft Sans Serif" ? "Arial" : font
    let f = NSFont(name:face,size:size) ?? NSFont(name:"Arial",size:size) ?? NSFont.systemFont(ofSize:size)
    let string = NSAttributedString(string:value,attributes:[.font:f,.foregroundColor:NSColor(cgColor:color) ?? .white])
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:false)
    string.draw(at:CGPoint(x:x-(center ? string.size().width/2 : 0),y:y))
    NSGraphicsContext.restoreGraphicsState()
  }
  static func draw(_ c: CGContext,object o: DisplayObject,rect r: CGRect,data: Telemetry?,time: Double,unit: String,canvasHeight: Double) -> Bool {
    guard let d = o.legacyPayload,let type = o.legacyType else { return false }
    let scale = canvasHeight/480
    if type == 30,d.count >= 640 {
      let common = o.legacyCommon
      // Styles store their own raster dimensions, independent of project percentages.
      let designWidth = Double((common?.u32(296) ?? 0) & 0xffff)
      let designHeight = Double((common?.u32(296) ?? 0) >> 16)
      let fontScale = designWidth > 0 && designHeight > 0
        ? min(r.width/designWidth,r.height/designHeight)*4/3 : scale
      gauge(c,object:o,data:data,time:time,unit:unit,rect:r,scale:fontScale,payload:d); return true
    }
    if [76,77,32].contains(type),d.count >= 656 {
      let lap = data?.lap(at:time), best = data?.bestLap
      var value = "—",prefix = d.utf16(4,512)
      if prefix == "Text" { prefix = "" }
      switch o.kind {
      case .lap:value = lap.map { String($0.number) } ?? "—"
      case .bestLap:value = best.map { String($0.number) } ?? "—"
      case .timer:value = lap.map { compactTime(time-$0.start) } ?? "—"
      case .bestTime:value = best.map { compactTime($0.duration) } ?? "—"
      case .delta:value = data?.delta(at:time).map { String(format:"%+.3f",$0) } ?? "—"
      default:value = data?.value(o.channel,at:time).map { String(format:"%.0f",$0) } ?? "—"
      }
      let size = min(r.height*0.85,max(8,d.f32(644)*scale))
      label(c,prefix+value,font:d.utf16(516,128),size:size,color:rgb(d.u32(0)),x:r.minX,y:r.minY,center:false)
      return true
    }
    if type == 31,d.count >= 640 {
      let value = data?.value(o.channel.isEmpty ? "throttle" : o.channel,at:time)
      let fraction = max(0,min(1,((value ?? 0)-o.minimum)/max(1,o.maximum-o.minimum)))
      c.setFillColor(rgb(d.u32(316))); c.fill(r)
      let filled = CGRect(x:r.minX,y:r.minY,width:r.width*fraction,height:r.height)
      if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[rgb(d.u32(304)),rgb(d.u32(308))] as CFArray,locations:[0,1]) {
        c.saveGState(); c.clip(to:filled); c.drawLinearGradient(gradient,start:CGPoint(x:r.minX,y:r.midY),end:CGPoint(x:r.maxX,y:r.midY),options:[]); c.restoreGState()
      }
      let size = min(r.height*0.7,max(8,d.f32(608)*scale))
      label(c,d.utf16(128,128),font:d.utf16(352,128),size:size,color:rgb(d.u32(328)),x:r.midX,y:r.midY-size*0.5)
      return true
    }
    if type == 74,d.count >= 440 {
      let radius = min(r.width,r.height)*0.46
      c.setFillColor(rgb(d.u32(280)));
      c.fillEllipse(in:CGRect(x:r.midX-radius,y:r.midY-radius,width:radius*2,height:radius*2))
      c.setStrokeColor(rgb(d.u32(268)));c.setLineWidth(max(1,radius*0.01))
      for factor in [0.33,0.66,1.0] { c.strokeEllipse(in:CGRect(x:r.midX-radius*factor,y:r.midY-radius*factor,width:radius*factor*2,height:radius*factor*2)) }
      c.move(to:CGPoint(x:r.midX-radius,y:r.midY));c.addLine(to:CGPoint(x:r.midX+radius,y:r.midY));c.move(to:CGPoint(x:r.midX,y:r.midY-radius));c.addLine(to:CGPoint(x:r.midX,y:r.midY+radius));c.strokePath()
      let gx = data?.value("gx",at:time) ?? 0,gy = data?.value("gy",at:time) ?? 0
      let x = r.midX+max(-1,min(1,gy/max(0.1,d.f32(260))))*radius
      let y = r.midY+max(-1,min(1,gx/max(0.1,d.f32(256))))*radius
      c.setFillColor(rgb(d.u32(264)));c.fillEllipse(in:CGRect(x:x-radius*0.055,y:y-radius*0.055,width:radius*0.11,height:radius*0.11))
      label(c,String(format:"%.2f G",hypot(gx,gy)),font:d.utf16(288,128),size:radius*0.23,color:rgb(d.u32(416)),x:r.midX,y:r.minY)
      return true
    }
    return false
  }
  static func compactTime(_ time: Double) -> String {
    guard time.isFinite,time >= 0,time < 1e8 else { return "—" }
    return String(format:"%d:%06.3f",Int(time)/60,time.truncatingRemainder(dividingBy:60))
  }
  static func gauge(_ c: CGContext,object o: DisplayObject,data: Telemetry?,time: Double,unit: String,rect r: CGRect,scale: Double,payload d: Data) {
    let g = o.gauge ?? GaugeSettings(),radius = min(r.width,r.height)*0.48
    let range = max(0.00001,o.maximum-o.minimum)
    let value = o.kind == .speed ? data?.speed(at:time,unit:unit,channel:o.channel.isEmpty ? "speed" : o.channel) : data?.value(o.channel.isEmpty ? "rpm" : o.channel,at:time)
    func point(_ factor: Double,_ distance: Double) -> CGPoint {
      let angle = (g.rotation-90+(g.counterClockwise ? -1 : 1)*factor*g.sweep) * .pi/180
      return CGPoint(x:r.midX+cos(angle)*distance,y:r.midY+sin(angle)*distance)
    }
    if g.showFace {
      c.setFillColor(rgb(d.u32(300)));c.fillEllipse(in:CGRect(x:r.midX-radius,y:r.midY-radius,width:radius*2,height:radius*2))
    }
    let interval = max(range/40,g.tickInterval ?? range/8)
    let ticks = max(1,Int(min(40,floor(range/interval))))
    let fontSize = min(radius*0.2,max(5,d.f32(608)*scale))
    let minorInterval = d.f64(280)
    if minorInterval.isFinite,minorInterval > 0,minorInterval < interval {
      let minorTicks = min(200,Int(min(200,floor(range/minorInterval))))
      for i in 0...minorTicks {
        let f = Double(i)*minorInterval/range
        c.setStrokeColor(rgb(d.u32(320)));c.setLineWidth(max(0.5,radius*0.004))
        c.move(to:point(f,radius*0.89));c.addLine(to:point(f,radius*0.96));c.strokePath()
      }
    }
    var labelBounds: [CGRect] = []
    for i in 0...ticks {
      let number = o.minimum+Double(i)*interval,f = (number-o.minimum)/range
      c.setStrokeColor(rgb(d.u32(316))); c.setLineWidth(max(1,radius*0.008));c.move(to:point(f,radius*0.82));c.addLine(to:point(f,radius*0.96));c.strokePath()
      if g.showLabels {
        let p = point(f,radius*0.68)
        let text = String(format:"%.0f",number/max(0.00001,g.numberingScale))
        let bounds = CGRect(x:p.x-Double(text.count)*fontSize*0.35,y:p.y-fontSize*0.6,width:Double(text.count)*fontSize*0.7,height:fontSize*1.2)
        if !labelBounds.contains(where: { $0.intersects(bounds) }) {
          label(c,text,font:d.utf16(352,128),size:fontSize,color:rgb(d.u32(332)),x:p.x,y:p.y-fontSize*0.5)
          labelBounds.append(bounds)
        }
      }
    }
    if let value,value.isFinite {
      let f = max(0,min(1,(value-o.minimum)/range)),tip = point(f,radius*0.84)
      c.setStrokeColor(OverlayRenderer.color(o.color));c.setLineWidth(max(1,radius*0.025));c.setLineCap(.round);c.move(to:CGPoint(x:r.midX,y:r.midY));c.addLine(to:tip);c.strokePath()
    }
    if g.showNumber {
      let size = min(radius*0.55,max(8,d.f32(612)*scale))
      let p = textPosition(d,common:o.legacyCommon,offset:348,rect:r,fallback:CGPoint(x:r.midX,y:r.midY))
      label(c,value.map { String(format:"%.*f",max(0,min(6,g.decimals)),$0) } ?? "—",font:d.utf16(480,128),size:size,color:rgb(d.u32(336)),x:p.x,y:p.y-size)
    }
    if g.showLabels {
      let title = o.kind == .speed && !g.label.lowercased().contains(unit.lowercased()) ? g.label+" ("+unit.uppercased()+")" : g.label
      let p = textPosition(d,common:o.legacyCommon,offset:344,rect:r,fallback:CGPoint(x:r.midX,y:r.midY+radius*0.3))
      label(c,title,font:d.utf16(352,128),size:fontSize,color:rgb(d.u32(332)),x:p.x,y:p.y-fontSize)
    }
  }
  static func textPosition(_ d: Data,common: Data?,offset: Int,rect r: CGRect,fallback: CGPoint) -> CGPoint {
    let x = Int(d[offset]) | Int(d[offset+1]) << 8
    let y = Int(d[offset+2]) | Int(d[offset+3]) << 8
    guard x > 0,y > 0,x < 4096,y < 4096 else { return fallback }
    let width = Double((common?.u32(296) ?? 0) & 0xffff)/2
    let height = Double((common?.u32(296) ?? 0) >> 16)/2
    guard width > 0,height > 0 else { return fallback }
    return CGPoint(x:r.minX+Double(x)*r.width/width,y:r.minY+Double(y)*r.height/height)
  }
}
