import RaceCore
import SwiftUI

struct SourceLocationControls:View {
  @Binding var settings:DataSettings
  var body:some View {
    Section("Location for scripts") {
      Toggle("Override location name",isOn:Binding(get:{settings.locationName != nil},set:{settings.locationName = $0 ? "" : nil}))
      if settings.locationName != nil {TextField("Location name",text:Binding(get:{settings.locationName ?? ""},set:{settings.locationName = $0}))}
      Text("Automatic uses recorded track metadata, then the nearest saved track within 5 km of the first GPS position. An empty override clears the name. No online lookup.").font(.caption).foregroundStyle(.secondary)
    }
  }
}
