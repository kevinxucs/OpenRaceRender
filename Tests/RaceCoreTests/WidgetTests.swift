import AppKit
import Compression
import XCTest
@testable import RaceCore

final class WidgetTests: XCTestCase {
  func canvas(_ width: Int = 100,_ height: Int = 100) -> CGContext {
    CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  }
  func testEnhancedRGBBlendUsesTheBrighterAdditiveTransition() throws {
    let drawing = ScriptDrawing(context:canvas(),font:"Arial",data:nil,time:0,unit:"mph")
    let args: [ScriptValue] = [.number(0xff0000),.number(0x00ff00),.number(0.25)]
    XCTAssertEqual(try drawing.call("blendcolors",args).number,Double(0xbf3f00))
    XCTAssertEqual(try drawing.call("blendcolorsrgb",args).number,Double(0xff7f00))
    XCTAssertEqual(try drawing.call("blendcolorsrgb",[.number(0xff0000),.number(0x00ff00),.number(0.5)]).number,Double(0xffff00))
  }
  func testSavedColorsSurvivePNGEncodingAsSRGB() throws {
    let c = canvas(2,2);c.setFillColor(OverlayRenderer.color("#1DDA05"));c.fill(CGRect(x:0,y:0,width:2,height:2))
    let rep = NSBitmapImageRep(cgImage:try XCTUnwrap(c.makeImage()))
    let png = try XCTUnwrap(rep.representation(using:.png,properties:[:]))
    let decoded = try XCTUnwrap(NSBitmapImageRep(data:png))
    var samples = [Int](repeating:0,count:decoded.samplesPerPixel)
    samples.withUnsafeMutableBufferPointer { decoded.getPixel($0.baseAddress!,atX:0,y:0) }
    XCTAssertEqual(Array(samples.prefix(3)),[29,218,5])
  }
  func testEnhancedTextLabelIsDrawnAboveTheForeground() throws {
    var o = DisplayObject(name:"Synthetic label",kind:.enhanced);o.legacyType = 50
    var d = Data(repeating:0,count:67168)
    d.putU32(100 | (100 << 16),280);d[284] = 2;d[569] = 1
    d.putUTF16("L",128,128);d.putUTF16("Arial",304,128);d.putU32(0xffffff,288)
    d.putU32(50 | (80 << 16),296);d.putFloat(20,560)
    let script = Data("DrawRect(0,0,100,100,Red,Filled);".utf8)
    d.replaceSubrange(34400..<34400+script.count,with:script);o.legacyPayload = d
    let c = canvas();XCTAssertTrue(LegacyEnhancedRenderer.draw(c,object:o,rect:CGRect(x:0,y:0,width:100,height:100),data:nil,time:0,unit:"mph"))
    let bytes = try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))
    let whitePixels = (0..<10000).filter { bytes[$0*4] > 220 && bytes[$0*4+1] > 220 && bytes[$0*4+2] > 220 }
    XCTAssertGreaterThan(whitePixels.count,10)
  }
  func testAutomaticBarRangeUsesMeasuredChannelBounds() throws {
    var o = DisplayObject(name:"Synthetic range",kind:.bar);o.legacyType = 31;o.channel = "Throttle"
    var d = Data(repeating:0,count:640)
    for offset in [256,264] { let bits = Double(100_000_000).bitPattern;d.putU32(UInt32(truncatingIfNeeded:bits),offset);d.putU32(UInt32(bits >> 32),offset+4) }
    d.putU32(0x00ff00,308);d.putU32(0x00ff00,632);d.putU32(0xff000000,316);d.putU32(0xff000000,332)
    o.legacyPayload = d
    let telemetry = try Telemetry(text:"Time,Throttle\n0,18\n1,90\n")
    for (time,expected) in [(0.0,false),(1.0,true)] {
      let c = canvas(100,10)
      XCTAssertTrue(LegacyStyledRenderer.draw(c,object:o,rect:CGRect(x:0,y:0,width:100,height:10),data:telemetry,time:time,unit:"mph",canvasHeight:480))
      let bytes = try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))
      XCTAssertEqual(bytes[50*4+1] > 200,expected)
    }
  }
  func testLegacyAspectFitCentersTheSavedCanvas() {
    var o = DisplayObject(name:"Synthetic bar",kind:.bar)
    var common = Data(repeating:0,count:344)
    common[285] = 1;common.putU32(600 | (100 << 16),296);o.legacyCommon = common
    let area = LegacyStyledRenderer.contentRect(o,in:CGRect(x:10,y:20,width:800,height:100))
    XCTAssertEqual(area,CGRect(x:110,y:20,width:600,height:100))
    let small = LegacyStyledRenderer.contentRect(o,in:CGRect(x:0,y:0,width:188.3,height:14.4))
    XCTAssertEqual(small.height,15,accuracy:0.0001)
    XCTAssertEqual(small.width,90,accuracy:0.0001)
    common[285] = 0;o.legacyCommon = common
    XCTAssertEqual(LegacyStyledRenderer.contentRect(o,in:CGRect(x:10,y:20,width:800,height:100)),CGRect(x:10,y:20,width:800,height:100))
  }
  func testLegacyGaugeStartsLeftAndSweepsClockwise() {
    var g = GaugeSettings();g.rotation = 90;g.sweep = 180
    XCTAssertEqual(cos(LegacyStyledRenderer.gaugeAngle(g,factor:0)),-1,accuracy:0.00001)
    XCTAssertEqual(sin(LegacyStyledRenderer.gaugeAngle(g,factor:0.5)),1,accuracy:0.00001)
    XCTAssertEqual(cos(LegacyStyledRenderer.gaugeAngle(g,factor:1)),1,accuracy:0.00001)
    g.counterClockwise = true
    XCTAssertEqual(sin(LegacyStyledRenderer.gaugeAngle(g,factor:0.5)),-1,accuracy:0.00001)
  }
  func testGaugeLayerVisibilityUsesTheSavedTransparencyByte() {
    var o = DisplayObject(name:"Synthetic tach",kind:.rpm);o.legacyType = 30
    var payload = Data(repeating:0,count:712)
    payload[616] = 1;payload[617] = 1
    payload.putU32(0xffabcdef,336);payload.putU32(0xff000000,300);payload.putU32(0xffffff,332)
    o.legacyPayload = payload;LegacyReader.inferDetails(&o)
    XCTAssertEqual(o.gauge?.showNumber,false)
    XCTAssertEqual(o.gauge?.showFace,false)
    XCTAssertEqual(o.gauge?.showLabels,true)
  }
  func testCurrentBestLapDoesNotIncludeFutureLaps() throws {
    let telemetry = try Telemetry(text:"Time,Lap,Distance\n0,0,0\n10,1,100\n70,2,1100\n120,3,2100\n180,4,3100\n")
    XCTAssertNil(telemetry.bestLap(at:30))
    XCTAssertEqual(telemetry.bestLap(at:80)?.number,1)
    XCTAssertEqual(telemetry.bestLap(at:130)?.number,2)
    XCTAssertEqual(telemetry.bestLap?.number,2)
  }
  func testSpeedAccelerationUsesAUnitIndependentTwoSecondWindow() throws {
    let telemetry = try Telemetry(text:"Time,Speed (km/h)\n0,0\n1,36\n2,72\n3,108\n")
    XCTAssertEqual(try XCTUnwrap(telemetry.speedAcceleration(at:1.5)),10/9.80665,accuracy:0.00001)
    XCTAssertEqual(try XCTUnwrap(telemetry.speedAcceleration(at:0)),10/9.80665,accuracy:0.00001)
  }
  func testLapDeltaInterpolatesBetweenReferenceDistanceSamples() throws {
    let telemetry = try Telemetry(text:"Time,Lap,Distance\n0,0,0\n10,1,100\n20,1,200\n30,1,300\n40,2,400\n50,2,550\n60,2,700\n70,3,800\n")
    let delta = telemetry.delta(at:45,reference:telemetry.bestLap(at:45))
    XCTAssertEqual(try XCTUnwrap(delta),-2.5,accuracy:0.00001)
  }
  func program(_ source: String) throws -> [ScriptStatement] {
    var parser = try ScriptParser(source); return try parser.parse()
  }
  func testScriptArithmeticBranchesAndCaseInsensitiveVariables() throws {
    let machine = ScriptMachine(variables:[:]) { _,_ in .number(0) }
    try machine.run(program("// synthetic\nValue = 3; VALUE += 2; if (value == 5) { result = pow(2, 3); } else { result = 0; }"))
    // Function calls are supplied by the renderer; test the language's own arithmetic separately.
    try machine.run(program("if (value > 4) { result = (value * 3) - 2; } else result = 0;"))
    XCTAssertEqual(machine.variables["value"]?.number,5)
    XCTAssertEqual(machine.variables["result"]?.number,13)
  }
  func testScriptStringsShortCircuitAndNewlineStatements() throws {
    var calls = 0
    let machine = ScriptMachine(variables:[:]) { _,_ in calls += 1; return .number(1) }
    try machine.run(program("title = \"Lap\"\ntitle += \" 2\"\nif (0 && unavailable())\n { value = 3; }\nelse if (1)\n { value = 7; }"))
    XCTAssertEqual(machine.variables["title"]?.string,"Lap 2")
    XCTAssertEqual(machine.variables["value"]?.number,7)
    XCTAssertEqual(calls,0)
  }
  func testScriptRejectsPropertiesLoopsAndExcessiveNesting() throws {
    XCTAssertThrowsError(try program("file.read(\"anything\");"))
    XCTAssertThrowsError(try program(String(repeating:"(",count:100)+"1"+String(repeating:")",count:100)))
    let c = CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let drawing = ScriptDrawing(context:c,font:"Arial",data:nil,time:0,unit:"mph")
    let machine = ScriptMachine(variables:[:]) { name,args in try drawing.call(name,args) }
    XCTAssertThrowsError(try machine.run(program("while(1) { x = 1; }")))
    XCTAssertThrowsError(try drawing.call("system",[.string("anything")]))
  }
  func testScriptInstructionAndExpressionDepthLimits() throws {
    let machine = ScriptMachine(variables:[:]) { _,_ in .number(0) }
    machine.budget = 3
    XCTAssertThrowsError(try machine.run(program("x = 1+2+3+4;")))
    let long = "x = "+Array(repeating:"1",count:300).joined(separator:"+")+";"
    let bounded = ScriptMachine(variables:[:]) { _,_ in .number(0) }
    XCTAssertThrowsError(try bounded.run(program(long)))
  }
  func syntheticBitmap() -> Data {
    // Original bottom-up legacy BGRA pixels: blue/red below green/yellow.
    Data([8,0,2,0,2,0,0x20,1,255,0,0,255,0,0,255,255,0,255,0,255,0,255,255,255])
  }
  func testEmbeddedBitmapDecodesWithoutVendorFixtures() throws {
    let png = try XCTUnwrap(LegacyArtwork.png(syntheticBitmap()))
    let rep = try XCTUnwrap(NSBitmapImageRep(data:png))
    XCTAssertEqual(rep.pixelsWide,2);XCTAssertEqual(rep.pixelsHigh,2)
    let blue = try XCTUnwrap(rep.colorAt(x:0,y:1)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(blue.blueComponent,0.95);XCTAssertLessThan(blue.redComponent,0.05)
    let green = try XCTUnwrap(rep.colorAt(x:0,y:0)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(green.greenComponent,0.95);XCTAssertLessThan(green.blueComponent,0.05)
    let encoded = try LegacyWriter.bitmap(png)
    XCTAssertEqual(Data(encoded.dropFirst(8)),Data(syntheticBitmap().dropFirst(8)))
    XCTAssertNil(LegacyArtwork.png(Data(syntheticBitmap().dropLast())))
  }
  func testCompressedEmbeddedBitmapAndBounds() throws {
    let raw = syntheticBitmap()
    var compressed = [UInt8](repeating:0,count:1024)
    let count = compressed.withUnsafeMutableBufferPointer { destination in
      raw.withUnsafeBytes { source in compression_encode_buffer(destination.baseAddress!,destination.count,source.bindMemory(to:UInt8.self).baseAddress!,raw.count,nil,COMPRESSION_ZLIB) }
    }
    XCTAssertGreaterThan(count,0)
    var container = Data(repeating:0,count:4);container.putU32(UInt32(count)|0x80000000,0);container.append(contentsOf:compressed.prefix(count))
    XCTAssertNotNil(LegacyArtwork.png(container))
    container.putU32(0xffffffff,0);XCTAssertNil(LegacyArtwork.png(container))
  }
  func testPaddedNativeBitmapWrapperPreservesFollowingRecord() throws {
    let pixels = syntheticBitmap()+Data(repeating:0,count:64)
    var container = Data(repeating:0,count:4);container.putU32(UInt32(pixels.count),0);container.append(pixels)
    let end = container.count;container.append(Data(repeating:0,count:4))
    var cursor = 0
    let decoded = try XCTUnwrap(LegacyProjectSettings.image(container,cursor:&cursor))
    XCTAssertEqual(cursor,end);XCTAssertEqual(decoded,pixels)
    XCTAssertNotNil(LegacyArtwork.png(decoded))
    XCTAssertNil(try LegacyProjectSettings.image(container,cursor:&cursor));XCTAssertEqual(cursor,end+4)
    var truncated = container;truncated.putU32(UInt32(container.count+10),0);cursor = 0
    XCTAssertThrowsError(try LegacyProjectSettings.image(truncated,cursor:&cursor))
  }
  func testLocalLegacyScriptsWhenLibraryIsProvided() throws {
    guard let path = ProcessInfo.processInfo.environment["OPENRACERENDER_LIBRARY"] else { throw XCTSkip("Optional local-library fidelity check.") }
    let root = URL(fileURLWithPath:path)
    let files = (FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "rro" }
    var count = 0,failed: [String] = []
    for file in files {
      let p = try RaceProject.read(file)
      for o in p.objects where o.legacyType == 50 {
        let header = o.channel.isEmpty ? "RPM" : o.channel
        let data = try Telemetry(text:"Time,\""+header+"\"\n0,3\n1,3\n")
        let c = CGContext(data:nil,width:240,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        count += 1
        if !LegacyEnhancedRenderer.draw(c,object:o,rect:CGRect(x:0,y:0,width:240,height:240),data:data,time:0.5,unit:"mph",failure:{ print(file.lastPathComponent+": "+$0) }) { failed.append(file.lastPathComponent) }
      }
    }
    print("Local Enhanced widgets rendered: \(count-failed.count)/\(count)")
    XCTAssertTrue(failed.isEmpty,"Unsupported local styles: "+failed.joined(separator:", "))
  }
}
