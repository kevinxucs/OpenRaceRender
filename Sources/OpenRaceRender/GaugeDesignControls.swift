import RaceCore
import SwiftUI

struct GaugeDesignControls: View {
  @Binding var object: DisplayObject
  var settings: Binding<GaugeDesign> {
    Binding(get: { object.editableGaugeDesign }, set: { value in
      if object.gauge == nil { object.gauge = GaugeSettings() }
      object.gauge?.design = value
    })
  }
  var body: some View {
    DisclosureGroup("Expanded gauge design") {
      VStack(alignment: .leading, spacing: 12) {
        Text("Edits use the vector gauge designer. Dimensions below are percentages of the gauge radius.")
          .font(.caption2).foregroundStyle(muted)
        Picker("Mode", selection: settings.mode) {
          Text("Needle").tag(GaugeDesign.Mode.needle)
          Text("Dual needle").tag(GaugeDesign.Mode.dualNeedle)
          Text("Filled gauge").tag(GaugeDesign.Mode.filled)
        }
        Toggle("Automatic minimum", isOn: settings.automaticMinimum)
        Toggle("Automatic maximum", isOn: settings.automaticMaximum)
        NumberSetting("Smooth over seconds", value: settings.smoothing)
        Toggle("Nonlinear scale", isOn: Binding(get: { settings.wrappedValue.splitValue != nil }, set: {
          settings.wrappedValue.splitValue = $0 ? (object.minimum + object.maximum) / 2 : nil
        }))
        if settings.wrappedValue.splitValue != nil {
          NumberSetting("Split at value", value: Binding(get: { settings.wrappedValue.splitValue ?? 0 }, set: { settings.wrappedValue.splitValue = $0 }))
          NumberSetting("Split angle (° of sweep)", value: settings.splitAngle)
        }
        GaugeFaceControls(settings: settings)
        GaugeNeedleControls(settings: settings)
        GaugeMarkControls(settings: settings)
        GaugeCaptionControls(title: "Current value typography", caption: settings.valueStyle)
        GaugeCaptionControls(title: "Label typography", caption: settings.labelStyle)
        GaugeCaptionControls(title: "Tick number typography", caption: settings.numberStyle, position: false)
        GaugeChangeControls(title: "Needle color thresholds", settings: settings.needleChange)
        GaugeChangeControls(title: "Marking color thresholds", settings: settings.markingChange)
        GaugeChangeControls(title: "Face color thresholds", settings: settings.faceChange)
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
}

private struct GaugeFaceControls: View {
  @Binding var settings: GaugeDesign
  var body: some View {
    DisclosureGroup("Face and trim") {
      VStack(spacing: 10) {
        HexColorControl("Face", value: $settings.faceColor)
        Toggle("Face gradient", isOn: $settings.faceGradient)
        if settings.faceGradient { HexColorControl("Second face color", value: $settings.faceSecondColor) }
        Toggle("Draw trim", isOn: $settings.trim)
        if settings.trim {
          HexColorControl("Trim", value: $settings.trimColor)
          NumberSetting("Trim width", value: $settings.trimWidth)
        }
      }.padding(.top, 8)
    }
  }
}

private struct GaugeNeedleControls: View {
  @Binding var settings: GaugeDesign
  var body: some View {
    DisclosureGroup(settings.mode == .filled ? "Fill band" : "Needle geometry") {
      VStack(spacing: 10) {
        HexColorControl(settings.mode == .filled ? "Fill" : "Needle", value: $settings.needleColor)
        if settings.mode == .filled { NumberSetting("Inner radius", value: $settings.fillInnerRadius) }
        else {
          NumberSetting("Tip length", value: $settings.tip)
          NumberSetting("Tail length", value: $settings.tail)
          NumberSetting("Needle width", value: $settings.needleWidth)
          NumberSetting("Taper (0 = straight)", value: $settings.taper)
          NumberSetting("Center diameter", value: $settings.centerSize)
          HexColorControl("Center", value: $settings.centerColor)
          if settings.mode == .dualNeedle {
            NumberSetting("Second needle interval", value: $settings.dualInterval)
            NumberSetting("Second tip", value: $settings.dualTip)
            NumberSetting("Second tail", value: $settings.dualTail)
            NumberSetting("Second width", value: $settings.dualWidth)
            HexColorControl("Second needle", value: $settings.dualColor)
          }
        }
      }.padding(.top, 8)
    }
  }
}

private struct GaugeMarkControls: View {
  @Binding var settings: GaugeDesign
  var body: some View {
    DisclosureGroup("Major/minor marks and pins") {
      VStack(spacing: 10) {
        Toggle("Major marks", isOn: $settings.showMajor)
        if settings.showMajor {
          markPicker("Major style", value: $settings.majorStyle)
          NumberSetting("Major length", value: $settings.majorLength)
          NumberSetting("Major width", value: $settings.majorWidth)
          HexColorControl("Major color", value: $settings.marksColor)
        }
        Toggle("Minor marks", isOn: $settings.showMinor)
        if settings.showMinor {
          Toggle("Fixed minor interval", isOn: Binding(get: { settings.minorInterval != nil }, set: { settings.minorInterval = $0 ? 10 : nil }))
          if settings.minorInterval != nil {
            NumberSetting("Minor interval", value: Binding(get: { settings.minorInterval ?? 10 }, set: { settings.minorInterval = $0 }))
          } else { Stepper("Minor subdivisions: \(settings.minorDivisions)", value: $settings.minorDivisions, in: 1...100) }
          markPicker("Minor style", value: $settings.minorStyle)
          NumberSetting("Minor length", value: $settings.minorLength)
          NumberSetting("Minor width", value: $settings.minorWidth)
          HexColorControl("Minor color", value: $settings.minorColor)
        }
        Toggle("Min/max pins", isOn: $settings.pins)
        if settings.pins {
          NumberSetting("Pin size", value: $settings.pinSize)
          HexColorControl("Pin color", value: $settings.pinColor)
        }
        Toggle("Number every other mark", isOn: $settings.everyOtherNumber)
        Toggle("Number min/max points", isOn: $settings.numberExtremes)
        Toggle("Avoid overlapping numbers", isOn: $settings.limitClutter)
      }.padding(.top, 8)
    }
  }
  func markPicker(_ title: String, value: Binding<GaugeDesign.Mark>) -> some View {
    Picker(title, selection: value) { ForEach(GaugeDesign.Mark.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
  }
}

private struct GaugeCaptionControls: View {
  var title: String
  @Binding var caption: GaugeCaption
  var position = true
  var body: some View {
    DisclosureGroup(title) {
      VStack(spacing: 10) {
        TextField("Font name", text: $caption.font)
        NumberSetting("Font size (% radius)", value: $caption.size)
        HStack { Toggle("Bold", isOn: $caption.bold); Toggle("Italic", isOn: $caption.italic) }
        HexColorControl("Color", value: $caption.color)
        if position {
          Toggle("Automatic position", isOn: $caption.automaticPosition)
          if !caption.automaticPosition {
            NumberSetting("X (% of box)", value: $caption.x)
            NumberSetting("Y (% of box)", value: $caption.y)
          }
        }
      }.padding(.top, 8)
    }
  }
}

private struct GaugeChangeControls: View {
  var title: String
  @Binding var settings: GaugeColorChange
  var body: some View {
    DisclosureGroup(title) {
      VStack(spacing: 10) {
        Toggle("Change color", isOn: $settings.enabled)
        if settings.enabled {
          NumberSetting("Threshold", value: $settings.threshold)
          HexColorControl("Threshold color", value: $settings.color)
          Toggle("Smooth gradient", isOn: $settings.gradient)
          if settings.gradient { NumberSetting("Gradient starts at", value: $settings.start) }
          Toggle("Second threshold", isOn: $settings.secondEnabled)
          if settings.secondEnabled {
            NumberSetting("Second threshold value", value: $settings.secondThreshold)
            HexColorControl("Second threshold color", value: $settings.secondColor)
          }
        }
      }.padding(.top, 8)
    }
  }
}
