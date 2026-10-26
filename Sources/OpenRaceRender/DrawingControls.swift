import RaceCore
import SwiftUI

struct TypographyControls: View {
  @Binding var settings: TextSettings
  @Binding var color: String
  var body: some View {
    DisclosureGroup("Text appearance") {
      VStack(alignment: .leading, spacing: 10) {
        TextField("Font family or PostScript name", text: $settings.font)
        Menu("Choose font") {
          ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { font in
            Button(font) { settings.font = font }
          }
        }
        NumberSetting("Font size", value: $settings.size)
        Text("Size at \(Int(settings.referenceHeight))p; scales with output resolution.").font(.caption2).foregroundStyle(muted)
        HStack { Toggle("Bold", isOn: $settings.bold); Toggle("Italic", isOn: $settings.italic) }
        HStack { Toggle("Underline", isOn: $settings.underline); Toggle("Strike", isOn: $settings.strikethrough) }
        Picker("Alignment", selection: $settings.alignment) {
          ForEach(TextSettings.Alignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        HexColorControl("Text color", value: $color)
        Toggle("Reduce font to fit box", isOn: $settings.fitToBox)
        Toggle("Text outline", isOn: $settings.outline)
        if settings.outline {
          HexColorControl("Outline color", value: $settings.outlineColor)
          NumberSetting("Outline width", value: $settings.outlineWidth)
        }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
}

struct ShapeControls: View {
  @Binding var settings: ShapeSettings
  @Binding var color: String
  var body: some View {
    DisclosureGroup("Shape appearance") {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Shape", selection: $settings.kind) {
          ForEach(ShapeSettings.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if settings.kind != .line {
          Toggle("Fill", isOn: $settings.fill)
          if settings.fill {
            HexColorControl("Fill color", value: $color)
            Toggle("Gradient fill", isOn: $settings.gradient)
            if settings.gradient {
              HexColorControl("Second color", value: $settings.gradientColor)
              NumberSetting("Gradient angle (°)", value: $settings.gradientAngle)
            }
          }
          Toggle("Outline", isOn: $settings.stroke)
        }
        if settings.stroke || settings.kind == .line {
          HexColorControl("Line color", value: $settings.strokeColor)
          NumberSetting("Line width", value: $settings.strokeWidth)
        }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
}

struct NumberSetting: View {
  var title: String
  @Binding var value: Double
  init(_ title: String, value: Binding<Double>) { self.title = title; _value = value }
  var body: some View {
    HStack {
      Text(title).foregroundStyle(muted)
      Spacer()
      TextField(title, value: $value, format: .number.precision(.fractionLength(0...3)))
        .frame(width: 82).accessibilityLabel(title)
    }
  }
}

struct HexColorControl: View {
  var title: String
  @Binding var value: String
  init(_ title: String, value: Binding<String>) { self.title = title; _value = value }
  var body: some View {
    ColorPicker(title, selection: Binding(get: { Color(cgColor: OverlayRenderer.color(value)) }, set: { color in
      guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
      value = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }), supportsOpacity: false)
  }
}

struct AudioControls: View {
  @Binding var settings: AudioSettings
  var source = false
  var body: some View {
    DisclosureGroup(source ? "Audio channels & balance" : "Display audio") {
      VStack(spacing: 10) {
        if !source {
          NumberSetting("Volume (0–2)", value: $settings.volume)
        }
        Slider(value: $settings.balance, in: -1...1).accessibilityLabel("Audio balance")
        Text(settings.balance == 0 ? "Center" : String(format: "%.0f%% %@", abs(settings.balance) * 100, settings.balance < 0 ? "left" : "right")).font(.caption2)
        if source {
          Picker("Channels", selection: $settings.routing) {
            Text("Stereo").tag(AudioSettings.Routing.stereo)
            Text("Swap left/right").tag(AudioSettings.Routing.swap)
            Text("Left to both speakers").tag(AudioSettings.Routing.left)
            Text("Right to both speakers").tag(AudioSettings.Routing.right)
            Text("Mix to mono").tag(AudioSettings.Routing.mono)
          }
        }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
}
