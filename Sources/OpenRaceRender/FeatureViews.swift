import RaceCore
import SwiftUI

struct SegmentControls: View {
  @ObservedObject var model: EditorModel
  var object: DisplayObject
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("TIMELINE SEGMENT").font(.system(size: 9, weight: .bold)).foregroundStyle(muted)
      Picker("Editing", selection: Binding(get: { model.editingSegment ?? -1 }, set: {
        model.editingSegment = $0 < 0 ? nil : $0
        if $0 >= 0 { model.seek($0) }
      })) {
        Text("Base settings").tag(-1.0)
        ForEach((object.segments ?? []).sorted { $0.time < $1.time }) { s in Text(clockText(s.time)).tag(s.time) }
      }.labelsHidden()
      HStack {
        Button("Add at playhead", action: model.addSegment).disabled(model.time <= 0)
        Button("Remove", action: model.removeSegment).disabled(model.editingSegment == nil)
      }
      if let t = model.editingSegment {
        Text("Edits apply from \(clockText(t)) until a later segment overrides that field.").font(.system(size: 10)).foregroundStyle(mint)
        Button("Inherit all fields from previous segment") {
          guard let i = model.project.objects.firstIndex(where: { $0.id == object.id }),
            let j = model.project.objects[i].segments?.firstIndex(where: { $0.time == t }) else { return }
          model.checkpoint(); model.project.objects[i].segments?[j] = ObjectSegment(time: t)
        }
      }
    }
  }
}

struct PictureControls: View {
  @Binding var settings: PictureSettings
  var media: Bool = true
  var body: some View {
    DisclosureGroup("Picture & orientation") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("Flip horizontally", isOn: $settings.flipX)
        Toggle("Flip vertically", isOn: $settings.flipY)
        value("Rotation (degrees)", $settings.rotation)
        if media {
          Toggle("Maintain aspect ratio", isOn: $settings.maintainAspect)
          Text("Crop from edges (0–0.95)").foregroundStyle(muted)
          HStack { value("Left", $settings.left); value("Right", $settings.right) }
          HStack { value("Top", $settings.top); value("Bottom", $settings.bottom) }
          value("Brightness (0–2)", $settings.brightness)
          value("Contrast (0–2)", $settings.contrast)
          value("Color (0–2)", $settings.saturation)
        }
        Button("Reset picture") { settings = PictureSettings() }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
  func value(_ label: String, _ binding: Binding<Double>) -> some View {
    VStack(alignment: .leading) { Text(label).font(.system(size: 10)); TextField(label, value: binding, format: .number.precision(.fractionLength(0...3))) }
  }
}

struct InputTimingControls: View {
  @Binding var input: MediaInput
  @ObservedObject var model: EditorModel
  var timing: Binding<InputTiming> { Binding(get: { input.timing ?? InputTiming() }, set: { input.timing = $0 }) }
  var picture: Binding<PictureSettings> { Binding(get: { input.picture ?? PictureSettings() }, set: { input.picture = $0 }) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Trim & playback").font(.system(size: 13, weight: .semibold))
      value("Trim start in source (s)", timing.trimStart)
      value("Trim end in source (s)", Binding(get: { timing.wrappedValue.trimEnd ?? input.duration }, set: { timing.wrappedValue.trimEnd = $0 }))
      value("Start within project (s)", timing.projectStart)
      value("Playback rate (1 = normal)", timing.rate)
      if input.kind == "data" {
        Button("Synchronize to a data event…") { model.showSync = true }
        DataControls(input: $input, model: model)
      }
      if ["video", "audio"].contains(input.kind) {
        if input.joinedTo != nil {
          Text("Joined to previous stream").foregroundStyle(mint)
          Button("Unjoin this clip") { model.unjoin(input.id) }
        } else {
          Button("Join after previous input") { model.joinPrevious(input.id) }.disabled(!canJoin)
        }
      }
      if ["video", "image"].contains(input.kind) { PictureControls(settings: picture) }
      Button("Remove input and its displays", role: .destructive) { model.removeInput(input.id) }
    }.font(.system(size: 11))
  }
  var canJoin: Bool {
    guard let i = model.project.inputs.firstIndex(where: { $0.id == input.id }), i > 0 else { return false }
    return model.project.inputs[i-1].kind == input.kind
  }
  func value(_ label: String, _ binding: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 10)).foregroundStyle(muted); TextField(label, value: binding, format: .number.precision(.fractionLength(0...4))) }
  }
}

struct SyncSheet: View {
  @ObservedObject var model: EditorModel
  @State var index = -1
  @State var eventID = ""
  @State var sourceTime = 0.0
  @Environment(\.dismiss) var dismiss
  var events: [SyncEvent] { model.telemetry[index]?.syncEvents ?? [] }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Synchronize a source").font(.title2)
      Text("Find the same event in the video and the source. Aligning these two times updates the source offset.").foregroundStyle(muted)
      Picker("Source", selection: $index) {
        Text("Select an input").tag(-1)
        ForEach(model.project.inputs.filter { $0.joinedTo == nil }) { Text($0.name).tag($0.legacyIndex) }
      }
      if !events.isEmpty {
        Picker("Data event", selection: $eventID) {
          Text("Choose an event or enter a time").tag("")
          ForEach(events) { Text($0.name + " · " + clockText($0.time)).tag($0.id) }
        }.onChange(of: eventID) { _, id in if let e = events.first(where: { $0.id == id }) { sourceTime = e.time } }
      }
      TextField("Source event time (seconds)", value: $sourceTime, format: .number).textFieldStyle(.roundedBorder)
      HStack {
        Text("Project event: " + clockText(model.time)).monospacedDigit()
        Button("−1 frame") { model.seek(model.time-1/model.project.fps) }
        Button("+1 frame") { model.seek(model.time+1/model.project.fps) }
      }
      Slider(value: Binding(get: { model.time }, set: { model.seek($0) }), in: 0...max(1, model.project.duration))
      HStack {
        Button("Done") { dismiss() }
        Spacer()
        Button("Align source event to playhead") { model.synchronize(inputIndex: index, sourceTime: sourceTime) }.buttonStyle(.borderedProminent).disabled(index < 0)
      }
    }.padding(28).frame(width: 590).background(bg).preferredColorScheme(.dark).tint(mint)
    .onAppear { index = model.project.inputs.first(where: { $0.id == model.selectedInput })?.legacyIndex ?? model.dataIndex ?? -1 }
  }
}

struct ObjectTracks: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    ScrollView {
      VStack(spacing: 4) {
        ForEach(model.project.objects.reversed()) { object in
          HStack(spacing: 10) {
            Button(object.name) { model.selected = object.id; model.selectedInput = nil }.buttonStyle(.plain).lineLimit(1).frame(width: 150, alignment: .leading)
            GeometryReader { g in
              ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill((object.id == model.selected ? mint : Color.blue).opacity(0.15))
                ForEach(object.segments ?? []) { segment in
                  Rectangle().fill(mint).frame(width: 3).offset(x: g.size.width * segment.time / model.project.duration)
                }
                Rectangle().fill(.white).frame(width: 1).offset(x: g.size.width * model.time / model.project.duration)
              }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { v in
                model.selected = object.id; model.selectedInput = nil
                model.seek(max(0, v.location.x / max(1, g.size.width) * model.project.duration))
              })
            }.frame(height: 15)
          }.font(.system(size: 10))
        }
      }.padding(.horizontal, 20).padding(.vertical, 10)
    }
  }
}

struct DataControls: View {
  @Binding var input: MediaInput
  @ObservedObject var model: EditorModel
  var settings: Binding<DataSettings> { Binding(get: { input.dataSettings ?? DataSettings() }, set: { input.dataSettings = $0 }) }
  var data: Telemetry? { model.telemetry[input.legacyIndex] }
  var body: some View {
    DisclosureGroup("Data channels & lap timing") {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(["speed", "rpm", "gear", "throttle", "brake", "lat", "lon", "distance", "gx", "gy"], id: \.self) { alias in
          Picker(alias.uppercased(), selection: Binding(get: { settings.wrappedValue.assignments[alias] ?? "" }, set: { settings.wrappedValue.assignments[alias] = $0 })) {
            Text("Automatic").tag("")
            ForEach(data?.headers ?? [], id: \.self) { Text($0).tag($0) }
          }
        }
        Divider()
        Text("Calculated fields: source × multiplier + offset").foregroundStyle(muted)
        ForEach(settings.fields) { $field in
          VStack(alignment: .leading) {
            TextField("Field name", text: $field.name)
            Picker("Source", selection: $field.source) {
              Text("Speed").tag("speed")
              ForEach(data?.headers ?? [], id: \.self) { Text($0).tag($0) }
            }
            HStack { TextField("Multiplier", value: $field.multiply, format: .number); TextField("Offset", value: $field.add, format: .number) }
            Button("Remove field") { settings.wrappedValue.fields.removeAll { $0.id == field.id } }
          }
        }
        Button("Add calculated field") { settings.wrappedValue.fields.append(CalculatedField()) }
        Divider()
        Button("Set finish line at current GPS position") {
          let t = model.project.sourceTime(for: input.legacyIndex, at: model.time) ?? -1
          if let line = data?.finishLine(at: t) { settings.wrappedValue.finishLine = line }
          else { model.error = "Seek to a moving GPS sample before setting the finish line." }
        }
        if settings.wrappedValue.finishLine != nil {
          Text("Custom finish line active").foregroundStyle(mint)
          TextField("Gate width (m)", value: Binding(get: { settings.wrappedValue.finishLine?.width ?? 40 }, set: { settings.wrappedValue.finishLine?.width = max(1,$0) }), format: .number)
          TextField("Minimum lap (s)", value: Binding(get: { settings.wrappedValue.finishLine?.minimumLap ?? 10 }, set: { settings.wrappedValue.finishLine?.minimumLap = max(1,$0) }), format: .number)
          Button("Use recorded lap numbers") { settings.wrappedValue.finishLine = nil }
        }
      }.padding(.top, 10)
    }
  }
}

struct GaugeControls: View {
  @Binding var settings: GaugeSettings
  var body: some View {
    DisclosureGroup("Gauge designer") {
      VStack(alignment: .leading, spacing: 10) {
        TextField("Label", text: $settings.label)
        Toggle("Draw face", isOn: $settings.showFace)
        Toggle("Show current value", isOn: $settings.showNumber)
        Toggle("Show labels", isOn: $settings.showLabels)
        Toggle("Counter-clockwise", isOn: $settings.counterClockwise)
        field("Sweep (degrees)", $settings.sweep)
        field("Orientation (degrees)", $settings.rotation)
        Stepper("Divisions: \(settings.divisions)", value: $settings.divisions, in: 1...40).disabled(settings.tickInterval != nil)
        Toggle("Use fixed tick interval", isOn: Binding(get: { settings.tickInterval != nil }, set: { settings.tickInterval = $0 ? 20 : nil }))
        if settings.tickInterval != nil { field("Tick interval", Binding(get: { settings.tickInterval ?? 20 }, set: { settings.tickInterval = $0 })) }
        Stepper("Decimals: \(settings.decimals)", value: $settings.decimals, in: 0...6)
        field("Divide numbering by", $settings.numberingScale)
        Toggle("Use redline color", isOn: Binding(get: { settings.redline != nil }, set: { settings.redline = $0 ? 6000 : nil }))
        if settings.redline != nil { field("Redline threshold", Binding(get: { settings.redline ?? 6000 }, set: { settings.redline = $0 })) }
        Button("Set gauge background…") {
          let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
          if panel.runModal() == .OK { settings.backgroundPath = panel.url?.path; settings.showFace = false }
        }
        if settings.backgroundPath != nil { Button("Remove background") { settings.backgroundPath = nil } }
      }.padding(.top, 10)
    }.font(.system(size: 11))
  }
  func field(_ name: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading) { Text(name).foregroundStyle(muted); TextField(name, value: value, format: .number) }
  }
}
