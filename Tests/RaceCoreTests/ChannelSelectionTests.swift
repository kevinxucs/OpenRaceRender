import AppKit
import XCTest
@testable import RaceCore

final class ChannelSelectionTests: XCTestCase {
  func payload(_ channel: String, persistent: Bool = false, gain: Int = 1) -> Data {
    var data = Data(repeating: 0, count: 67168)
    data.putUTF16(channel,0,128); data.putU32(8 | (8 << 16),280)
    data[284] = persistent ? 4 : 0
    let source = Data("DrawRect(0,0,8,8,DataValue*\(gain)*65536,Filled);".utf8)
    data.replaceSubrange(34400..<34400+source.count,with:source)
    return data
  }
  func corrupt(_ data: Data) -> Data {
    var result = data
    for (i,mask) in [UInt8(0x34),0x16,0x6e,0x3c,0x1a,0xa0].enumerated() { result[4+i] ^= mask }
    return result
  }
  func stripped(_ name: String) -> String {
    name.hasPrefix("(") && name.hasSuffix(")") ? String(name.dropFirst().dropLast()) : name
  }
  func red(_ object: DisplayObject, data: Telemetry, time: Double = 1) throws -> UInt8 {
    let c = try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:0,
      space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    XCTAssertTrue(LegacyEnhancedRenderer.draw(c,object:object,rect:CGRect(x:0,y:0,width:8,height:8),
      data:data,time:time,unit:"m/s"))
    return try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))[0]
  }
  func testCodecSkipsGeneratorAtZeroPositionRemainder() {
    // Synthetic zero payload and key; fixed bytes verify interoperability rather
    // than just symmetry (the old faulty transform was also symmetric).
    let key = Array(repeating: UInt8(118),count:31) + [121]
    let encoded = LegacyCodec.transform(Data(repeating:0,count:67168),key:key)
    XCTAssertEqual(encoded.prefix(32).map { String(format:"%02x",$0) }.joined(),
      "311651c419ec18dc53f23bad07c047baaacaeb42cd44c316e54b43d4c4fcb9ab")
    XCTAssertEqual(LegacyCodec.transform(encoded,key:key),Data(repeating:0,count:67168))
  }
  func testAutomaticIgnoresImportedPayloadChannelForEveryAffectedWidget() throws {
    let telemetry = try Telemetry(text:"Time,Speed (m/s),Gear *canbus,RPM (rpm) *canbus,Coolant temperature (.C) *canbus,Intake temperature (.C) *canbus,Engine oil temperature (.C) *obd,Lateral acceleration (G) *calc\n0,10,2,90,90,40,80,0.5\n1,30,4,120,95,45,85,0.8\n")
    let cases: [(ObjectKind,String,String,UInt8)] = [
      (.gear,"Gear","(Gear)",4), (.lights,"Shift Lights","(RPM)",120),
      (.temperature,"Coolant Temperature","Coolant temperature (.C)",95),
      (.temperature,"Intake Air Temperature","Intake temperature (.C)",45),
      (.temperature,"Engine Oil Temperature","Engine oil temperature (.C)",85),
      (.speed,"Peak+Base Speed","(Speed)",30), (.gforce,"Peak G-Force","(Accel Y)",80)
    ]
    for (kind,name,channel,value) in cases {
      var o = DisplayObject(name:name,kind:kind); o.legacyType = 50
      // Deliberately retain the old corrupt payload, as when the user chooses Automatic.
      o.legacyPayload = corrupt(payload(channel,persistent:kind == .speed || kind == .gforce,gain:kind == .gforce ? 100 : 1))
      XCTAssertEqual(try red(o,data:telemetry),value,name)
      if kind == .gforce {
        XCTAssertEqual(LegacyEnhancedRenderer.channelValue(o.resolvedChannel,data:telemetry,time:1,unit:"m/s"),0.8)
      }
      o.legacyPayload = payload(channel)
      o.channel = "Speed (m/s)"
      XCTAssertEqual(try red(o,data:telemetry),30,"Explicit channel must override Automatic for \(name)")
    }
  }
  func testAutomaticSurvivesOldNativeActivationMigrationAndSaveReopen() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer { try? FileManager.default.removeItem(at:file) }
    var project = RaceProject(), object = DisplayObject(name:"Gear",kind:.gear)
    object.legacyType = 50; object.legacyCommon = Data(repeating:0,count:344)
    object.legacyPayload = corrupt(payload("(Gear)")); project.objects = [object]
    try project.save(file)
    let restored = try RaceProject.read(file)
    XCTAssertEqual(restored.objects[0].channel,"")
    XCTAssertEqual(restored.objects[0].resolvedChannel,"gear")
    try restored.save(file)
    XCTAssertEqual(try RaceProject.read(file).objects[0].channel,"")
  }
  func testOldNativeCorruptionIsRepairedWithoutChangingOverridesOrOtherBytes() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp")
    defer { try? FileManager.default.removeItem(at:file) }
    var project = RaceProject()
    for name in ["(Gear)","(RPM)","(Speed)","(Accel Y)","Coolant temperature (.C)","Intake temperature (.C)","Engine oil temperature (.C)"] {
      let clean = payload(name), bad = corrupt(clean)
      var o = DisplayObject(name:"Synthetic",kind:.enhanced); o.legacyType = 50
      o.legacyPayload = bad; o.channel = stripped(bad.utf16(0,128))
      var inherited = ObjectSegment(time:1); inherited.channel = o.channel
      var manual = ObjectSegment(time:2); manual.channel = "Custom channel"
      o.segments = [inherited,manual]; project.objects.append(o)
      o.channel = "Custom channel"; project.objects.append(o)
    }
    try project.save(file)
    let bytes = try Data(contentsOf:file), restored = try RaceProject.read(file)
    for i in stride(from:0,to:restored.objects.count,by:2) {
      let o = restored.objects[i], clean = payload(o.legacyPayload!.utf16(0,128))
      XCTAssertEqual(o.legacyPayload,clean)
      XCTAssertEqual(o.channel,stripped(clean.utf16(0,128)))
      XCTAssertEqual(o.segments?[0].channel,o.channel)
      XCTAssertEqual(o.segments?[1].channel,"Custom channel")
      XCTAssertEqual(restored.objects[i+1].channel,"Custom channel")
    }
    XCTAssertEqual(try Data(contentsOf:file),bytes,"Opening never rewrites the user's file")
    try restored.save(file)
    XCTAssertEqual(try RaceProject.read(file),restored,"Migration is idempotent")
  }
  func testOrdinaryAndLocalizedChannelNamesArePreserved() {
    for channel in ["Custom channel","Température huile (°C)","油温"] {
      var o = DisplayObject(name:"Custom",kind:.enhanced); o.legacyType = 50
      o.legacyPayload = payload(channel); o.channel = channel
      let original = o; LegacyReader.repairOldChannelDecode(&o)
      XCTAssertEqual(o,original)
    }
  }
  func testNumericLabelsDoNotDecodeTheirColorsAsChannelNames() throws {
    var o = DisplayObject(name:"Gear",kind:.gear); o.legacyType = 76
    var data = Data(repeating:0,count:656); data.putU32(0xffffffff,0); data.putUTF16("Text",4,128)
    o.legacyPayload = data; LegacyReader.inferDetails(&o)
    XCTAssertEqual(o.channel,"")
    XCTAssertEqual(o.resolvedChannel,"gear")
    data.putU32(0xffffff,0); data.putFloat(20,644); o.legacyPayload = data
    let telemetry = try Telemetry(text:"Time,Gear *canbus\n0,2\n1,3\n")
    func pixels(_ time: Double) throws -> Data {
      let c = try XCTUnwrap(CGContext(data:nil,width:100,height:60,bitsPerComponent:8,bytesPerRow:0,
        space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      XCTAssertTrue(LegacyStyledRenderer.drawContent(c,object:o,rect:CGRect(x:0,y:0,width:100,height:60),data:telemetry,time:time,unit:"mph",canvasHeight:480))
      return try XCTUnwrap(c.makeImage()?.dataProvider?.data) as Data
    }
    XCTAssertEqual(try pixels(0),try pixels(0.8),"Gear holds until the recorded shift")
    XCTAssertNotEqual(try pixels(0),try pixels(1))
  }
}
