import RaceCore
import XCTest
@testable import OpenRaceRender

final class SequenceEditorTests: XCTestCase {
  @MainActor func testSequenceDraftIsIsolatedAndApplyUndoRestoresOriginalRolesAndFiles() throws {
    let model = EditorModel(); var a = MediaInput(name:"A",path:"a.mov",kind:"video",legacyIndex:0); a.duration = 2
    var b = MediaInput(name:"B",path:"b.mov",kind:"video",legacyIndex:1); b.duration = 2; b.joinedTo = 0
    model.project.inputs = [a,b]; model.project.lengthInputIndex = 0; model.dirty = false
    let before = model.project
    var draft = try SequenceDraft(project:model.project,inputID:a.id)
    let gap = try draft.addFiller(after:draft.clips.first?.id)
    XCTAssertEqual(model.project,before); XCTAssertFalse(model.dirty)
    XCTAssertTrue(model.applySequence(draft)); XCTAssertEqual(model.project.duration,5)
    XCTAssertTrue(model.project.inputs.contains(where:{$0.id == gap})); XCTAssertEqual(model.selectedInput,a.id)
    model.undo(); XCTAssertEqual(model.project,before)
    model.redo(); XCTAssertEqual(model.project.duration,5)
  }
  @MainActor func testChildTrimAndGapEditsRefreshRootMetadataAndSupportUndo() throws {
    let model = EditorModel(); var a = MediaInput(name:"A",path:"a.mov",kind:"video",legacyIndex:0); a.duration = 4
    model.project.inputs = [a]; model.project.lengthInputIndex = 0
    var draft = try SequenceDraft(project:model.project,inputID:a.id); try draft.addFiller(after:nil)
    XCTAssertTrue(model.applySequence(draft))
    let child = try XCTUnwrap(model.project.inputs.first(where:{$0.isJoinRoot != true && $0.isTimeFiller != true}))
    var trimmed = child; var timing = InputTiming(); timing.trimEnd = 2; trimmed.timing = timing
    model.inputBinding(child.id).wrappedValue = trimmed
    XCTAssertEqual(model.project.inputs.first?.duration,3); XCTAssertEqual(model.project.duration,3)
    model.undo(); XCTAssertEqual(model.project.duration,5)
    let gap = try XCTUnwrap(model.project.inputs.first(where:{$0.isTimeFiller == true}))
    model.removeInput(gap.id); XCTAssertEqual(model.project.inputs.first?.duration,4); XCTAssertEqual(model.project.duration,4)
    model.undo(); XCTAssertEqual(model.project.duration,5)
  }
  @MainActor func testAddingAudioDoesNotReplaceGeneratedJoinRootAsEmptyTemplatePlaceholder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    var wav = Data("RIFF".utf8)
    func u32(_ n:UInt32) { var n = n.littleEndian; withUnsafeBytes(of:&n) { wav.append(contentsOf:$0) } }
    func u16(_ n:UInt16) { var n = n.littleEndian; withUnsafeBytes(of:&n) { wav.append(contentsOf:$0) } }
    u32(36+8820); wav.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
    wav.append(Data("data".utf8)); u32(8820); wav.append(Data(repeating:0,count:8820))
    let first = root.appendingPathComponent("a.wav"), second = root.appendingPathComponent("b.wav")
    try wav.write(to:first); try wav.write(to:second)
    let model = EditorModel(); var stream = MediaInput(name:"Joined audio",path:"",kind:"audio",legacyIndex:0); stream.isJoinRoot = true; stream.duration = 0.1
    var child = MediaInput(name:"A",path:first.path,kind:"audio",legacyIndex:1); child.duration = 0.1; child.joinedTo = 0
    model.project.inputs = [stream,child]; model.addInputs([second])
    for _ in 0..<200 where model.busy { try await Task.sleep(nanoseconds:10_000_000) }
    XCTAssertFalse(model.busy); XCTAssertNil(model.error)
    XCTAssertEqual(model.project.inputs.count,3)
    XCTAssertEqual(model.project.inputs.first?.id,stream.id); XCTAssertEqual(model.project.inputs.first?.isJoinRoot,true)
    XCTAssertEqual(model.project.inputs.last?.path,second.path); XCTAssertNil(model.project.inputs.last?.joinedTo)
  }
}
