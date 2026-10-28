import RaceCore
import SwiftUI

extension EditorModel {
  func fillSphericalSelection() {
    guard project.sphericalWorkspace == true,let bounds = project.selectionBounds(selectedIDs,at:editingSegment) else {return}
    checkpoint();project.transformDisplays(selectedIDs,from:bounds,to:project.workspaceBounds,at:editingSegment)
  }
  func setSphericalWorkspace(_ enabled:Bool) {
    guard enabled != (project.sphericalWorkspace == true) else {return}
    checkpoint();project.setSphericalWorkspace(enabled)
  }
}
struct SphericalPictureControls:View {
  @Binding var settings:PictureSettings
  var projection:Binding<SphericalProjection> {Binding(get:{settings.spherical ?? SphericalProjection()},set:{settings.spherical = $0})}
  var body:some View {
    DisclosureGroup("Fisheye / 360 projection") {
      Toggle("Enable 360 source controls",isOn:Binding(get:{settings.spherical != nil},set:{settings.spherical = $0 ? SphericalProjection() : nil}))
      if let value = settings.spherical {
        Picker("Input format",selection:projection.mode) {Text("Equirectangular panorama").tag(SphericalProjection.Mode.equirectangular);Text("Single fisheye lens").tag(SphericalProjection.Mode.fisheye)}
        NumberSetting("Pan (degrees)",value:projection.pan)
        if value.mode == .fisheye {
          NumberSetting("Lens field of view (degrees)",value:projection.fieldOfView)
          Picker("Lens points",selection:projection.axis) {Text("Up (360fly style)").tag(SphericalProjection.Axis.up);Text("Forward").tag(SphericalProjection.Axis.forward)}
          HStack {NumberSetting("Center X (0–1)",value:projection.centerX);NumberSetting("Center Y (0–1)",value:projection.centerY)}
          NumberSetting("Radius / shorter edge",value:projection.radius)
          Text("Equidistant single-lens calibration. Uncovered directions remain transparent. Use your camera’s stitching software for dual-lens footage.").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }
}
struct SphericalWorkspaceControls:View {
  @ObservedObject var model:EditorModel
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      Toggle("360° equirectangular workspace",isOn:Binding(get:{model.project.sphericalWorkspace == true},set:{enabled in
        model.setSphericalWorkspace(enabled)
      }))
      if model.project.sphericalWorkspace == true {
        Text("\(model.project.width) × \(model.project.height) · coordinates −100% to 200%. Normal templates occupy the center third; place overlays near Y 0–100%.").font(.caption).foregroundStyle(.secondary)
        Toggle("Show 360 view guide",isOn:$model.showSphericalGuide)
        if model.selected != nil {Button("Fill panorama with selection",action:model.fillSphericalSelection)}
      }
    }
  }
}
