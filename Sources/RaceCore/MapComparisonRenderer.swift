import AppKit

enum MapComparisonRenderer {
  final class Trace:NSObject {
    let primary:Telemetry,reference:Telemetry
    let origin:FinishLine
    let primaryPath:CGPath,referencePath:CGPath
    let bounds:CGRect
    init?(primary:Telemetry,reference:Telemetry,settings:MapComparisonSettings,display:MapDisplaySettings? = nil,time:Double = 0) {
      let a = primary.gpsTrackSamples(maximum:display?.resolution.points ?? 4000,interpolateCurves:true),b = reference.gpsTrackSamples(maximum:display?.resolution.points ?? 4000,interpolateCurves:true)
      guard let first = a.first,a.count > 1,b.count > 1 else { return nil }
      self.primary = primary; self.reference = reference
      let origin = FinishLine(latitude:first.latitude,longitude:first.longitude,heading:0); self.origin = origin
      func projected(_ sample:GPSTrackSample) -> CGPoint {
        let p = origin.localPosition(latitude:sample.latitude,longitude:sample.longitude); return CGPoint(x:p.0,y:p.1)
      }
      let all = (a+b).map(projected)
      let minX = all.map(\.x).min()!,maxX = all.map(\.x).max()!,minY = all.map(\.y).min()!,maxY = all.map(\.y).max()!
      bounds = CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)
      func path(_ samples:[GPSTrackSample],data:Telemetry,start:Double?) -> CGPath {
        var points = samples.filter{settings.includes($0.time,in:data,lapStart:start)}
        let lap = start.flatMap{t in data.laps.first{abs($0.start-t) < 1e-6}}
        for time in [lap?.start ?? 0,lap?.end ?? data.duration] {
          if let latitude = data.value("lat",at:time),let longitude = data.value("lon",at:time) {
            points.append(GPSTrackSample(time:time,latitude:latitude,longitude:longitude))
          }
        }
        if start != nil,lap == nil { points = [] }
        points.sort{$0.time < $1.time}
        let path = CGMutablePath()
        for (index,sample) in points.enumerated() {
          if index == 0 { path.move(to:projected(sample)) } else { path.addLine(to:projected(sample)) }
        }
        return path
      }
      if let display,display.trace != .all {
        if let range = display.range(data:primary,time:time) { primaryPath = path(a,data:primary,start:range.lowerBound) }
        else { primaryPath = CGMutablePath() }
      } else { primaryPath = path(a,data:primary,start:settings.primaryLapStart) }
      let otherStart = settings.referenceLapStart ?? (settings.mode == .lapGhost ? reference.bestLap?.start : nil)
      referencePath = path(b,data:reference,start:otherStart)
    }
    func point(latitude:Double,longitude:Double) -> CGPoint {
      let p = origin.localPosition(latitude:latitude,longitude:longitude); return CGPoint(x:p.0,y:p.1)
    }
  }
  static let cache:NSCache<NSString,Trace> = { let c = NSCache<NSString,Trace>(); c.countLimit = 16; return c }()
  static func draw(_ c:CGContext,object:DisplayObject,rect r:CGRect,scene:RenderScene,sourceTime:Double,projectTime:Double) -> Bool {
    guard object.kind == .map,let settings = object.mapComparison else { return false }
    func unavailable(_ text:String) {
      OverlayRenderer.panel(c,r); OverlayRenderer.text(c,text,x:r.midX,y:r.midY,size:min(r.width,r.height)*0.06,color:"#9BA8B9")
    }
    guard let data = scene.telemetry[object.inputIndex],let other = scene.telemetry[settings.referenceInputIndex] else { unavailable("CHOOSE TWO DATA SOURCES"); return true }
    let display = object.mapSettings
    let traceStart = display?.range(data:data,time:sourceTime)?.lowerBound ?? -1
    let key = "\(display?.trace.rawValue ?? "original"):\(display?.resolution.rawValue ?? "high"):\(traceStart):\(ObjectIdentifier(data)):\(data.renderRevision):\(ObjectIdentifier(other)):\(other.renderRevision):\(settings.mode.rawValue):\(settings.primaryLapStart ?? -1):\(settings.referenceLapStart ?? -1)" as NSString
    let trace:Trace
    if let found = cache.object(forKey:key) { trace = found }
    else if let found = Trace(primary:data,reference:other,settings:settings,display:display,time:sourceTime) { trace = found; cache.setObject(found,forKey:key) }
    else { unavailable("GPS REQUIRED FOR SHARED MAP"); return true }
    let labelHeight = settings.showLabels ? min(r.height*0.18,40) : 0
    let area = CGRect(x:r.minX,y:r.minY+labelHeight,width:r.width,height:max(1,r.height-labelHeight))
    let scale = min(area.width*0.86/max(1,trace.bounds.width),area.height*0.86/max(1,trace.bounds.height))
    var transform = CGAffineTransform(a:scale,b:0,c:0,d:scale,tx:area.midX-trace.bounds.midX*scale,ty:area.midY-trace.bounds.midY*scale)
    let primaryPoint = data.value("lat",at:sourceTime).flatMap { lat in data.value("lon",at:sourceTime).map { trace.point(latitude:lat,longitude:$0) } }
    let viewport = display.map { MapViewport(bounds:trace.bounds,rect:area,settings:$0,position:primaryPoint,heading:data.value("heading",at:sourceTime)) }
    if let display,let viewport {
      MapPainter.background(c,object:object,rect:r,viewport:viewport,settings:display)
      MapPainter.course(c,path:trace.primaryPath,viewport:viewport,rect:area,settings:display)
      if display.drawStart {
        let start = display.trace == .all ? settings.primaryLapStart ?? 0 : display.range(data:data,time:sourceTime)?.lowerBound ?? 0
        if let lat = data.value("lat",at:start),let lon = data.value("lon",at:start) {
          let p = trace.point(latitude:lat,longitude:lon).applying(viewport.transform)
          OverlayRenderer.text(c,"⚑",x:p.x,y:p.y,size:max(10,min(area.width,area.height)*0.08),color:display.lineColor)
        }
      }
      if settings.showReferenceTrace { MapPainter.course(c,path:trace.referencePath,viewport:viewport,rect:area,settings:display,color:settings.referenceColor) }
    }
    if display == nil,let path = trace.primaryPath.copy(using:&transform) {
      c.addPath(path); c.setStrokeColor(OverlayRenderer.color("#111821",alpha:0.8)); c.setLineWidth(max(4,min(r.width,r.height)*0.035)); c.setLineJoin(.round); c.setLineCap(.round); c.strokePath()
      c.addPath(path); c.setStrokeColor(OverlayRenderer.color("#E4EAF1")); c.setLineWidth(max(1.5,min(r.width,r.height)*0.012)); c.strokePath()
    }
    if display == nil,settings.showReferenceTrace,let path = trace.referencePath.copy(using:&transform) {
      c.addPath(path); c.setStrokeColor(OverlayRenderer.color(settings.referenceColor,alpha:0.65)); c.setLineWidth(max(1,min(r.width,r.height)*0.008)); c.strokePath()
    }
    func marker(_ source:Telemetry,time:Double?,color:String,hollow:Bool) {
      guard let time,let latitude = source.value("lat",at:time),let longitude = source.value("lon",at:time) else { return }
      let raw = trace.point(latitude:latitude,longitude:longitude)
      if let display,let viewport {
        let t = min(source.duration,time+0.2)
        let next = source.value("lat",at:t).flatMap{lat in source.value("lon",at:t).map{trace.point(latitude:lat,longitude:$0)}}
        MapPainter.marker(c,point:raw,next:next,viewport:viewport,rect:area,settings:display,color:color,hollow:hollow)
        return
      }
      let p = raw.applying(transform)
      let radius = max(3,min(r.width,r.height)*0.028),rect = CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)
      c.setFillColor(OverlayRenderer.color(color)); c.setStrokeColor(OverlayRenderer.color(color)); c.setLineWidth(max(2,radius*0.4))
      if hollow { c.strokeEllipse(in:rect.insetBy(dx:-2,dy:-2)) } else { c.fillEllipse(in:rect) }
    }
    let primaryTime = settings.includes(sourceTime,in:data,lapStart:settings.primaryLapStart) ? sourceTime : nil
    let timelineTime = scene.project.sourceTime(for:settings.referenceInputIndex,at:projectTime)
    var referenceTime = settings.referenceTime(primary:data,reference:other,primaryTime:sourceTime,timelineTime:timelineTime)
    if settings.mode == .timeline,let t = referenceTime,!settings.includes(t,in:other,lapStart:settings.referenceLapStart) { referenceTime = nil }
    marker(other,time:referenceTime,color:settings.referenceColor,hollow:true)
    marker(data,time:primaryTime,color:display?.positionColor ?? object.color,hollow:false)
    if settings.showLabels {
      let a = scene.project.inputs.first{$0.legacyIndex == object.inputIndex}?.name ?? "Primary"
      let b = scene.project.inputs.first{$0.legacyIndex == settings.referenceInputIndex}?.name ?? "Reference"
      let size = min(14,max(8,r.height*0.05))
      OverlayRenderer.text(c,String(a.prefix(30)),x:r.minX+5,y:r.minY+size*1.4,size:size,color:display?.positionColor ?? object.color,align:0)
      let title = (referenceTime == nil ? "UNAVAILABLE · " : settings.mode == .lapGhost ? "GHOST · " : "")+b
      OverlayRenderer.text(c,String(title.prefix(40)),x:r.minX+5,y:r.minY+2,size:size,color:settings.referenceColor,align:0)
    }
    return true
  }
}
