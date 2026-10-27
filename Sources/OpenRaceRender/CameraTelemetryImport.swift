import Foundation
import RaceCore
import SwiftUI

extension EditorModel {
  var cameraDataOffer:MediaInput? {
    project.inputs.first { source in cameraDataCandidates.contains(source.id) && source.kind == "video" && !project.inputs.contains(where:{$0.cameraVideoID == source.id}) }
  }
  @discardableResult func addCameraData(_ id:UUID) async -> Bool {
    guard !busy,let source = project.inputs.first(where:{$0.id == id && $0.kind == "video"}),!project.inputs.contains(where:{$0.cameraVideoID == id}) else {return false}
    let revision = documentRevision;busy = true;pause();defer {busy = false}
    do {
      let data = try await Task.detached {try Telemetry(url:URL(fileURLWithPath:source.path))}.value
      guard documentRevision == revision,project.inputs.contains(source) else {return false}
      var input = MediaInput(name:source.name+" · camera data",path:source.path,kind:"data")
      input.cameraVideoID = id;input.duration = data.duration
      installInput(input,data:data);cameraDataCandidates.remove(id)
      configurePlayers();status = "Camera data added · verify synchronization against a visible event"
      return true
    } catch {if documentRevision == revision {self.error = error.localizedDescription};return false}
  }
}

struct CameraDataOffer:View {
  @ObservedObject var model:EditorModel
  var body:some View {
    if let source = model.cameraDataOffer {
      HStack {
        Label("Embedded GoPro telemetry found in \(source.name)",systemImage:"location.circle")
        Spacer()
        Button("Add camera data") {Task {await model.addCameraData(source.id)}}.disabled(model.busy)
        Button("Skip") {model.cameraDataCandidates.remove(source.id)}
      }.font(.system(size:11)).padding(.horizontal,20).padding(.vertical,8)
    }
  }
}
