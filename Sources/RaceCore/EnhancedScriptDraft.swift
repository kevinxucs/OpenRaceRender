import AppKit

/// Edits are private until the complete draft is validated and applied.
public struct EnhancedScriptDraft:Equatable,Sendable {
  public var background = "DrawRect(0,0,SizeX,SizeY,Black,Filled);"
  public var foreground = "DrawText(\"Enhanced\",CenterX,CenterY,ColorA,24,AlignH_Center);"
  public var width = 320
  public var height = 180
  public var font = "Arial"
  public var persistent = false
  public var maintainAspect = true
  public init(object:DisplayObject) {
    guard object.hasScriptStyleSettings,let data = object.legacyPayload else { return }
    func source(_ offset:Int) -> String {String(bytes:data[offset..<offset+32768].prefix{$0 != 0},encoding:.utf8) ?? ""}
    background = source(1632); foreground = source(34400)
    width = Int(data.u32(280)&0xffff); height = Int(data.u32(280)>>16)
    font = data.utf16(432,128); persistent = data[284]&4 != 0
    maintainAspect = object.picture?.maintainAspect ?? (object.legacyCommon.map{$0.count > 285 && $0[285] != 0} ?? true)
  }
  public func validate() throws {
    guard (1...2048).contains(width),(1...2048).contains(height),font.utf16.count < 64,!font.contains("\0") else {throw RaceError.invalid("Script canvas must be 1–2048 pixels per side; font name must fit 63 UTF-16 units.")}
    for (stage,source) in [("Background",background),("Foreground",foreground)] {
      guard source.utf8.count < 32768,!source.contains("\0") else {throw RaceError.invalid("\(stage): source must fit 32767 UTF-8 bytes without NUL characters.")}
      do {var parser = try ScriptParser(source); try ScriptValidation.check(parser.parse())}
      catch {throw RaceError.invalid("\(stage): \(error.localizedDescription)")}
    }
  }
  public func applying(to original:DisplayObject) throws -> DisplayObject {
    guard original.canEditScripts else {throw RaceError.invalid("Choose an Enhanced display to edit drawing scripts.")}
    try validate()
    var result = original
    let existing = original.hasScriptStyleSettings
    var payload = existing ? original.legacyPayload! : Data(repeating:0,count:67168)
    if !existing {
      payload.putDouble(100_000_000,256); payload.putDouble(-100_000_000,264)
      payload.putUTF16("Arial",304,128); payload.putFloat(20,560)
      for i in 0..<8 {payload.putU32(i == 0 ? 0x5ee0b5 : 0xffffff,576+i*4)}
      result.legacyType = 50; result.legacyActivation = 1
      // No fabricated legacy common record: authored scripts remain native .orrp/.orrt.
    }
    payload.putU32(UInt32(width)|(UInt32(height)<<16),280)
    payload[284] = persistent ? payload[284]|4 : payload[284] & ~UInt8(4)
    payload.putUTF16(font,432,128)
    for (offset,source) in [(1632,background),(34400,foreground)] {
      payload.replaceSubrange(offset..<offset+32768,with:Data(repeating:0,count:32768))
      payload.replaceSubrange(offset..<offset+source.utf8.count,with:Data(source.utf8))
    }
    result.legacyPayload = payload
    var picture = result.picture ?? PictureSettings();picture.maintainAspect = maintainAspect;result.picture = picture
    if (result.legacyCommon?.count ?? 0) >= 300 {
      result.legacyCommon?[285] = maintainAspect ? 1 : 0
      result.legacyCommon?.putU32(UInt32(width)|(UInt32(height)<<16),296)
    }
    return result
  }
  /// Uses the actual renderer with isolated persistent history; no document changes.
  public func test(object:DisplayObject,data:Telemetry?,sourceTime:Double,displayTime:Double,sourceRate:Double = 1,unit:String,fps:Double) throws -> EnhancedScriptTest {
    var value = try applying(to:object); value.id = UUID()
    guard sourceTime.isFinite,displayTime.isFinite,displayTime >= 0,sourceRate.isFinite,sourceRate > 0,fps.isFinite,fps > 0,fps <= 240 else {throw RaceError.invalid("Invalid script test clock.")}
    guard let canvas = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:OverlayRenderer.colorSpace,bitmapInfo:OverlayRenderer.bitmapInfo) else {throw RaceError.invalid("Cannot allocate the script test canvas.")}
    var messages:[String] = [],failure:String?,omitted = 0
    let interval = 1/fps
    let timeline = EnhancedTimeline(sourceStart:sourceTime-displayTime*sourceRate,sourceStep:interval*sourceRate,displayStart:0,frameInterval:interval)
    let okay = LegacyEnhancedRenderer.draw(canvas,object:value,rect:CGRect(x:0,y:0,width:width,height:height),data:data,time:sourceTime,unit:unit,timeline:timeline,
      failure:{failure = $0},message:{if messages.count < 100 {messages.append(String($0.prefix(2048)))} else {omitted += 1}})
    guard okay,let cg = canvas.makeImage() else {throw RaceError.invalid(failure ?? "Script did not render.")}
    if omitted > 0 {messages.append("… \(omitted) additional messages omitted.")}
    return EnhancedScriptTest(image:cg,messages:messages)
  }
}
extension DisplayObject {
  public var canEditScripts:Bool {hasScriptStyleSettings || (kind == .enhanced && legacyType == nil && hud == nil)}
}
public struct EnhancedScriptTest:@unchecked Sendable {
  public var image:CGImage
  public var messages:[String]
}

enum ScriptValidation {
  // Function semantics remain in ScriptDrawing. Validate even unreachable calls.
  static let functions:Set<String> = Set("print settextoutline drawnumber drawtext drawchar drawtime drawdot drawsquare drawcircle drawline drawlineflat drawlinegradient drawlinegradientrgb drawcurve drawcurvergb drawrect drawrrect draworect drawpoly3 drawpoly4 drawdotgradient drawdotgradientrgb blendcolors blendcolorsrgb getdataindex getdatavalue getcurlapnum getcurlaptime getbestlapnum getbestlaptime getcurbestlapnum getprevbestlapnum getcurbestlaptime getprevbestlaptime getlaptime formatnumber formatheading substr strlen toupper tolower trim chr asc strobe abs ceil floor max min pow sqrt trunc round sin cos tan asin acos atan atan2 hypot".split(separator:" ").map(String.init))
  static func check(_ list:[ScriptStatement]) throws {for statement in list {try check(statement)}}
  static func check(_ statement:ScriptStatement) throws {
    switch statement {
    case .assign(_,_,let value),.expression(let value):try check(value)
    case .branch(let value,let yes,let no):try check(value);try check(yes);if let no {try check(no)}
    case .block(let list):try check(list)
    case .stop:break
    }
  }
  static func check(_ expression:ScriptExpression,depth:Int = 0) throws {
    guard depth < 128 else {throw RaceError.invalid("Enhanced expression nesting limit.")}
    switch expression {
    case .call(let name,let args):guard functions.contains(name) else {throw RaceError.invalid("Unsupported Enhanced function: \(name)")};for arg in args {try check(arg,depth:depth+1)}
    case .unary(_,let value),.assignment(_,let value):try check(value,depth:depth+1)
    case .binary(_,let a,let b):try check(a,depth:depth+1);try check(b,depth:depth+1)
    case .value,.variable:break
    }
  }
}
