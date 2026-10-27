import AppKit

public struct MapDisplaySettings:Codable,Equatable,Sendable {
  public enum Trace:String,Codable,CaseIterable,Sendable { case all,best,current,lap }
  public enum Icon:String,Codable,CaseIterable,Sendable { case dot,ring,arrow,car }
  public enum Resolution:String,Codable,CaseIterable,Sendable {
    case normal,high,extreme
    public var points:Int { self == .normal ? 1000 : self == .high ? 4000 : 16000 }
  }
  public var trace:Trace = .all
  public var lapStart:Double?
  public var drawCourse = true
  public var drawPosition = true
  public var drawStart = false
  public var icon:Icon = .dot
  public var markerSize:Double = 5.6
  public var zoom:Double = 1
  public var rotation:Double = 0
  public var headingUp = false
  public var followPosition = false
  public var resolution:Resolution = .high
  public var lineColor = "#E4EAF1"
  public var edgeColor = "#111821"
  public var lineWidth:Double = 1.2
  public var edgeWidth:Double = 2.3
  public var positionColor:String?
  public var alignBackground = true
  public init() {}
  public func range(data:Telemetry,time:Double) -> ClosedRange<Double>? {
    let lap:TelemetryLap?
    switch trace {
    case .all:return 0...data.duration
    case .best:lap = data.bestLap
    case .current:lap = data.lap(at:time)
    case .lap:lap = lapStart.flatMap{start in data.laps.first{abs($0.start-start) < 1e-6}}
    }
    return lap.flatMap{$0.end >= $0.start ? $0.start...$0.end : nil}
  }
}

extension DisplayObject {
  public var editableMapSettings:MapDisplaySettings {
    if let mapSettings { return mapSettings }
    var settings = MapDisplaySettings()
    guard legacyType == 70,let p = legacyPayload,p.count >= 80 else { return settings }
    func color(_ offset:Int) -> String { String(format:"#%06X",p.u32(offset)&0xffffff) }
    settings.trace = p[63] == 1 ? .best : .all
    settings.drawCourse = p.u32(32)>>24 != 255; settings.drawPosition = p.u32(48)>>24 != 255; settings.drawStart = p.u32(40)>>24 != 255
    settings.lineColor = color(32); settings.edgeColor = color(72); settings.positionColor = color(48)
    settings.lineWidth = Double(p[57])/8; settings.edgeWidth = p.u32(72)>>24 != 255 ? settings.lineWidth*0.45 : 0
    let height = Double((legacyCommon?.u32(296) ?? 0)>>16)
    settings.markerSize = Double(p[59])/max(1,height > 0 ? height/100 : 12)
    settings.zoom = p[60] == 0 ? 1 : Double(p[60])/100; settings.icon = p[68] == 0 ? .dot : .arrow
    return settings
  }
}

struct MapViewport {
  let transform:CGAffineTransform
  let backgroundTransform:CGAffineTransform
  init(bounds:CGRect,rect:CGRect,settings:MapDisplaySettings,position:CGPoint?,heading:Double?) {
    let scale = min(rect.width*0.86/max(1e-9,bounds.width),rect.height*0.86/max(1e-9,bounds.height))
    let zoom = settings.zoom.isFinite ? min(20,max(0.1,settings.zoom)) : 1
    let rotation = settings.rotation.isFinite ? settings.rotation.truncatingRemainder(dividingBy:360) : 0
    let angle = -(rotation+(settings.headingUp ? -(heading ?? 0) : 0)) * .pi/180
    let a = scale*zoom*cos(angle),b = scale*zoom*sin(angle),c = -b,d = a
    let center = settings.followPosition ? position ?? CGPoint(x:bounds.midX,y:bounds.midY) : CGPoint(x:bounds.midX,y:bounds.midY)
    transform = CGAffineTransform(a:a,b:b,c:c,d:d,tx:rect.midX-a*center.x-c*center.y,ty:rect.midY-b*center.x-d*center.y)
    let base = CGAffineTransform(a:scale,b:0,c:0,d:scale,tx:rect.midX-bounds.midX*scale,ty:rect.midY-bounds.midY*scale)
    backgroundTransform = base.inverted().concatenating(transform)
  }
}

enum MapPainter {
  static func background(_ c:CGContext,object:DisplayObject,rect:CGRect,viewport:MapViewport,settings:MapDisplaySettings) {
    guard let bytes = WidgetBackground.data(for:object),let image = NSImage(data:bytes)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
    c.saveGState(); if settings.alignBackground { c.concatenate(viewport.backgroundTransform) }; c.draw(image,in:rect); c.restoreGState()
  }
  static func course(_ c:CGContext,path:CGPath,viewport:MapViewport,rect:CGRect,settings:MapDisplaySettings,color:String? = nil) {
    guard settings.drawCourse else { return }
    var transform = viewport.transform
    guard let path = path.copy(using:&transform) else { return }
    let scale = min(rect.width,rect.height)/100
    let width = settings.lineWidth.isFinite ? max(0.1,min(20,settings.lineWidth))*scale : scale
    c.setLineCap(.round); c.setLineJoin(.round)
    if color == nil,settings.edgeWidth.isFinite,settings.edgeWidth > 0 {
      c.addPath(path); c.setStrokeColor(OverlayRenderer.color(settings.edgeColor)); c.setLineWidth(width+min(20,settings.edgeWidth)*scale); c.strokePath()
    }
    c.addPath(path); c.setStrokeColor(OverlayRenderer.color(color ?? settings.lineColor)); c.setLineWidth(width); c.strokePath()
  }
  static func marker(_ c:CGContext,point:CGPoint,next:CGPoint?,viewport:MapViewport,rect:CGRect,settings:MapDisplaySettings,color:String,hollow:Bool = false) {
    guard settings.drawPosition else { return }
    let p = point.applying(viewport.transform),future = next?.applying(viewport.transform)
    let heading = future.map{atan2($0.y-p.y,$0.x-p.x)} ?? .pi/2
    let size = settings.markerSize.isFinite ? min(40,max(0.2,settings.markerSize)) : 5.6
    let radius = max(2,min(rect.width,rect.height)*size/200)
    c.saveGState(); c.translateBy(x:p.x,y:p.y); c.rotate(by:heading)
    c.setFillColor(OverlayRenderer.color(color)); c.setStrokeColor(OverlayRenderer.color(color)); c.setLineWidth(max(1,radius*0.3))
    let path = CGMutablePath()
    switch settings.icon {
    case .dot,.ring:path.addEllipse(in:CGRect(x:-radius,y:-radius,width:radius*2,height:radius*2).insetBy(dx:hollow ? -2 : 0,dy:hollow ? -2 : 0))
    case .arrow:
      path.move(to:CGPoint(x:radius*1.4,y:0)); path.addLine(to:CGPoint(x:-radius,y:radius)); path.addLine(to:CGPoint(x:-radius*0.4,y:0)); path.addLine(to:CGPoint(x:-radius,y:-radius)); path.closeSubpath()
    case .car:
      for x in [-0.7,0.5] { for y in [-0.7,0.4] { c.fill(CGRect(x:x*radius,y:y*radius,width:radius*0.5,height:radius*0.3)) } }
      path.addRoundedRect(in:CGRect(x:-radius,y:-radius*0.5,width:radius*2,height:radius),cornerWidth:radius*0.25,cornerHeight:radius*0.25)
    }
    c.addPath(path)
    if hollow || settings.icon == .ring { c.strokePath() } else { c.fillPath() }
    c.restoreGState()
  }
}

enum MapDisplayRenderer {
  final class Trace:NSObject {
    let data:Telemetry,points:[(Double,Double)],path:CGPath,bounds:CGRect
    init(data:Telemetry,range:ClosedRange<Double>,maximum:Int) {
      self.data = data
      var selected = data.trackPoints(from:range.lowerBound,to:range.upperBound,maximum:maximum)
      if let first = data.trackPosition(at:range.lowerBound),!selected.isEmpty { selected[0] = first }
      if let last = data.trackPosition(at:range.upperBound) { selected.append(last) }
      points = selected
      let x = points.map(\.0),y = points.map(\.1)
      bounds = CGRect(x:x.min() ?? 0,y:y.min() ?? 0,width:(x.max() ?? 0)-(x.min() ?? 0),height:(y.max() ?? 0)-(y.min() ?? 0))
      let path = CGMutablePath(); for (i,p) in points.enumerated() { if i == 0 { path.move(to:CGPoint(x:p.0,y:p.1)) } else { path.addLine(to:CGPoint(x:p.0,y:p.1)) } }; self.path = path
    }
  }
  static let cache:NSCache<NSString,Trace> = { let c = NSCache<NSString,Trace>(); c.countLimit = 16; return c }()
  static func draw(_ c:CGContext,object:DisplayObject,rect:CGRect,data:Telemetry?,time:Double) -> Bool {
    guard object.kind == .map,let settings = object.mapSettings else { return false }
    guard let data,let range = settings.range(data:data,time:time) ?? (!settings.drawCourse ? 0...data.duration : nil) else { OverlayRenderer.text(c,"NO SELECTED LAP / GPS",x:rect.midX,y:rect.midY,size:min(rect.width,rect.height)*0.06,color:"#9BA8B9"); return true }
    let key = "\(ObjectIdentifier(data))|\(data.renderRevision)|\(range.lowerBound)|\(range.upperBound)|\(settings.resolution.rawValue)" as NSString
    let trace:Trace
    if let found = cache.object(forKey:key) { trace = found }
    else { trace = Trace(data:data,range:range,maximum:settings.resolution.points); cache.setObject(trace,forKey:key) }
    guard trace.points.count > 1 else { OverlayRenderer.text(c,"NO MAP POSITIONS",x:rect.midX,y:rect.midY,size:min(rect.width,rect.height)*0.06,color:"#9BA8B9"); return true }
    let position = data.trackPosition(at:time).map{CGPoint(x:$0.0,y:$0.1)}
    let next = data.trackPosition(at:min(data.duration,time+0.2)).map{CGPoint(x:$0.0,y:$0.1)}
    let heading = data.value("heading",at:time)
    let viewport = MapViewport(bounds:trace.bounds,rect:rect,settings:settings,position:position,heading:heading)
    MapPainter.background(c,object:object,rect:rect,viewport:viewport,settings:settings)
    MapPainter.course(c,path:trace.path,viewport:viewport,rect:rect,settings:settings)
    if settings.drawStart,let first = trace.points.first {
      let p = CGPoint(x:first.0,y:first.1).applying(viewport.transform)
      OverlayRenderer.text(c,"⚑",x:p.x,y:p.y,size:max(10,min(rect.width,rect.height)*0.08),color:settings.lineColor)
    }
    if let position { MapPainter.marker(c,point:position,next:next,viewport:viewport,rect:rect,settings:settings,color:settings.positionColor ?? object.color) }
    return true
  }
}
