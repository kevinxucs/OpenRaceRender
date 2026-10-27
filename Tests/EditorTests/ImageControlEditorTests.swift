import RaceCore
import XCTest
@testable import OpenRaceRender

final class ImageControlEditorTests: XCTestCase {
  @MainActor func testImageControlsChooseDataWithoutLosingArtworkAndSupportUndoAndSegments() throws {
    let model = EditorModel()
    model.project.inputs = [MediaInput(name:"Artwork",path:"",kind:"image",legacyIndex:4),MediaInput(name:"Data",path:"",kind:"data",legacyIndex:9)]
    var image = DisplayObject(name:"Lamp",kind:.image); image.inputIndex = 4; image.embeddedImage = Data([1,2,3])
    model.project.objects = [image]; model.selected = image.id
    let controls = ImageControlControls(object:model.objectBinding(image.id),inputs:model.project.inputs)
    controls.settings.mode.wrappedValue = .greaterOrEqual
    XCTAssertEqual(model.project.objects[0].inputIndex,9); XCTAssertEqual(model.project.objects[0].embeddedImage,image.embeddedImage)
    XCTAssertTrue(model.project.objects[0].imageUsesData)
    model.undo(); XCTAssertEqual(model.project.objects,[image])
    model.editingSegment = 1; controls.settings.mode.wrappedValue = .proportional
    XCTAssertFalse(model.project.objects[0].imageUsesData)
    XCTAssertEqual(model.project.objects[0].resolved(at:1).inputIndex,9)
    XCTAssertTrue(model.project.objects[0].resolved(at:1).imageUsesData)
    model.undo(); XCTAssertEqual(model.project.objects,[image])
  }
  @MainActor func testMappedImageWidgetUsesDataSourceWhileStaticImagesKeepArtworkRole() {
    let model = EditorModel()
    model.project.inputs = [MediaInput(name:"Image",path:"",kind:"image",legacyIndex:4),MediaInput(name:"Logger",path:"",kind:"data",legacyIndex:9)]
    var o = DisplayObject(name:"Image",kind:.image)
    model.addWidget(WidgetStyle(id:"static",name:"Static",object:o))
    XCTAssertEqual(model.project.objects.last?.inputIndex,4)
    var s = ImageControlSettings(); s.mode = .proportional; o.imageControl = s
    model.addWidget(WidgetStyle(id:"controlled",name:"Controlled",object:o))
    XCTAssertEqual(model.project.objects.last?.inputIndex,9)
  }
}
