import RaceCore
import SwiftUI

struct DerivedMotionControls:View {
  @Binding var settings:DataSettings
  var data:Telemetry?
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("Motion estimates").font(.headline)
      mode("Heading",alias:"heading",key:\.headingDerivation)
      mode("Longitudinal G",alias:"gx",key:\.longitudinalDerivation)
      mode("Lateral G",alias:"gy",key:\.lateralDerivation)
      NumberSetting("Heading adjustment (degrees)",value:Binding(get:{settings.headingAdjustment ?? 0},set:{settings.headingAdjustment = $0.isFinite ? $0 : 0}))
      Toggle("Reverse heading direction",isOn:Binding(get:{settings.reverseHeading ?? false},set:{settings.reverseHeading = $0 ? true : nil}))
      Text("Automatic prefers recorded channels. Estimates use position, course and speed; forward acceleration and rightward lateral acceleration are positive. Heading adjustment does not rotate GPS-derived G-force.").font(.caption).foregroundStyle(muted)
    }
  }
  func mode(_ name:String,alias:String,key:WritableKeyPath<DataSettings,DataDerivationMode?>) -> some View {
    VStack(alignment:.leading,spacing:4) {
      Picker(name,selection:Binding(get:{settings[keyPath:key] ?? .automatic},set:{settings[keyPath:key] = $0 == .automatic ? nil : $0})) {
        ForEach(DataDerivationMode.allCases,id:\.self) { Text($0.title).tag($0) }
      }
      if let origin = data?.provenance(for:alias) {
        Text(data?.bounds(alias) == nil ? "No usable samples for this channel" : origin.details).font(.caption2).foregroundStyle(muted)
      } else { Text("Unavailable with the current data and mode").font(.caption2).foregroundStyle(.orange) }
    }
  }
}
