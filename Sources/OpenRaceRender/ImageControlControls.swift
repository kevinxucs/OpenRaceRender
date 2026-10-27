import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

struct ImageControlControls: View {
  @Binding var object: DisplayObject
  var inputs: [MediaInput]
  @State private var error: String?
  var settings: Binding<ImageControlSettings> {
    Binding(get:{object.imageControl ?? ImageControlSettings()},set:{ value in
      var updated = object; updated.imageControl = value
      if value.usesData, !inputs.contains(where: { $0.legacyIndex == updated.inputIndex && $0.kind == "data" }) {
        updated.inputIndex = inputs.first { $0.kind == "data" && $0.joinedTo == nil }?.legacyIndex ?? -1
      }
      object = updated
    })
  }
  var body: some View {
    VStack(alignment:.leading,spacing:10) {
      Divider()
      Text("IMAGE CONTROL").font(.caption).foregroundStyle(muted)
      Button("Choose embedded image…",action:chooseArtwork)
      if object.artwork != nil || object.embeddedImage != nil {
        Text("Artwork is embedded in this project and reusable styles.").font(.caption2).foregroundStyle(muted)
      }
      Picker("Image mode",selection:settings.mode) {
        ForEach(ImageControlSettings.Mode.allCases,id:\.self) { Text($0.title).tag($0) }
      }
      if settings.wrappedValue.usesData {
        Picker("Output",selection:settings.output) {
          ForEach(ImageControlSettings.Output.allCases,id:\.self) { Text($0.title).tag($0) }
        }
        if settings.wrappedValue.mode != .greaterOrEqual { NumberSetting(settings.wrappedValue.mode == .lessOrEqual ? "At or below" : "Input low",value:settings.inputMinimum) }
        if settings.wrappedValue.mode != .lessOrEqual { NumberSetting(settings.wrappedValue.mode == .greaterOrEqual ? "At or above" : "Input high",value:settings.inputMaximum) }
        NumberSetting(settings.wrappedValue.mode == .proportional ? "Output low" : "When false",value:settings.outputMinimum)
        NumberSetting(settings.wrappedValue.mode == .proportional ? "Output high" : "When true",value:settings.outputMaximum)
        Text(settings.wrappedValue.output == .visibility ? "Below 50 hides the image; 50 and above shows it." : "Proportional mappings clamp at the input endpoints. Reverse either range to invert the effect.")
          .font(.caption2).foregroundStyle(muted)
      }
      Toggle("Flash image",isOn:Binding(get:{settings.wrappedValue.pulseInterval > 0},set:{settings.wrappedValue.pulseInterval = $0 ? 0.5 : 0}))
      if settings.wrappedValue.pulseInterval > 0 {
        NumberSetting("Seconds per on/off phase",value:settings.pulseInterval)
      }
      Text("Flashing follows project time. Data effects follow the synchronized input; unavailable data hides the image.")
        .font(.caption2).foregroundStyle(muted)
    }.font(.system(size:11)).alert("Could not load image",isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})) {
      Button("OK") { error = nil }
    } message:{Text(error ?? "")}
  }
  func chooseArtwork() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf:url)
      guard NSImage(data:data) != nil else { throw RaceError.invalid("Choose a readable image file.") }
      var updated = object; updated.artwork = data; updated.embeddedImage = nil; updated.text = ""; object = updated
    } catch { self.error = error.localizedDescription }
  }
}
