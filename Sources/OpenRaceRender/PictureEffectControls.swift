import AppKit
import RaceCore
import SwiftUI

struct PictureEffectControls:View {
  @Binding var settings:PictureSettings
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      Toggle("Chroma key",isOn:Binding(get:{settings.chromaKey != nil},set:{settings.chromaKey = $0 ? ChromaKeySettings() : nil}))
      if settings.chromaKey != nil {
        HexColorControl("Key color",value:Binding(get:{settings.chromaKey?.color ?? "#00FF00"},set:{settings.chromaKey?.color = $0}))
        HStack {
          ForEach(Array([("R",16),("G",8),("B",0)].enumerated()),id:\.offset) { _,item in
            VStack { Text(item.0).font(.caption2); TextField(item.0,value:component(item.1),format:.number.precision(.fractionLength(0))).frame(width:60) }
          }
        }
        Button("Pick key color from screen…",action:sampleColor)
        NumberSetting("Color range (%)",value:keyValue(\.colorTolerance))
        NumberSetting("Brightness range (%)",value:keyValue(\.brightnessTolerance))
        NumberSetting("Edge softness (%)",value:keyValue(\.softness))
        Text("Keying runs before this layer's picture adjustments. A screen sample taken from an adjusted preview may need refinement. Display-level keying sees the source's adjusted picture.").font(.caption2).foregroundStyle(muted)
      }
      Toggle("Colorize",isOn:Binding(get:{settings.colorize != nil},set:{settings.colorize = $0 ? ColorizeSettings() : nil}))
      if settings.colorize != nil {
        Toggle("Full spectrum",isOn:Binding(get:{settings.colorize?.mode == .spectrum},set:{settings.colorize?.mode = $0 ? .spectrum : .tint}))
        if settings.colorize?.mode != .spectrum {
          HexColorControl("Tint",value:Binding(get:{settings.colorize?.color ?? "#FFFFFF"},set:{settings.colorize?.color = $0}))
        }
        NumberSetting("Colorize amount (%)",value:Binding(get:{(settings.colorize?.amount ?? 1)*100},set:{if $0.isFinite {settings.colorize?.amount = min(1,max(0,$0/100))}}))
        Text("Tint maps brightness to the selected color. Full spectrum maps brightness around the hue wheel. Both preserve keyed transparency.").font(.caption2).foregroundStyle(muted)
      }
      if let issue { Text(issue).font(.caption2).foregroundStyle(.orange) }
    }
  }
  var issue:String? { do {try settings.validateEffects(); return nil} catch {return error.localizedDescription} }
  func keyValue(_ path:WritableKeyPath<ChromaKeySettings,Double>) -> Binding<Double> {
    Binding(get:{(settings.chromaKey?[keyPath:path] ?? 0)*100},set:{if $0.isFinite {settings.chromaKey?[keyPath:path] = max(0,min(1,$0/100))}})
  }
  func component(_ shift:Int) -> Binding<Double> {
    Binding(get:{Double(((UInt32((settings.chromaKey?.color ?? "").replacingOccurrences(of:"#",with:""),radix:16) ?? 0)>>shift)&255)},set:{value in
      guard value.isFinite else { return }; let byte = UInt32(min(255,max(0,value.rounded())))
      let original = UInt32((settings.chromaKey?.color ?? "").replacingOccurrences(of:"#",with:""),radix:16) ?? 0
      let number = (original & ~(255<<shift)) | byte<<shift
      settings.chromaKey?.color = String(format:"#%06X",number)
    })
  }
  func sampleColor() {
    NSColorSampler().show { value in
      guard let rgb = value?.usingColorSpace(.sRGB) else { return }
      settings.chromaKey?.color = String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
    }
  }
}
