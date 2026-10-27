import AppKit
import XCTest
@testable import RaceCore

final class ScriptDraftTests:XCTestCase {
  func testDraftPreservesInstanceAndOriginalPayloadExtrasAndRejectsInvalidSource() throws {
    var object = DisplayObject(name:"Authored display",kind:.enhanced); object.inputIndex = 4; object.x = 12; object.start = 2
    var draft = EnhancedScriptDraft(object:object); draft.width = 40; draft.height = 24; draft.font = "Helvetica"; draft.persistent = true
    let created = try draft.applying(to:object)
    XCTAssertNil(object.legacyPayload); XCTAssertEqual(created.id,object.id); XCTAssertEqual(created.inputIndex,4); XCTAssertEqual(created.x,12); XCTAssertEqual(created.start,2)
    XCTAssertEqual(EnhancedScriptDraft(object:created),draft); XCTAssertEqual(created.legacyType,50); XCTAssertEqual(created.legacyActivation,1)
    let styled = object.applyingStyle(created)
    XCTAssertEqual(styled.picture?.maintainAspect,true);XCTAssertEqual(styled.id,object.id);XCTAssertEqual(styled.inputIndex,4)
    var imported = created; imported.legacyPayload?[1000] = 123; imported.legacyCommon = Data(repeating:17,count:344)
    draft.foreground = "DrawText(\"Updated\",0,0,White,12,0);"
    let edited = try draft.applying(to:imported)
    var expectedCommon = try XCTUnwrap(imported.legacyCommon);expectedCommon[285] = 1;expectedCommon.putU32(40|(24<<16),296)
    XCTAssertEqual(edited.legacyPayload?[1000],123); XCTAssertEqual(edited.legacyCommon,expectedCommon)
    let fitted = LegacyStyledRenderer.contentRect(edited,in:CGRect(x:0,y:0,width:80,height:80))
    XCTAssertEqual(fitted,CGRect(x:0,y:16,width:80,height:48))
    draft.maintainAspect = false
    XCTAssertEqual(LegacyStyledRenderer.contentRect(try draft.applying(to:imported),in:CGRect(x:0,y:0,width:80,height:80)),CGRect(x:0,y:0,width:80,height:80))
    draft.foreground = "if (False) { NotAFunction(); }"; XCTAssertThrowsError(try draft.validate())
    draft.foreground = "x = 1;\nDrawRect(;"; XCTAssertThrowsError(try draft.validate()) {error in
      XCTAssertTrue(error.localizedDescription.contains("Foreground")); XCTAssertTrue(error.localizedDescription.contains("Line 2"))
    }
    draft.foreground = String(repeating:" ",count:32768); XCTAssertThrowsError(try draft.validate())
    draft.foreground = "\0"; XCTAssertThrowsError(try draft.validate())
    XCTAssertFalse(DisplayObject(name:"Regular gauge",kind:.gauge).canEditScripts)
  }
  func testCompileAndTestDrawsKnownPixelsAndCapturesCurrentPrintMessages() throws {
    let object = DisplayObject(name:"Test display",kind:.enhanced)
    var draft = EnhancedScriptDraft(object:object); draft.width = 8; draft.height = 8
    draft.background = "Print(\"background\"); DrawRect(0,0,8,8,Red,Filled); count = 0;"
    draft.foreground = "count += 1; Print(\"foreground\", count); DrawRect(0,0,4,8,Blue,Filled);"
    draft.persistent = true
    let result = try draft.test(object:object,data:nil,sourceTime:2,displayTime:2,unit:"mph",fps:30)
    XCTAssertEqual(result.messages,["background","foreground 61.0"])
    XCTAssertEqual(result.image.width,8); XCTAssertEqual(result.image.height,8)
    let c = try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    c.draw(result.image,in:CGRect(x:0,y:0,width:8,height:8)); let bytes = try XCTUnwrap(c.data?.assumingMemoryBound(to:UInt8.self))
    XCTAssertEqual(bytes[0],0); XCTAssertEqual(bytes[2],255); XCTAssertEqual(bytes[7*4],255); XCTAssertEqual(bytes[7*4+2],0)
    let again = try draft.test(object:object,data:nil,sourceTime:2,displayTime:2,unit:"mph",fps:30)
    XCTAssertEqual(again.messages,result.messages)
    draft.persistent = false
    let reset = try draft.test(object:object,data:nil,sourceTime:2,displayTime:2,unit:"mph",fps:30)
    XCTAssertEqual(reset.messages,["background","foreground 1.0"])
  }
  func testRecordedRateAndSourceFreeDisplayClockAndNativePersistence() throws {
    var object = DisplayObject(name:"Authored script",kind:.enhanced); object.x = 0; object.y = 0; object.width = 100; object.height = 100
    var draft = EnhancedScriptDraft(object:object); draft.width = 20; draft.height = 20; draft.background = ""; draft.foreground = "Print(SampleTime, DisplayTime, DataValue); DrawRect(0,0,20,20,Green,Filled);"
    let telemetry = try Telemetry(text:"Time,Speed\n0,10\n10,20\n"); object.channel = "Speed"
    let result = try draft.test(object:object,data:telemetry,sourceTime:5,displayTime:2,sourceRate:2,unit:"m/s",fps:30)
    XCTAssertEqual(result.messages.count,1); XCTAssertTrue(result.messages[0].hasPrefix("5.0 2.0 "))
    object = try draft.applying(to:object)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orrp"); defer {try? FileManager.default.removeItem(at:file)}
    var p = RaceProject();p.objects = [object];try p.save(file)
    XCTAssertEqual(EnhancedScriptDraft(object:try RaceProject.read(file).objects[0]),draft)
    XCTAssertEqual(EnhancedScriptDraft(object:try p.reusableLayout().objects[0]),draft)
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp))
    // Source-free SampleTime/DisplayTime follow the object's elapsed project clock.
    draft.foreground = "if (DisplayTime >= 2) DrawRect(0,0,20,20,Green,Filled);"
    object = try draft.applying(to:object);object.inputIndex = -1;object.start = 1;p.objects = [object]
    let c = try XCTUnwrap(CGContext(data:nil,width:20,height:20,bitsPerComponent:8,bytesPerRow:80,space:OverlayRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:[:]),time:3,size:CGSize(width:20,height:20))
    XCTAssertEqual(c.data?.assumingMemoryBound(to:UInt8.self)[1],255)
  }
  func testCancellationAndExpressionLimitsBoundTestWork() async throws {
    let task = Task.detached {
      while !Task.isCancelled {await Task.yield()}
      var parser = try ScriptParser(String(repeating:"x += 1;",count:500))
      let machine = ScriptMachine(variables:[:]) {_,_ in .number(0)}
      try machine.run(parser.parse())
    }
    task.cancel()
    do {try await task.value;XCTFail("Canceled script continued")} catch {XCTAssertTrue(error is CancellationError)}
    var draft = EnhancedScriptDraft(object:DisplayObject(name:"Bounded",kind:.enhanced))
    draft.foreground = "x="+String(repeating:"1+",count:200)+"1;"
    XCTAssertThrowsError(try draft.validate())
  }
}
