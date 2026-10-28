import RaceCore
import SwiftUI

struct RGBChannelControls:View {
  @Binding var object:DisplayObject
  var mask:Binding<RGBWriteMask> {Binding(get:{object.colorChannels ?? RGBWriteMask()},set:{object.colorChannels = $0})}
  var body:some View {
    DisclosureGroup("RGB color channels") {
      HStack {Toggle("Red",isOn:mask.red);Toggle("Green",isOn:mask.green);Toggle("Blue",isOn:mask.blue)}.toggleStyle(.checkbox)
      Menu("Channel preset") {
        ForEach([("All RGB",7),("Red",1),("Cyan",6),("Green",2),("Magenta",5),("Amber",3),("Blue",4),("None",0)],id:\.0) { name,bits in
          Button(name) {object.colorChannels = RGBWriteMask(bits:UInt8(bits))}
        }
      }
      Text("Disabled channels keep the picture underneath. Applies to this display only.").font(.caption).foregroundStyle(.secondary)
    }
  }
}
extension EditorModel {
  func addStereoPair(left:Int,right:Int,layout:StereoLayout,convergence:Double) throws {
    var updated = project
    let ids = try updated.addStereoPair(left:left,right:right,layout:layout,convergence:convergence)
    checkpoint();project = updated;setSelection(Set(ids));editingSegment = nil
    status = "Added stereo pair · synchronize both cameras, then check eye order and convergence"
  }
}
struct StereoLayoutSheet:View {
  @ObservedObject var model:EditorModel
  @Environment(\.dismiss) var dismiss
  @State var left = -1
  @State var right = -1
  @State var layout:StereoLayout = .redCyan
  @State var convergence:Double = 0
  @State var message:String?
  var cameras:[MediaInput] {model.project.inputs.filter{$0.kind == "video" && $0.joinedTo == nil && $0.isTimeFiller != true}}
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Stereo camera layout").font(.title2.bold())
      Text("Use synchronized recordings from two physical camera positions. Adds a pair above existing cameras and below ordinary overlays. Review layer order if your project contains camera groups.")
      if cameras.count < 2 {Text("Add two independent camera streams first.").foregroundStyle(.orange)}
      Picker("Left-eye camera",selection:$left) {Text("Choose camera").tag(-1);ForEach(cameras){Text($0.name).tag($0.legacyIndex)}}
      Picker("Right-eye camera",selection:$right) {Text("Choose camera").tag(-1);ForEach(cameras){Text($0.name).tag($0.legacyIndex)}}
      Button("Swap eyes") {let old = left;left = right;right = old}
      Picker("Viewing style",selection:$layout) {ForEach(StereoLayout.allCases){Text($0.title).tag($0)}}
      NumberSetting("Horizontal convergence (%)",value:$convergence)
      Text("Adjust synchronization with Timeline → Synchronize cameras side by side. Right-eye display audio is muted; source settings stay unchanged. Anaglyph presets use simple RGB separation, without calibrated color matrices.").font(.caption).foregroundStyle(.secondary)
      if let message {Text(message).foregroundStyle(.orange)}
      Spacer();HStack {Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("Add stereo pair") {
        do {try model.addStereoPair(left:left,right:right,layout:layout,convergence:convergence);dismiss()}catch {message = error.localizedDescription}
      }.disabled(left == right || left < 0 || right < 0 || model.project.sphericalWorkspace == true).keyboardShortcut(.defaultAction)}
    }.padding(24).frame(width:620,height:480).onAppear {left = cameras.first?.legacyIndex ?? -1;right = cameras.dropFirst().first?.legacyIndex ?? -1}
  }
}
