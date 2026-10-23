import AppKit
import Compression
import XCTest
@testable import RaceCore

final class WidgetTests: XCTestCase {
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
    // Original test pixels in the legacy BGRA container: blue, red, green, yellow.
    Data([8,0,2,0,2,0,0x20,1,255,0,0,255,0,0,255,255,0,255,0,255,0,255,255,255])
  }
  func testEmbeddedBitmapDecodesWithoutVendorFixtures() throws {
    let png = try XCTUnwrap(LegacyArtwork.png(syntheticBitmap()))
    let rep = try XCTUnwrap(NSBitmapImageRep(data:png))
    XCTAssertEqual(rep.pixelsWide,2);XCTAssertEqual(rep.pixelsHigh,2)
    let blue = try XCTUnwrap(rep.colorAt(x:0,y:0)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(blue.blueComponent,0.95);XCTAssertLessThan(blue.redComponent,0.05)
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
