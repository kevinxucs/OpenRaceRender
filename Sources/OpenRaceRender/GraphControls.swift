import RaceCore
import SwiftUI

struct GraphControls: View {
  @Binding var object: DisplayObject
  var headers: [String]
  var settings: Binding<GraphSettings> {
    Binding(get: { object.graph ?? GraphSettings() },set: { object.graph = $0 })
  }
  var body: some View {
    VStack(alignment:.leading,spacing:10) {
      Divider()
      Text("2D GRAPH").font(.caption).foregroundStyle(muted)
      Picker("Horizontal axis",selection:settings.axis) {
        Text("Time (seconds)").tag(GraphSettings.Axis.time)
        Text("Distance").tag(GraphSettings.Axis.distance)
        Text("Data channel").tag(GraphSettings.Axis.channel)
      }
      if settings.wrappedValue.axis == .channel {
        Picker("X channel",selection:settings.horizontalChannel) {
          Text("Choose a channel").tag("")
          if !settings.wrappedValue.horizontalChannel.isEmpty, !headers.contains(settings.wrappedValue.horizontalChannel) {
            Text(settings.wrappedValue.horizontalChannel).tag(settings.wrappedValue.horizontalChannel)
          }
          ForEach(headers,id:\.self) { Text($0).tag($0) }
        }
      }
      Picker("Plot mode",selection:settings.mode) {
        ForEach(GraphSettings.Mode.allCases,id:\.self) { Text($0.title).tag($0) }
      }
      if [.moving,.centered].contains(settings.wrappedValue.mode) {
        NumberSetting("Time span (s)",value:settings.timeSpan)
      }
      Text("Times are seconds into the data file, after synchronization. Channel axes use the input's units.")
        .font(.caption2).foregroundStyle(muted)
      Toggle("Automatic Y minimum",isOn:settings.automaticMinimum)
      Toggle("Automatic Y maximum",isOn:settings.automaticMaximum)
      optional("X minimum",value:settings.xMinimum,defaultValue:0)
      optional("X maximum",value:settings.xMaximum,defaultValue:100)
      if ![.moving,.centered].contains(settings.wrappedValue.mode) {
        optional("Source start (s)",value:settings.timeStart,defaultValue:0)
        optional("Source end (s)",value:settings.timeEnd,defaultValue:60)
        Toggle("Plot one lap",isOn:Binding(get:{settings.wrappedValue.lap != nil},set:{settings.wrappedValue.lap = $0 ? 1 : nil}))
        if settings.wrappedValue.lap != nil {
          Stepper("Lap \(settings.wrappedValue.lap ?? 1)",value:Binding(get:{settings.wrappedValue.lap ?? 1},set:{settings.wrappedValue.lap = $0}),in:1...10000)
        }
      }
      Toggle("Connect points with lines",isOn:settings.connect)
      Toggle("Sort points by X",isOn:settings.sortX)
      Toggle("Vertical",isOn:settings.vertical)
      Toggle("Reverse X direction",isOn:settings.reverse)
      DisclosureGroup("Graph appearance") {
        VStack(spacing:10) {
          HexColorControl("Line",value:settings.lineColor)
          NumberSetting("Line width",value:settings.lineWidth)
          optionalColor("Line gradient",value:settings.lineGradient)
          Toggle("Fill under curve",isOn:settings.fill)
          if settings.wrappedValue.fill {
            HexColorControl("Fill",value:settings.fillColor)
            optionalColor("Fill gradient",value:settings.fillGradient)
          }
          Toggle("Solid background",isOn:settings.background)
          if settings.wrappedValue.background { HexColorControl("Background",value:settings.backgroundColor) }
          Toggle("Axes",isOn:settings.axes)
          if settings.wrappedValue.axes {
            HexColorControl("Axis color",value:settings.axisColor)
            NumberSetting("Axis width",value:settings.axisWidth)
          }
          Toggle("Axis numbers",isOn:settings.numbers)
          if settings.wrappedValue.numbers {
            HexColorControl("Number color",value:settings.numberColor)
            NumberSetting("Number size",value:settings.numberSize)
            Toggle("Numbers on opposite side",isOn:settings.flipSides)
          }
          NumberSetting("Axis interval (0 = automatic)",value:settings.interval)
          Toggle("Border",isOn:settings.trim)
          if settings.wrappedValue.trim {
            HexColorControl("Border color",value:settings.trimColor)
            NumberSetting("Border width",value:settings.trimWidth)
          }
          HexColorControl("Position marker",value:settings.markerColor)
          NumberSetting("Marker size",value:settings.markerSize)
          TextField("Label",text:settings.label)
          HexColorControl("Label color",value:settings.labelColor)
          NumberSetting("Label size",value:settings.labelSize)
        }.padding(.top,8)
      }
    }.font(.system(size:11))
  }
  func optional(_ title: String,value:Binding<Double?>,defaultValue:Double) -> some View {
    VStack(alignment:.leading) {
      Toggle("Set \(title.lowercased())",isOn:Binding(get:{value.wrappedValue != nil},set:{value.wrappedValue = $0 ? defaultValue : nil}))
      if value.wrappedValue != nil { NumberSetting(title,value:Binding(get:{value.wrappedValue ?? defaultValue},set:{value.wrappedValue = $0})) }
    }
  }
  func optionalColor(_ title: String,value:Binding<String?>) -> some View {
    VStack(alignment:.leading) {
      Toggle(title,isOn:Binding(get:{value.wrappedValue != nil},set:{value.wrappedValue = $0 ? "#000000" : nil}))
      if value.wrappedValue != nil { HexColorControl("Second color",value:Binding(get:{value.wrappedValue ?? "#000000"},set:{value.wrappedValue = $0})) }
    }
  }
}
