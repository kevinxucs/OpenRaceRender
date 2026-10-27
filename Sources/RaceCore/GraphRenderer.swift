import AppKit

public enum GraphRenderer {
  public static func draw(_ c: CGContext, object o: DisplayObject, rect r: CGRect, data: Telemetry?, time: Double) {
    let g = o.graph ?? GraphSettings()
    func safe(_ v: Double, _ fallback: Double, _ upper: Double = 1000) -> Double { v.isFinite ? max(0,min(upper,v)) : fallback }
    let scale = r.width / max(1,safe(g.referenceWidth,600,16384))
    if g.background { c.setFillColor(OverlayRenderer.color(g.backgroundColor)); c.fill(r) }
    let font = max(6,safe(g.numberSize,12)*scale)
    let inset = g.numbers ? min(min(r.width,r.height)*0.25,font*2.7) : safe(g.trimWidth,1)*scale
    let plotRect = r.insetBy(dx:inset,dy:g.numbers ? min(r.height*0.25,font*1.7) : safe(g.trimWidth,1)*scale)
    guard plotRect.width > 0, plotRect.height > 0 else { return }
    guard let data else {
      OverlayRenderer.text(c,"NO DATA",x:r.midX,y:r.midY,size:min(14,r.height/5)); return
    }
    let p = GraphSampler.plot(object:o,data:data,time:time,resolution:Int(min(2048,max(32,plotRect.width))))
    func fraction(_ value: Double, _ range: ClosedRange<Double>) -> Double {
      max(-10,min(10,(value-range.lowerBound)/max(0.000001,range.upperBound-range.lowerBound)))
    }
    func point(_ x: Double,_ y: Double) -> CGPoint {
      var u = fraction(x,p.xRange), v = fraction(y,p.yRange)
      if g.reverse { u = 1-u }
      if g.vertical { swap(&u,&v) }
      return CGPoint(x:plotRect.minX+u*plotRect.width,y:plotRect.minY+v*plotRect.height)
    }
    func ticks(_ range: ClosedRange<Double>, explicit: Double) -> [Double] {
      let span = range.upperBound-range.lowerBound
      let raw = span/5, power = pow(10,floor(log10(max(raw,1e-12))))
      let step = explicit.isFinite && explicit > 0 ? explicit : (raw/power > 5 ? 10 : raw/power > 2 ? 5 : raw/power > 1 ? 2 : 1)*power
      guard step.isFinite, step > 0 else { return [] }
      let first = ceil(range.lowerBound/step)*step
      guard first.isFinite else { return [] }
      let count = min(100,max(0,(range.upperBound-first)/step+1))
      return (0..<Int(count)).map { first+Double($0)*step }
    }
    c.saveGState(); c.clip(to:plotRect)
    if g.axes {
      c.setStrokeColor(OverlayRenderer.color(g.axisColor)); c.setLineWidth(max(0.5,safe(g.axisWidth,1)*scale))
      for x in ticks(p.xRange,explicit:g.interval) { c.move(to:point(x,p.yRange.lowerBound)); c.addLine(to:point(x,p.yRange.upperBound)) }
      for y in ticks(p.yRange,explicit:g.interval) { c.move(to:point(p.xRange.lowerBound,y)); c.addLine(to:point(p.xRange.upperBound,y)) }
      c.strokePath()
    }
    var runs: [[GraphPoint]] = []
    for q in p.points {
      if q.beginsPath || runs.isEmpty { runs.append([]) }; runs[runs.count-1].append(q)
    }
    if g.fill && g.connect {
      let path = CGMutablePath()
      let base = max(p.yRange.lowerBound,min(p.yRange.upperBound,0))
      for run in runs where run.count > 1 {
        path.move(to:point(run[0].x,base))
        for q in run { path.addLine(to:point(q.x,q.y)) }
        path.addLine(to:point(run.last!.x,base)); path.closeSubpath()
      }
      paint(c,path:path,color:g.fillColor,gradient:g.fillGradient,rect:plotRect,vertical:g.vertical)
    }
    let width = max(0.5,safe(g.lineWidth,2)*scale)
    let path = CGMutablePath()
    if g.connect {
      for run in runs {
        for (i,q) in run.enumerated() { if i == 0 { path.move(to:point(q.x,q.y)) } else { path.addLine(to:point(q.x,q.y)) } }
        if run.count == 1 { let q = point(run[0].x,run[0].y); path.addEllipse(in:CGRect(x:q.x-width/2,y:q.y-width/2,width:width,height:width)) }
      }
      let stroke = path.copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:1)
      paint(c,path:stroke,color:g.lineColor,gradient:g.lineGradient,rect:plotRect,vertical:g.vertical)
    } else {
      for q in p.points { let q = point(q.x,q.y); path.addEllipse(in:CGRect(x:q.x-width,y:q.y-width,width:2*width,height:2*width)) }
      paint(c,path:path,color:g.lineColor,gradient:g.lineGradient,rect:plotRect,vertical:g.vertical)
    }
    if let cursor = p.cursor {
      c.setStrokeColor(OverlayRenderer.color(g.markerColor)); c.setFillColor(OverlayRenderer.color(g.markerColor))
      if [.fixedLine,.fixedBoth,.centered].contains(g.mode) {
        c.setLineWidth(max(0.5,safe(g.markerSize,3)*scale)); c.move(to:point(cursor.x,p.yRange.lowerBound)); c.addLine(to:point(cursor.x,p.yRange.upperBound)); c.strokePath()
      }
      if [.fixedDot,.fixedBoth,.centered].contains(g.mode) {
        let q = point(cursor.x,cursor.y), radius = max(2,safe(g.markerSize,3)*scale)
        c.fillEllipse(in:CGRect(x:q.x-radius,y:q.y-radius,width:radius*2,height:radius*2))
      }
    }
    c.restoreGState()
    if g.numbers {
      func label(_ v: Double) -> String { String(format:abs(v) >= 10000 ? "%.3g" : "%.2f",v).replacingOccurrences(of:".00",with:"") }
      for x in ticks(p.xRange,explicit:g.interval) {
        let q = point(x,g.flipSides ? p.yRange.upperBound : p.yRange.lowerBound)
        OverlayRenderer.text(c,label(x),x:g.vertical ? (g.flipSides ? plotRect.maxX+font : plotRect.minX-font) : q.x,y:g.vertical ? q.y-font/2 : (g.flipSides ? plotRect.maxY+font*0.2 : plotRect.minY-font*1.3),size:font,color:g.numberColor,align:g.vertical ? 1 : 0.5)
      }
      for y in ticks(p.yRange,explicit:g.interval) {
        let q = point(g.flipSides ? p.xRange.upperBound : p.xRange.lowerBound,y)
        OverlayRenderer.text(c,label(y),x:g.vertical ? q.x : (g.flipSides ? plotRect.maxX+font*2.5 : plotRect.minX-font/3),y:g.vertical ? (g.flipSides ? plotRect.maxY+font*0.2 : plotRect.minY-font*1.3) : q.y-font/2,size:font,color:g.numberColor,align:g.vertical ? 0.5 : 1)
      }
    }
    if g.trim { c.setStrokeColor(OverlayRenderer.color(g.trimColor)); c.setLineWidth(max(0.5,safe(g.trimWidth,1)*scale)); c.stroke(plotRect) }
    if !g.label.isEmpty { OverlayRenderer.text(c,g.label,x:r.midX,y:r.maxY-max(font,safe(g.labelSize,18)*scale)*1.3,size:max(1,safe(g.labelSize,18)*scale),color:g.labelColor) }
    if let message = p.message { OverlayRenderer.text(c,message,x:r.midX,y:r.midY,size:min(14,r.height/5),color:"#FFBC6E") }
  }
  private static func paint(_ c: CGContext,path: CGPath,color: String,gradient: String?,rect: CGRect,vertical: Bool) {
    c.saveGState(); c.addPath(path)
    if let gradient, let ramp = CGGradient(colorsSpace:OverlayRenderer.colorSpace,
      colors:[OverlayRenderer.color(color),OverlayRenderer.color(gradient)] as CFArray,locations:[0,1]) {
      c.clip(); c.drawLinearGradient(ramp,start:CGPoint(x:rect.minX,y:rect.minY),
        end:vertical ? CGPoint(x:rect.maxX,y:rect.minY) : CGPoint(x:rect.minX,y:rect.maxY),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
    } else { c.setFillColor(OverlayRenderer.color(color)); c.fillPath() }
    c.restoreGState()
  }
}
