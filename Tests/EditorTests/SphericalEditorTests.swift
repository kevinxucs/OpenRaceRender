import XCTest
@testable import RaceCore
@testable import OpenRaceRender

final class SphericalEditorTests:XCTestCase {
  @MainActor func testWorkspaceUndoNegativeDropNudgeAndAlignment() throws {
    let model = EditorModel();model.project.objects = []
    model.setSphericalWorkspace(true)
    XCTAssertEqual(model.project.width,3840);XCTAssertEqual(model.project.height,1920)
    model.project.width = 300;model.project.height = 150
    model.addObject(.shape,at:CGPoint(x:-50,y:50))
    let before = try XCTUnwrap(model.project.objects.first);XCTAssertLessThan(before.x,0)
    model.nudgeWidget(x:1,y:0)
    XCTAssertEqual(model.project.objects[0].x,before.x+1,accuracy:1e-8)
    model.alignWidget("Left");XCTAssertEqual(model.project.objects[0].x,-100)
    model.alignWidget("Right");XCTAssertEqual(model.project.objects[0].x,200-before.width)
    model.undo();XCTAssertEqual(model.project.objects[0].x,-100)
    model.fillSphericalSelection();XCTAssertEqual(model.project.objects[0].x,-100);XCTAssertEqual(model.project.objects[0].width,300)
    model.undo();XCTAssertEqual(model.project.objects[0].width,before.width)
    model.setSphericalWorkspace(false);XCTAssertNil(model.project.sphericalWorkspace)
    model.undo();XCTAssertEqual(model.project.sphericalWorkspace,true)
  }
  @MainActor func testTemplateKeepsExpandedCoordinatesAndProjectionWithoutSessionPaths() throws {
    let model = EditorModel();model.setSphericalWorkspace(true)
    var object = DisplayObject(name:"Panorama",kind:.video);object.x = -100;object.y = -100;object.width = 300;object.height = 300
    var picture = PictureSettings();picture.spherical = SphericalProjection();picture.spherical?.pan = 45;object.picture = picture
    object.inputIndex = 0
    model.project.inputs = [MediaInput(name:"Camera",path:"/private/example.mp4",kind:"video")];model.project.objects = [object]
    let layout = try model.project.reusableLayout()
    XCTAssertEqual(layout.sphericalWorkspace,true);XCTAssertEqual(layout.objects[0].picture?.spherical?.pan,45)
    XCTAssertTrue(layout.inputs.allSatisfy{$0.path.isEmpty})
    let other = EditorModel();other.apply(layout,replace:true,mapping:[:])
    XCTAssertEqual(other.project.sphericalWorkspace,true);XCTAssertEqual(other.project.objects[0].x,-100)
    other.undo();XCTAssertNil(other.project.sphericalWorkspace)
  }
}
