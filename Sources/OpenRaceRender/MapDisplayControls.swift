import RaceCore
import SwiftUI

struct MapDisplayControls:View {
  @Binding var object:DisplayObject
  var data:Telemetry?
  var settings:Binding<MapDisplaySettings> { Binding(get:{object.editableMapSettings},set:{object.mapSettings = $0}) }
  var body:some View {
    DisclosureGroup("Map display") {
      VStack(alignment:.leading,spacing:10) {
        Toggle("Draw course",isOn:settings.drawCourse)
        Toggle("Draw vehicle position",isOn:settings.drawPosition)
        Toggle("Mark start / finish",isOn:settings.drawStart)
        Picker("Trace",selection:settings.trace) {
          Text("Whole source").tag(MapDisplaySettings.Trace.all)
          Text("Best complete lap").tag(MapDisplaySettings.Trace.best)
          Text("Current lap").tag(MapDisplaySettings.Trace.current)
          Text("Selected lap / run").tag(MapDisplaySettings.Trace.lap)
        }
        if settings.wrappedValue.trace == .lap {
          Picker("Lap",selection:settings.lapStart) {
            Text("Choose lap").tag(nil as Double?)
            ForEach(data?.laps ?? [],id:\.start) { Text("Lap \($0.number) · \(clockText($0.start))").tag(Optional($0.start)) }
          }
        }
        Picker("Vehicle icon",selection:settings.icon) { ForEach(MapDisplaySettings.Icon.allCases,id:\.rawValue){Text($0.rawValue.capitalized).tag($0)} }
        NumberSetting("Icon size (% short side)",value:bounded(\.markerSize,0.2...40))
        NumberSetting("Zoom (0.1–20×)",value:bounded(\.zoom,0.1...20))
        NumberSetting("Clockwise rotation (°)",value:bounded(\.rotation,-360...360))
        Toggle("Heading up",isOn:settings.headingUp)
        Toggle("Center on vehicle",isOn:settings.followPosition)
        Picker("Trace detail",selection:settings.resolution) {
          ForEach(MapDisplaySettings.Resolution.allCases,id:\.rawValue){Text("\($0.rawValue.capitalized) · ~\($0.points) points").tag($0)}
        }
        HexColorControl("Course color",value:settings.lineColor)
        HexColorControl("Course edge",value:settings.edgeColor)
        HexColorControl("Vehicle color",value:Binding(get:{settings.wrappedValue.positionColor ?? object.color},set:{settings.wrappedValue.positionColor = $0}))
        NumberSetting("Course width (%)",value:bounded(\.lineWidth,0.1...20))
        NumberSetting("Edge width (%)",value:bounded(\.edgeWidth,0...20))
        Toggle("Keep background aligned with map",isOn:settings.alignBackground)
        Text("Align embedded artwork at 1× zoom / north up using Edit widget background. Then zoom, rotate or follow the map and artwork together. Separate image widgets keep their own positions.").font(.caption2).foregroundStyle(muted)
        Text("Edits use the vector map renderer. Reset restores the original imported map or native defaults.").font(.caption2).foregroundStyle(muted)
        Button("Reset to original map") { object.mapSettings = nil }
      }.padding(.top,8)
    }
  }
  func bounded(_ path:WritableKeyPath<MapDisplaySettings,Double>,_ range:ClosedRange<Double>) -> Binding<Double> {
    Binding(get:{settings.wrappedValue[keyPath:path]},set:{if $0.isFinite { settings.wrappedValue[keyPath:path] = min(range.upperBound,max(range.lowerBound,$0)) }})
  }
}
