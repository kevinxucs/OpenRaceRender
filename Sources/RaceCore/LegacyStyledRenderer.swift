import AppKit

/// Honor traditional widget styling from the imported payload instead of applying the native theme.
enum LegacyStyledRenderer {
  static func contentRect(_ o: DisplayObject,in rect: CGRect) -> CGRect {
    guard let common = o.legacyCommon,common.count >= 300,common[285] != 0 else { return rect }
    let width = Double(common.u32(296) & 0xffff),height = Double(common.u32(296) >> 16)
    guard width > 0,height > 0 else { return rect }
    // Legacy raster targets round their allocated pixel size up before fitting
    // the bitmap. At small sizes (for example a 14.4 px banner) this matters.
    let scale = min(ceil(rect.width)/width,ceil(rect.height)/height)
    let size = CGSize(width:ceil(width*scale),height:ceil(height*scale))
    return CGRect(x:floor(rect.midX-size.width/2),y:floor(rect.midY-size.height/2),width:size.width,height:size.height)
  }
  static func rgb(_ value: UInt32) -> CGColor { OverlayRenderer.color(String(format:"#%06X",value & 0xffffff)) }
  static func label(_ c: CGContext,_ value: String,font: String,size: Double,color: CGColor,x: Double,y: Double,center: Bool = true,bold: Bool = false,italic: Bool = false,outline: CGColor? = nil) {
    guard size > 0,size < 4096,size.isFinite,x.isFinite,y.isFinite else { return }
    var f = NSFont(name:font,size:size) ?? NSFont(name:"Arial",size:size) ?? NSFont.systemFont(ofSize:size)
    if bold { f = NSFontManager.shared.convert(f,toHaveTrait:.boldFontMask) }
    if italic { f = NSFontManager.shared.convert(f,toHaveTrait:.italicFontMask) }
    var attributes: [NSAttributedString.Key:Any] = [.font:f,.foregroundColor:NSColor(cgColor:color) ?? .white]
    let string = NSAttributedString(string:value,attributes:attributes)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:false)
    let point = CGPoint(x:x-(center ? string.size().width/2 : 0),y:y)
    if let outline {
      attributes[.strokeColor] = NSColor(cgColor:outline);attributes[.strokeWidth] = 8
      NSAttributedString(string:value,attributes:attributes).draw(at:point)
    }
    string.draw(at:point)
    NSGraphicsContext.restoreGraphicsState()
  }
  static func draw(_ c: CGContext,object o: DisplayObject,rect r: CGRect,data: Telemetry?,time: Double,unit: String,canvasHeight: Double) -> Bool {
    guard let type = o.legacyType,[30,31,32,74,76,77].contains(type) else { return false }
    let dimensions = o.legacyCommon?.u32(296) ?? 0
    let width = Int(dimensions & 0xffff),height = Int(dimensions >> 16)
    guard width > 0,height > 0,width <= 2048,height <= 2048 else {
      return drawContent(c,object:o,rect:r,data:data,time:time,unit:unit,canvasHeight:canvasHeight)
    }
    guard let bitmap = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
      space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo) else { return false }
    let area = CGRect(x:0,y:0,width:width,height:height)
    guard drawContent(bitmap,object:o,rect:area,data:data,time:time,unit:unit,canvasHeight:canvasHeight*Double(height)/max(1,r.height)),
      let image = bitmap.makeImage() else { return false }
    c.interpolationQuality = .high;c.draw(image,in:r);return true
  }
  static func drawContent(_ c: CGContext,object o: DisplayObject,rect r: CGRect,data: Telemetry?,time: Double,unit: String,canvasHeight: Double) -> Bool {
    guard let d = o.legacyPayload,let type = o.legacyType else { return false }
    let scale = canvasHeight/480
    if type == 30,d.count >= 640 {
      let common = o.legacyCommon
      // Styles store their own raster dimensions, independent of project percentages.
      let designWidth = Double((common?.u32(296) ?? 0) & 0xffff)
      let designHeight = Double((common?.u32(296) ?? 0) >> 16)
      let fontScale = designWidth > 0 && designHeight > 0
        ? min(r.width/designWidth,r.height/designHeight)*2 : scale
      gauge(c,object:o,data:data,time:time,unit:unit,rect:r,scale:fontScale,payload:d); return true
    }
    if [76,77,32].contains(type),d.count >= 656 {
      let lap = data?.lap(at:time), best = data?.bestLap(at:time)
      var value = "—",prefix = d.utf16(4,512)
      if prefix == "Text" { prefix = "" }
      switch o.kind {
      case .lap:value = String(lap?.number ?? 0)
      case .bestLap:value = String(best?.number ?? 0)
      case .timer:value = compactTime(lap.map { time-$0.start } ?? 0)
      case .bestTime:value = compactTime(best?.duration ?? 0)
      case .delta:value = compactTime(data?.delta(at:time,reference:best) ?? 0)
      default:value = data?.value(o.resolvedChannel,at:time,interpolate:o.kind != .gear).map { String(format:"%.0f",$0) } ?? "—"
      }
      if type == 77,d[652] == 1 { prefix = "" }
      let size = min(r.height*0.85,max(8,d.f32(644)*scale))
      let alignment = d[649]
      let x = alignment == 1 ? r.midX : r.minX
      let face = d.utf16(516,128)
      // The native macOS Arial text reference remains regular even with its
      // saved Bold flag set. Other families retain their explicit traits.
      let synthesizeBold = face.caseInsensitiveCompare("Arial") != .orderedSame
      label(c,prefix+value,font:face,size:size,color:rgb(d.u32(0)),x:x,y:r.minY+size*0.125,center:alignment == 1,
        bold:synthesizeBold && d[648] & 1 != 0,italic:d[648] & 2 != 0,outline:d[651] != 0 ? rgb(d.u32(640)) : nil)
      return true
    }
    if type == 31,d.count >= 640 {
      let channel = o.resolvedChannel
      let value = data?.value(channel,at:time)
      let bounds = data?.bounds(channel)
      let rawMinimum = d.f64(256),rawMaximum = d.f64(264)
      let minimum = abs(rawMinimum) >= 9e7 ? bounds?.0 ?? o.minimum : rawMinimum
      let maximum = abs(rawMaximum) >= 9e7 ? bounds?.1 ?? o.maximum : rawMaximum
      let fraction = max(0,min(1,((value ?? minimum)-minimum)/max(0.00001,maximum-minimum)))
      let horizontal = r.width >= r.height
      let rasterWidth = Double((o.legacyCommon?.u32(296) ?? 0) & 0xffff)
      let objectScale = rasterWidth > 0 ? r.width*2/rasterWidth : scale
      let trim = max(0,min(min(r.width,r.height)/4,Double(d[621])*objectScale))
      let rounded = d[618] & 0x20 != 0
      let outer = r.insetBy(dx:trim/2,dy:trim/2)
      let beveled = rounded && trim > 0 && d.u32(316) >> 24 != 255
      let bevel = min(trim*2,max(0,min(outer.width,outer.height)/4))
      let area = beveled ? outer.insetBy(dx:bevel,dy:bevel) : outer
      if beveled {
        c.setFillColor(shaded(d.u32(316),factor:0.72))
        let corner = min(outer.width,outer.height)/2
        c.addPath(CGPath(roundedRect:outer,cornerWidth:corner,cornerHeight:corner,transform:nil));c.fillPath()
      }
      let radius = rounded ? min(area.width,area.height)/2 : 0
      let path = CGPath(roundedRect:area,cornerWidth:radius,cornerHeight:radius,transform:nil)
      if d.u32(304) >> 24 != 255 {
        barGradient(c,path:path,rect:area,first:d.u32(304),second:d.u32(636),horizontal:!horizontal,rounded:rounded)
      }
      c.saveGState();c.addPath(path);c.clip()
      let filled = CGRect(x:area.minX,y:area.minY,width:area.width*(horizontal ? fraction : 1),height:area.height*(horizontal ? 1 : fraction))
      c.clip(to:filled)
      barGradient(c,path:path,rect:area,first:d.u32(308),second:d.u32(632),horizontal:!horizontal,rounded:rounded)
      c.restoreGState()
      if d.u32(316) >> 24 != 255 { c.setStrokeColor(rgb(d.u32(beveled ? 312 : 316)));c.setLineWidth(trim);c.addPath(path);c.strokePath() }
      let size = min(r.height*0.8,max(5,d.f32(608)*objectScale))
      if d.u32(332) >> 24 != 255 {
        let text = d.utf16(128,128),face = d.utf16(352,128)
        let font = NSFont(name:face,size:size) ?? NSFont(name:"Arial",size:size) ?? NSFont.systemFont(ofSize:size)
        let textWidth = NSAttributedString(string:text,attributes:[.font:font]).size().width
        let position = Double(d[340])/100
        let x = horizontal
          ? (d[340] == 255 ? outer.maxX-outer.height/2-textWidth/2 : outer.minX+(outer.width-textWidth)*position+textWidth/2)
          : r.midX
        label(c,text,font:face,size:size,color:rgb(d.u32(332)),x:x,y:r.midY-size*0.55)
      }
      return true
    }
    if type == 74,d.count >= 440 {
      let radius = min(r.width,r.height)*0.46
      let objectScale = min(r.width,r.height)/432
      let circle = CGRect(x:r.midX-radius,y:r.midY-radius,width:radius*2,height:radius*2)
      if d.u32(280) >> 24 != 255 { gradient(c,path:CGPath(ellipseIn:circle,transform:nil),rect:circle,first:d.u32(280),second:d.u32(284),horizontal:false) }
      c.setStrokeColor(rgb(d.u32(268)));c.setLineWidth(max(0.5,Double(d[278])*objectScale))
      for factor in [1.0/3,2.0/3,1.0] { c.strokeEllipse(in:CGRect(x:r.midX-radius*factor,y:r.midY-radius*factor,width:radius*factor*2,height:radius*factor*2)) }
      c.move(to:CGPoint(x:r.midX-radius,y:r.midY));c.addLine(to:CGPoint(x:r.midX+radius,y:r.midY));c.move(to:CGPoint(x:r.midX,y:r.midY-radius));c.addLine(to:CGPoint(x:r.midX,y:r.midY+radius));c.strokePath()
      let lateralField = d.utf16(0,128),longitudinalField = d.utf16(128,128)
      let gy = data?.value(lateralField.isEmpty ? "gy" : lateralField,at:time) ?? 0
      let gx = longitudinalField.isEmpty
        ? data?.value("gx",at:time) ?? data?.speedAcceleration(at:time) ?? 0
        : data?.value(longitudinalField,at:time) ?? 0
      let x = r.midX+max(-1,min(1,gy/max(0.1,d.f32(260))))*radius
      let y = r.midY-max(-1,min(1,gx/max(0.1,d.f32(256))))*radius
      let ball = max(1,Double(d[277])*objectScale)
      c.setFillColor(rgb(d.u32(264)));c.fillEllipse(in:CGRect(x:x-ball,y:y-ball,width:ball*2,height:ball*2))
      let size = max(5,min(radius*0.55,d.f32(424)*objectScale))
      let numberX = min(r.maxX-size*1.2,max(r.minX+size*1.2,x))
      label(c,String(format:"%.2f",abs(gy)),font:d.utf16(288,128),size:size,color:rgb(d.u32(416)),x:numberX,y:y-size*1.3)
      label(c,String(format:"%.2f",abs(gx)),font:d.utf16(288,128),size:size,color:rgb(d.u32(420)),x:numberX,y:y+size*0.1)
      return true
    }
    return false
  }
  static func compactTime(_ time: Double) -> String {
    guard time.isFinite,abs(time) < 1e8 else { return "—" }
    return (time < 0 ? "-" : "")+String(format:"%d:%06.3f",Int(abs(time))/60,abs(time).truncatingRemainder(dividingBy:60))
  }
  static func gradient(_ c: CGContext,path: CGPath,rect r: CGRect,first: UInt32,second: UInt32,horizontal: Bool,reverse: Bool = false) {
    c.saveGState();c.addPath(path);c.clip()
    if let gradient = CGGradient(colorsSpace:OverlayRenderer.colorSpace,colors:[rgb(first),rgb(second)] as CFArray,locations:[0,1]) {
      let start = CGPoint(x:r.minX,y:r.minY),end = CGPoint(x:horizontal ? r.maxX : r.minX,y:horizontal ? r.minY : r.maxY)
      c.drawLinearGradient(gradient,start:reverse ? end : start,end:reverse ? start : end,options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
    }
    c.restoreGState()
  }
  static func shaded(_ value: UInt32,factor: Double) -> CGColor {
    CGColor(colorSpace:OverlayRenderer.colorSpace,components:[Double((value >> 16)&255)*factor/255,Double((value >> 8)&255)*factor/255,Double(value&255)*factor/255,1])!
  }
  static func barGradient(_ c: CGContext,path: CGPath,rect r: CGRect,first: UInt32,second: UInt32,horizontal: Bool,rounded: Bool) {
    guard rounded else { gradient(c,path:path,rect:r,first:first,second:second,horizontal:horizontal,reverse:true);return }
    c.saveGState();c.addPath(path);c.clip();defer { c.restoreGState() }
    // Rounded legacy bars have a cylindrical surface, with dark edges and a
    // broad highlight rather than a single flat top-to-bottom ramp.
    let colors = [shaded(second,factor:0.5),rgb(second),rgb(first),rgb(second),shaded(second,factor:0.5)]
    if let gradient = CGGradient(colorsSpace:OverlayRenderer.colorSpace,colors:colors as CFArray,locations:[0,0.15,0.4,0.85,1]) {
      c.drawLinearGradient(gradient,start:CGPoint(x:r.minX,y:r.minY),end:CGPoint(x:horizontal ? r.maxX : r.minX,y:horizontal ? r.minY : r.maxY),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
    }
  }
  static func gauge(_ c: CGContext,object o: DisplayObject,data: Telemetry?,time: Double,unit: String,rect r: CGRect,scale: Double,payload d: Data) {
    let g = o.gauge ?? GaugeSettings(),radius = min(r.width,r.height)*0.48
    let range = max(0.00001,o.maximum-o.minimum)
    let value = o.kind == .speed ? data?.speed(at:time,unit:unit,channel:o.resolvedChannel) : data?.value(o.resolvedChannel,at:time)
    func point(_ factor: Double,_ distance: Double) -> CGPoint {
      let angle = gaugeAngle(g,factor:factor)
      return CGPoint(x:r.midX+cos(angle)*distance,y:r.midY+sin(angle)*distance)
    }
    if g.showFace {
      c.setFillColor(rgb(d.u32(300)));c.fillEllipse(in:CGRect(x:r.midX-radius,y:r.midY-radius,width:radius*2,height:radius*2))
    }
    let interval = max(range/40,g.tickInterval ?? range/8)
    let ticks = max(1,Int(min(40,floor(range/interval))))
    let fontSize = min(radius*0.25,max(5,(d.count >= 668 ? d.f32(664) : d.f32(608))*scale))
    let tipLength = max(1,Double(d[624])*scale)
    let largeLength = Double(d.count >= 692 ? d[688] : 20)*scale
    let smallLength = Double(d.count >= 692 ? d[689] : 16)*scale
    let largeRadius = tipLength-Double(d.count >= 692 ? Int8(bitPattern:d[690]) : 0)*scale
    let smallRadius = tipLength-Double(d.count >= 692 ? Int8(bitPattern:d[691]) : 0)*scale
    let minorInterval = d.f64(280)
    let threshold = g.redline ?? d.f64(288)
    let changeMarkColor = g.redline != nil || d[634] & 1 != 0
    if minorInterval.isFinite,minorInterval > 0,minorInterval < interval {
      let minorTicks = min(200,Int(min(200,floor(range/minorInterval))))
      for i in 0...minorTicks {
        let f = Double(i)*minorInterval/range
        let above = changeMarkColor && o.minimum+Double(i)*minorInterval >= threshold
        c.setStrokeColor(rgb(above ? d.u32(328) : (d.count >= 688 ? d.u32(684) : d.u32(320))));c.setLineWidth(max(0.5,Double(d[630])*scale/2))
        c.move(to:point(f,smallRadius-smallLength));c.addLine(to:point(f,smallRadius));c.strokePath()
      }
    }
    var labelBounds: [CGRect] = []
    for i in 0...ticks {
      let number = o.minimum+Double(i)*interval,f = (number-o.minimum)/range
      let markColor = changeMarkColor && number >= threshold
      c.setStrokeColor(rgb(d.u32(markColor ? 328 : 320))); c.setLineWidth(max(1,Double(d[629])*scale/2));c.move(to:point(f,largeRadius-largeLength));c.addLine(to:point(f,largeRadius));c.strokePath()
      if g.showLabels && (d[633] & 2 == 0 || i % 2 == 0 || i == ticks) {
        let p = point(f,tipLength-largeLength-fontSize*0.5)
        let text = String(format:"%.0f",number/max(0.00001,g.numberingScale))
        let bounds = CGRect(x:p.x-Double(text.count)*fontSize*0.35,y:p.y-fontSize*0.6,width:Double(text.count)*fontSize*0.7,height:fontSize*1.2)
        if !labelBounds.contains(where: { $0.intersects(bounds) }) {
          label(c,text,font:d.utf16(352,128),size:fontSize,color:rgb(d.count >= 696 ? d.u32(692) : d.u32(332)),x:p.x,y:p.y-fontSize*0.5)
          labelBounds.append(bounds)
        }
      }
    }
    if let value,value.isFinite {
      let f = max(0,min(1,(value-o.minimum)/range)),tip = point(f,tipLength)
      let tail = point(f,-Double(Int8(bitPattern:d[625]))*scale)
      c.setStrokeColor(OverlayRenderer.color(o.color));c.setLineWidth(max(1,Double(d[623])*scale*2));c.setLineCap(.round);c.move(to:tail);c.addLine(to:tip);c.strokePath()
    }
    if g.showNumber && d.u32(336) >> 24 != 255 {
      let size = min(radius*0.55,max(8,d.f32(612)*scale))
      let p = textPosition(d,common:o.legacyCommon,offset:348,rect:r,fallback:CGPoint(x:r.midX,y:r.midY))
      label(c,value.map { String(format:"%.*f",max(0,min(6,g.decimals)),$0) } ?? "—",font:d.utf16(480,128),size:size,color:rgb(d.u32(336)),x:p.x,y:p.y-size)
    }
    if g.showLabels {
      let title = g.label
      let p = textPosition(d,common:o.legacyCommon,offset:344,rect:r,fallback:CGPoint(x:r.midX,y:r.midY+radius*0.3))
      let labelSize = min(radius*0.25,max(5,d.f32(608)*scale))
      label(c,title,font:d.utf16(352,128),size:labelSize,color:rgb(d.u32(332)),x:p.x,y:p.y-labelSize)
    }
  }
  static func gaugeAngle(_ g: GaugeSettings,factor: Double) -> Double {
    (-90-g.rotation+(g.counterClockwise ? 1 : -1)*factor*g.sweep) * .pi/180
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
