import AppKit

/// The saved map trace, lap selection, edge color and vehicle icon belong to the style.
enum LegacyMapRenderer {
  final class Trace: NSObject {
    let telemetry: Telemetry
    let points: [(Double,Double)]
    let bounds: CGRect
    let path: CGPath
    init(data: Telemetry,start: Double,end: Double) {
      telemetry = data;points = data.trackPoints(from:start,to:end)
      let minX = points.map(\.0).min() ?? 0,maxX = points.map(\.0).max() ?? 0
      let minY = points.map(\.1).min() ?? 0,maxY = points.map(\.1).max() ?? 0
      bounds = CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)
      let p = CGMutablePath()
      if let first = points.first { p.move(to:CGPoint(x:first.0,y:first.1));for v in points.dropFirst() { p.addLine(to:CGPoint(x:v.0,y:v.1)) } }
      path = p
    }
  }
  static let traces: NSCache<NSString,Trace> = { let c = NSCache<NSString,Trace>();c.countLimit = 16;return c }()
  static func draw(_ c: CGContext,object o: DisplayObject,rect r: CGRect,data: Telemetry?,time: Double) -> Bool {
    guard o.legacyType == 70,let d = o.legacyPayload,d.count >= 80,let data else { return false }
    let lap = d[63] == 1 ? data.bestLap : nil
    let start = lap?.start ?? 0,end = lap?.end ?? data.duration
    let key = "\(ObjectIdentifier(data))|\(data.renderRevision)|\(start.bitPattern)|\(end.bitPattern)" as NSString
    let trace: Trace
    if let cached = traces.object(forKey:key) { trace = cached }
    else { trace = Trace(data:data,start:start,end:end);traces.setObject(trace,forKey:key) }
    let points = trace.points
    guard points.count > 1 else { return false }
    let minX = trace.bounds.minX,maxX = trace.bounds.maxX,minY = trace.bounds.minY,maxY = trace.bounds.maxY
    let zoom = d[60] == 0 ? 1 : Double(d[60])/100
    let scale = min(r.width*0.90/max(1e-9,maxX-minX),r.height*0.90/max(1e-9,maxY-minY))*zoom
    func point(_ value: (Double,Double)) -> CGPoint {
      CGPoint(x:r.midX+(value.0-(minX+maxX)/2)*scale,y:r.midY+(value.1-(minY+maxY)/2)*scale)
    }
    var transform = CGAffineTransform(a:scale,b:0,c:0,d:scale,tx:r.midX-(minX+maxX)*scale/2,ty:r.midY-(minY+maxY)*scale/2)
    guard let path = trace.path.copy(using:&transform) else { return false }
    let rasterHeight = Double((o.legacyCommon?.u32(296) ?? 0) >> 16)
    let styleScale = rasterHeight > 0 ? r.height/rasterHeight : r.height/1200
    let width = max(0.5,Double(d[57])*r.height/800)
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
