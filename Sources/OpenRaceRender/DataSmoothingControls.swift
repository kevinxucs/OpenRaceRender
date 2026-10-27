import RaceCore
import SwiftUI

struct DataSmoothingControls:View {
  @Binding var settings:DataSettings
  var body:some View {
    DisclosureGroup("Data smoothness") {
      VStack(alignment:.leading,spacing:8) {
        Toggle("Boost sample rate",isOn:Binding(get:{settings.interpolate ?? true},set:{settings.interpolate = $0}))
        Text("Interpolate continuous readings between recorded samples without duplicating the entire data table. Gear and lap numbers remain stepped.").font(.caption).foregroundStyle(.secondary)
        Toggle("Detect slower GPS updates",isOn:Binding(get:{settings.detectGPSUpdates ?? false},set:{settings.detectGPSUpdates = $0 ? true : nil}))
          .disabled(settings.interpolate == false)
        Text("Reconstruct repeated location/speed readings using observed update times. Long stops, missing data and OBD speed are preserved. Recorded timestamps do not change.").font(.caption).foregroundStyle(.secondary)
        Toggle("Smooth map curves",isOn:Binding(get:{settings.smoothCurves ?? false},set:{settings.smoothCurves = $0 ? true : nil}))
          .disabled(settings.interpolate == false)
        Text("Use bounded curves for both the trace and position marker. This changes visual interpolation, not recorded lap boundaries.").font(.caption).foregroundStyle(.secondary)
      }.padding(.top,8)
    }
  }
}
