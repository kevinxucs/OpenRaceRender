import AppKit

/// The saved map trace, lap selection, edge color and vehicle icon belong to the style.
enum LegacyMapRenderer {
  static func draw(_ c: CGContext,object o: DisplayObject,rect r: CGRect,data: Telemetry?,time: Double) -> Bool {
    guard o.legacyType == 70,let d = o.legacyPayload,d.count >= 80,let data else { return false }
    let lap = d[63] == 1 ? data.bestLap : nil
    let points = data.trackPoints(from:lap?.start ?? 0,to:lap?.end ?? data.duration)
    guard points.count > 1 else { return false }
    let minX = points.map(\.0).min()!,maxX = points.map(\.0).max()!
    let minY = points.map(\.1).min()!,maxY = points.map(\.1).max()!
    let scale = min(r.width*0.90/max(1e-9,maxX-minX),r.height*0.90/max(1e-9,maxY-minY))
    func point(_ value: (Double,Double)) -> CGPoint {
      CGPoint(x:r.midX+(value.0-(minX+maxX)/2)*scale,y:r.midY+(value.1-(minY+maxY)/2)*scale)
    }
    let path = CGMutablePath();path.move(to:point(points[0]))
    for value in points.dropFirst() { path.addLine(to:point(value)) }
    let rasterHeight = Double((o.legacyCommon?.u32(296) ?? 0) >> 16)
    let styleScale = rasterHeight > 0 ? r.height/rasterHeight : r.height/1200
    let width = max(0.5,Double(d[57])*styleScale*2)
    c.setLineCap(.round);c.setLineJoin(.round)
    if d.u32(72) >> 24 != 255 {
      c.setStrokeColor(LegacyStyledRenderer.rgb(d.u32(72)));c.setLineWidth(width+max(1,width*0.45));c.addPath(path);c.strokePath()
    }
    if d.u32(32) >> 24 != 255 {
      c.setStrokeColor(LegacyStyledRenderer.rgb(d.u32(32)));c.setLineWidth(width);c.addPath(path);c.strokePath()
    }
    if d.u32(40) >> 24 != 255 {
      let start = point(points[0]),next = point(points[min(3,points.count-1)])
      let angle = atan2(next.y-start.y,next.x-start.x)
      let cell = max(0.5,Double(d[58])*styleScale*0.75)
      c.saveGState();c.translateBy(x:start.x,y:start.y);c.rotate(by:angle)
      for row in 0..<2 { for column in 0..<4 {
        c.setFillColor((row+column)%2 == 0 ? LegacyStyledRenderer.rgb(d.u32(40)) : CGColor(gray:0,alpha:1))
        c.fill(CGRect(x:Double(row-1)*cell,y:Double(column-2)*cell,width:cell,height:cell))
      } };c.restoreGState()
    }
    if d.u32(48) >> 24 != 255,let position = data.trackPosition(at:time) {
      let p = point(position),size = max(2,Double(d[59])*styleScale)
      c.setFillColor(LegacyStyledRenderer.rgb(d.u32(48)))
      if d[68] == 0 { c.fillEllipse(in:CGRect(x:p.x-size/2,y:p.y-size/2,width:size,height:size)) }
      else {
        let next = data.trackPosition(at:min(data.duration,time+0.25)) ?? position
        let angle = atan2(next.1-position.1,next.0-position.0)
        c.saveGState();c.translateBy(x:p.x,y:p.y);c.rotate(by:angle)
        c.move(to:CGPoint(x:size,y:0));c.addLine(to:CGPoint(x:-size*0.65,y:size*0.65))
        c.addLine(to:CGPoint(x:-size*0.25,y:0));c.addLine(to:CGPoint(x:-size*0.65,y:-size*0.65));c.closePath();c.fillPath();c.restoreGState()
      }
    }
    return true
  }
}
