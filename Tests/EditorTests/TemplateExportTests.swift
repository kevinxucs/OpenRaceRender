import AppKit
import RaceCore
import XCTest
@testable import OpenRaceRender

final class TemplateExportTests: XCTestCase {
  @MainActor func fixture() -> EditorModel {
    let m = EditorModel()
    m.project.inputs = [MediaInput(name:"Session video",path:"/private/video.mov",kind:"video",legacyIndex:1),
      MediaInput(name:"Session data",path:"/private/data.csv",kind:"data",legacyIndex:4)]
    var camera = DisplayObject(name:"Camera",kind:.video); camera.inputIndex = 1
    var tyre = DisplayObject(name:"Tyres",kind:.speed); tyre.inputIndex = 4
    var pedals = DisplayObject(name:"Pedals",kind:.shape); pedals.inputIndex = -1
    m.project.objects = [camera,tyre,pedals]
    return m
  }
  @MainActor func testDraftSelectsArbitrarySubsetRenamesRolesWithoutEditingProject() throws {
    let m = fixture(), original = m.project
    m.dirty = false; m.saveTemplate()
    XCTAssertEqual(m.templateIncludedIDs,Set(original.objects.dropFirst().map(\.id)))
    XCTAssertEqual(m.templateUsedInputs,[4])
    XCTAssertEqual(m.templateInputNames,[1:"Video 1",4:"Data 1"])
    m.templateChecked(original.objects[1].id).wrappedValue = false
    m.templateChecked(original.objects[0].id).wrappedValue = true
    m.templateObjectName(original.objects[2]).wrappedValue = "Pedal cluster"
    m.templateInputName(original.inputs[0]).wrappedValue = "Front camera"
    m.templateName = "Road kit"
    let saved = try m.templateDraft()
    XCTAssertEqual(saved.name,"Road kit")
    XCTAssertEqual(saved.objects.map(\.name),["Camera","Pedal cluster"])
    XCTAssertEqual(saved.inputs.map(\.name),["Front camera"])
    XCTAssertEqual(m.project,original); XCTAssertFalse(m.dirty)
    m.showSaveTemplate = false; m.saveTemplate()
    XCTAssertEqual(m.templateObjectNames[original.objects[2].id],"Pedals","Reopening discards the cancelled draft")
    m.templateObjectIDs = []; XCTAssertThrowsError(try m.templateDraft())
  }
  @MainActor func testGroupCheckboxAndMemberRefinementPreserveOnlyRequiredAncestors() throws {
    let m = fixture(), a = m.project.objects[1].id, b = m.project.objects[2].id
    let group = try m.project.groupDisplays([a,b])
    m.selected = a; m.saveSelectedStyle()
    XCTAssertEqual(m.templateIncludedIDs,[a,group]); XCTAssertFalse(m.templateIsSingleStyle)
    XCTAssertFalse(m.templateChecked(group).wrappedValue)
    m.templateChecked(group).wrappedValue = true
    XCTAssertTrue(m.templateChecked(group).wrappedValue); XCTAssertEqual(m.templateIncludedIDs,[a,b,group])
    m.templateChecked(b).wrappedValue = false
    XCTAssertFalse(m.templateChecked(group).wrappedValue)
    XCTAssertEqual(try m.templateDraft().objects.count,2)
    m.templateChecked(group).wrappedValue = false
    XCTAssertTrue(m.templateIncludedIDs.isEmpty)
  }
  @MainActor func testSaveSelectionUsesMultipleObjectsAndKeepsSingleStyleFormatAccurate() throws {
    let m = fixture(), a = m.project.objects[1].id, b = m.project.objects[2].id
    m.setSelection([a,b],primary:a); m.saveSelectedStyle()
    XCTAssertEqual(m.templateIncludedIDs,[a,b]); XCTAssertFalse(m.templateIsSingleStyle)
    m.templateChecked(b).wrappedValue = false
    XCTAssertTrue(m.templateIsSingleStyle)
    let style = try m.templateDraft()
    XCTAssertNoThrow(try LegacyWriter.data(style,format:.rro))
    m.selected = b; m.saveSelectedStyle()
    XCTAssertEqual(m.templateIncludedIDs,[b]); XCTAssertTrue(m.templateIsSingleStyle)
  }
  @MainActor func testSelectAllInTemplateFieldPreservesCanvasSelection() throws {
    let m = fixture(); m.selected = m.project.objects[1].id
    let selection = m.selectedIDs
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let field = NSTextField(string:"Vehicle sensors"); field.frame = NSRect(x:20,y:20,width:300,height:30)
    window.contentView?.addSubview(field); field.selectText(nil)
    let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
    editor.setSelectedRange(NSRange(location:0,length:0))
    m.selectAll(focusedResponder: window.firstResponder)
    XCTAssertEqual(editor.selectedRange(),NSRange(location:0,length:field.stringValue.utf16.count))
    XCTAssertEqual(m.selectedIDs,selection)
    window.makeFirstResponder(window.contentView)
    m.selectAll(focusedResponder: window.firstResponder)
    XCTAssertEqual(m.selectedIDs,Set(m.project.objects.map(\.id)))
  }
}
