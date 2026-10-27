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
        if let segment = object.segments?.first(where:{abs($0.time-t) < 1e-6}) {
          SegmentEditingControls(model:model,object:object,segment:segment).id(segment.id)
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
          Text("Adjustments: −100 to +100 · 0 is neutral").foregroundStyle(muted)
          adjustment("Brightness", $settings.brightnessAdjustment)
          adjustment("Contrast", $settings.contrastAdjustment)
          adjustment("Saturation", $settings.saturationAdjustment)
          adjustment("Sharpness", $settings.sharpnessAdjustment)
          VStack(alignment: .leading, spacing: 4) {
            Text("Hue (−180° to +180°)").font(.system(size: 10))
            HStack {
              Slider(value: $settings.hueAdjustment, in: -180...180).accessibilityLabel("Hue")
              TextField("Hue adjustment", value: $settings.hueAdjustment, format: .number.precision(.fractionLength(0...2))).frame(width: 60)
            }
          }
        }
        Button("Reset picture") { let interpretation = settings.legacyColorInterpretation; settings = PictureSettings(); settings.legacyColorInterpretation = interpretation }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
  func value(_ label: String, _ binding: Binding<Double>) -> some View {
    VStack(alignment: .leading) { Text(label).font(.system(size: 10)); TextField(label, value: binding, format: .number.precision(.fractionLength(0...3))) }
  }
  func adjustment(_ label: String, _ binding: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: 10))
      HStack {
        Slider(value: binding, in: -100...100).accessibilityLabel(label)
        TextField(label, value: binding, format: .number.precision(.fractionLength(0...2)))
          .frame(width: 60).accessibilityLabel(label + " adjustment")
      }
    }
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
      if input.joinedTo == nil {
        Toggle("Loop within project length", isOn: Binding(get: { timing.wrappedValue.loop ?? false }, set: { timing.wrappedValue.loop = $0 }))
      }
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
      if ["video", "image"].contains(input.kind) {
        Text("Picture changes affect every display using this input.").font(.system(size: 10)).foregroundStyle(muted)
        PictureControls(settings: picture)
      }
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
  @State var events: [SyncEvent] = []
  @State var aligned = false
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Data synchronization wizard").font(.title2)
        Spacer()
        Button("Done") { model.pause(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("1. Choose a lap start or another recorded event.  2. Find the same frame in the video.  3. Align.")
        .font(.callout).foregroundStyle(muted)
      HStack(alignment: .top, spacing: 22) {
        VStack(spacing: 10) {
          Preview(model: model, interactive: false).aspectRatio(Double(model.project.width)/Double(model.project.height), contentMode: .fit)
            .frame(width: 560, height: 315).background(.black)
          HStack {
            Button("−1 s") { model.seek(model.time-1) }
            Button("−1 frame") { model.seek(model.time-1/model.project.fps) }
            Button(model.playing ? "Pause" : "Play") { model.togglePlayback() }
            Button("+1 frame") { model.seek(model.time+1/model.project.fps) }
            Button("+1 s") { model.seek(model.time+1) }
          }
          Slider(value: Binding(get: { model.time }, set: { model.seek($0) }), in: 0...max(1, model.project.duration))
          HStack {
            Text("Video frame (seconds)")
            TextField("Video event time", value: Binding(get: { model.time }, set: { model.seek($0) }), format: .number.precision(.fractionLength(0...4)))
              .textFieldStyle(.roundedBorder).frame(width: 125)
            Text(clockText(model.time)).monospacedDigit().foregroundStyle(mint)
          }
        }
        VStack(alignment: .leading, spacing: 16) {
          Picker("Data source", selection: $index) {
            Text("Select telemetry").tag(-1)
            ForEach(model.project.inputs.filter { $0.kind == "data" && $0.joinedTo == nil }) { Text($0.name).tag($0.legacyIndex) }
          }.onChange(of: index) { _, _ in loadEvents() }
          Picker("Recorded event", selection: $eventID) {
            Text("Custom source time").tag("")
            ForEach(events) { Text($0.name + " · " + clockText($0.time)).tag($0.id) }
          }.onChange(of: eventID) { _, id in
            if let e = events.first(where: { $0.id == id }) { sourceTime = e.time }
            aligned = false
          }
          if events.isEmpty { Text("No lap events? Enter a source time, or configure a GPS finish line in the data inspector.").font(.caption).foregroundStyle(muted) }
          TextField("Source event time (seconds)", value: $sourceTime, format: .number.precision(.fractionLength(0...4)))
            .textFieldStyle(.roundedBorder)
          Text("Data event: " + clockText(sourceTime)).monospacedDigit()
          Text("Scrub until the car crosses the same start/finish line. Use frame steps for the first or second lap crossing.")
            .font(.callout).foregroundStyle(muted)
          Button("Align event to video frame") {
            model.pause(); model.synchronize(inputIndex: index, sourceTime: sourceTime)
            aligned = model.error == nil
          }.buttonStyle(.borderedProminent).disabled(index < 0)
          if aligned { Label("Aligned. Choose another lap to check the match.", systemImage: "checkmark.circle").foregroundStyle(mint) }
          if let input = model.project.inputs.first(where: { $0.legacyIndex == index }) {
            Text("Offset: \(input.offset.formatted(.number.precision(.fractionLength(3)))) s").monospacedDigit().font(.caption)
            Button("Seek to selected event using current sync") { model.seek(model.projectTime(for: sourceTime, inputIndex: index)) }
          }
        }.frame(width: 295)
      }
    }.padding(24).frame(width: 925).background(bg).preferredColorScheme(.dark).tint(mint)
    .onAppear {
      model.pause()
      index = model.project.inputs.first(where: { $0.id == model.selectedInput && $0.kind == "data" })?.legacyIndex ?? model.dataIndex ?? -1
      loadEvents()
    }
    .onDisappear { model.pause() }
  }
  func loadEvents() {
    events = model.telemetry[index]?.syncEvents ?? []
    let lap = events.first { $0.name.hasPrefix("Lap ") && $0.time > 0 }
    eventID = lap?.id ?? ""; sourceTime = lap?.time ?? 0; aligned = false
  }
}

struct SaveTemplateSheet: View {
  @ObservedObject var model: EditorModel
  @Environment(\.dismiss) var dismiss
  var body: some View {
    let included = model.templateIncludedIDs
    let usedInputs = model.templateUsedInputs
    VStack(alignment: .leading, spacing: 16) {
      Text(model.templateIsSingleStyle ? "Save reusable style" : "Save reusable template").font(.title2)
      TextField("Template name", text: $model.templateName).textFieldStyle(.roundedBorder)
      Picker("File format",selection:$model.templateLegacyFormat) {
        Text("OpenRaceRender (.orrt)").tag(false)
        Text(model.templateIsSingleStyle ? "RaceRender style (.rro)" : "RaceRender template (.rrt)").tag(true)
      }
      HStack {
        Text("Include:").foregroundStyle(muted)
        Button("All") { model.templateObjectIDs = Set(model.project.objects.map(\.id)) }
        Button("Widgets only") { model.templateObjectIDs = Set(model.project.objects.filter { ![.video, .audio].contains($0.kind) }.map(\.id)) }
        Button("Current selection") { model.templateObjectIDs = model.project.descendants(of: model.selectedIDs) }.disabled(model.selectedIDs.isEmpty)
        Button("None") { model.templateObjectIDs = [] }
      }.font(.caption)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Display objects · template names").font(.headline)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(model.project.objects) { object in
                HStack {
                  Toggle(object.name, isOn: model.templateChecked(object.id)).labelsHidden()
                    .accessibilityLabel("Include " + object.name)
                    .help(object.kind == .group ? "Select or deselect the entire group" : "Include this display")
                  VStack(alignment: .leading, spacing: 2) {
                    TextField(object.name, text: model.templateObjectName(object)).textFieldStyle(.roundedBorder)
                      .accessibilityLabel("Template object name: " + object.name)
                    Text(object.name + " · " + object.kind.title).font(.caption2).foregroundStyle(muted)
                  }
                }.padding(.leading, CGFloat(model.project.ancestors(of: object.id).count) * 10)
                  .opacity(included.contains(object.id) ? 1 : 0.55)
              }
            }.padding(.trailing, 6)
          }.frame(height: 260)
        }.frame(maxWidth: .infinity)
        VStack(alignment: .leading, spacing: 8) {
          Text("Input roles · template names").font(.headline)
          Text("Included inputs follow your display choices. These names appear when loading the template.")
            .font(.caption).foregroundStyle(muted)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(model.project.inputs) { input in
                let used = usedInputs.contains(input.legacyIndex)
                HStack {
                  Image(systemName: used ? "checkmark.circle.fill" : "circle").foregroundStyle(used ? mint : muted)
                    .accessibilityLabel((used ? "Included input: " : "Unused input: ") + input.name)
                  VStack(alignment: .leading, spacing: 2) {
                    TextField(input.name, text: model.templateInputName(input)).textFieldStyle(.roundedBorder)
                      .accessibilityLabel("Template input role: " + input.name).disabled(!used)
                    Text(input.name + " · " + input.kind).font(.caption2).foregroundStyle(muted)
                  }
                }.opacity(used ? 1 : 0.5)
              }
            }
          }
        }.frame(width: 245)
      }
      Text("\(included.count) displays · \(usedInputs.count) input \(usedInputs.count == 1 ? "role" : "roles"). Parent groups are retained; unselected siblings are excluded. Group checkboxes select all members.")
        .font(.callout).foregroundStyle(muted)
      Text("Names change only in this template. Media paths, synchronization, export marks and session settings are removed; artwork is embedded. Save in the suggested folder to find it in the library.")
        .font(.caption).foregroundStyle(muted)
      if model.templateLegacyFormat {
        Text("RaceRender formats support a smaller set of settings. Incompatible widgets or timeline events are reported before choosing a file.").font(.caption).foregroundStyle(muted)
      }
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Choose file & save…", action: model.saveLayout).buttonStyle(.borderedProminent).disabled(included.isEmpty)
      }
    }.padding(26).frame(width: 740).background(bg).preferredColorScheme(.dark).tint(mint)
  }
}

struct WidgetPalette: View {
  @ObservedObject var model: EditorModel
  @ObservedObject var catalog: WidgetCatalog
  @State var source = ""
  @State var search = ""
  @State var kind = ""
  init(model: EditorModel) { self.model = model; self.catalog = model.widgetCatalog }
  var basicKinds: [ObjectKind] { ObjectKind.allCases.filter { ![.group, .audio, .video, .image, .enhanced].contains($0) } }
  var filtered: [WidgetStyle] {
    catalog.styles.filter {
      (kind.isEmpty || $0.object.kind.rawValue == kind) && (search.isEmpty || ($0.name + " " + $0.object.style).localizedCaseInsensitiveContains(search))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("WIDGETS").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(muted)
        Spacer()
        Button { model.showWidgets = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close widgets")
      }
      Text("Drag onto the preview, or click to add.").font(.system(size: 10)).foregroundStyle(muted)
      WidgetSourcePicker(catalog: catalog, source: $source)
      TextField("Search widgets or styles", text: $search).textFieldStyle(.roundedBorder)
      if !source.isEmpty {
        Picker("Widget type", selection: $kind) {
          Text("All types").tag("")
          ForEach(ObjectKind.allCases.filter { ![.group, .video, .audio].contains($0) }, id: \.self) { Text($0.title).tag($0.rawValue) }
        }.labelsHidden().accessibilityLabel("Widget type")
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
          if source.isEmpty {
            ForEach(basicKinds.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }, id: \.self) { kind in
              WidgetTile(model: model, kind: kind).frame(maxWidth: .infinity).frame(height: 53)
            }
          } else {
            ForEach(filtered) { style in
              WidgetTile(model: model, kind: style.object.kind, style: style).frame(maxWidth: .infinity).frame(height: 94)
            }
          }
        }
      }.frame(minHeight: 100, maxHeight: 200)
      if catalog.loading { ProgressView("Reading widgets…").controlSize(.small) }
      else if !source.isEmpty { Text("\(filtered.count) widgets").font(.system(size: 10)).foregroundStyle(muted) }
      if let message = catalog.message { Text(message).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2) }
      HStack {
        Button("From file…") {
          let panel = NSOpenPanel(); panel.directoryURL = LayoutLibrary.userRoot().appendingPathComponent("Templates")
          if panel.runModal() == .OK, let url = panel.url { source = url.path }
        }
        Button("Image / logo…", action: model.chooseInputs)
      }.font(.system(size: 10))
      Button("Save template…", action: model.saveTemplate).font(.system(size: 11))
        .disabled(model.project.objects.isEmpty)
    }.padding(12).background(panelColor)
      .task(id: source + "#\(model.widgetLibraryRevision)") { await catalog.discover(refresh: true); await catalog.load(source) }
  }
}

struct WidgetTile: NSViewRepresentable {
  var model: EditorModel
  var kind: ObjectKind
  var style: WidgetStyle?
  func makeNSView(context: Context) -> WidgetTileView { WidgetTileView(model: model, kind: kind) }
  func updateNSView(_ view: WidgetTileView, context: Context) { view.model = model; view.kind = kind; view.setStyle(style) }
}

/// Palette drags stay inside the editor. Track the release in window coordinates
/// so AppKit's video view and SwiftUI don't compete for the drag destination.
@MainActor final class WidgetTileView: NSView {
  weak var model: EditorModel?
  var kind: ObjectKind { didSet { setAccessibilityLabel(style?.name ?? kind.title); needsDisplay = true } }
  private var style: WidgetStyle?
  private var thumbnail: NSImage?
  func setStyle(_ value: WidgetStyle?) {
    guard value?.id != style?.id else { return }
    style = value; thumbnail = nil
    setAccessibilityLabel(value?.name ?? kind.title)
    setAccessibilityHelp("Drag onto the preview, or press to add " + (value?.name ?? kind.title))
    needsDisplay = true
    if let value {
      Task { [weak self] in
        let image = await Task.detached(priority: .utility) { WidgetDesign.thumbnail(value.object) }.value
        guard self?.style?.id == value.id else { return }
        self?.thumbnail = image; self?.needsDisplay = true
      }
    }
  }
  func add(at point: CGPoint? = nil) {
    if let style { model?.addWidget(style, at: point) }
    else { model?.addObject(kind, at: point) }
  }
  private var origin = CGPoint.zero
  private var dragging = false
  init(model: EditorModel, kind: ObjectKind) {
    self.model = model; self.kind = kind
    super.init(frame: .zero)
    setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(kind.title)
    setAccessibilityHelp("Drag onto the preview, or press to add " + kind.title)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(bg).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(mint)])))
    if let thumbnail {
      thumbnail.draw(in: NSRect(x: 4, y: 3, width: max(1, bounds.width-8), height: 57), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    } else { symbol?.draw(in: NSRect(x: bounds.midX-11, y: 8, width: 22, height: 22)) }
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
    ((style?.name ?? kind.title) as NSString).draw(in: NSRect(x: 3, y: style == nil ? 34 : 62, width: max(1, bounds.width-6), height: style == nil ? 16 : 30),
      withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
  }
  override func accessibilityPerformPress() -> Bool { add(); return true }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self); origin = event.locationInWindow; dragging = false
  }
  override func mouseDragged(with event: NSEvent) {
    guard hypot(event.locationInWindow.x-origin.x, event.locationInWindow.y-origin.y) > 3 else { return }
    dragging = true; alphaValue = 0.6
    guard let canvas = model?.canvasView, canvas.window === window else { return }
    let point = canvas.convert(event.locationInWindow, from: nil)
    canvas.overlay.dropPoint = canvas.bounds.contains(point) ? point : nil
    canvas.overlay.needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    defer {
      dragging = false; alphaValue = 1
      model?.canvasView?.overlay.dropPoint = nil; model?.canvasView?.overlay.needsDisplay = true
    }
    guard dragging else { add(); return }
    guard let canvas = model?.canvasView, canvas.window === window, canvas.bounds.width > 0, canvas.bounds.height > 0 else { return }
    let point = canvas.convert(event.locationInWindow, from: nil)
    guard canvas.bounds.contains(point) else { return }
    add(at: CGPoint(x: point.x/canvas.bounds.width*100, y: point.y/canvas.bounds.height*100))
  }
  override func keyDown(with event: NSEvent) {
    if [36, 49].contains(event.keyCode) { add() }
    else { super.keyDown(with: event) }
  }
}

struct ObjectTracks: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(spacing:0) {
      TimelineZoomControls(model:model).padding(.horizontal,20).padding(.top,8)
      ScrollView {
        VStack(spacing:4) {
          ForEach(model.project.objects.reversed()) { object in
            HStack(spacing:10) {
              Button(object.name) { model.selectSegment(object.id,at:nil) }
                .buttonStyle(.plain).lineLimit(1).frame(width:150,alignment:.leading)
              GeometryReader { g in
                ZStack(alignment:.leading) {
                  RoundedRectangle(cornerRadius:3).fill((object.id == model.selected ? mint : Color.blue).opacity(0.15))
                    .contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { v in
                      model.selected = object.id; model.selectedInput = nil
                      model.seek(model.timelineLower+max(0,min(1,v.location.x/max(1,g.size.width)))*model.timelineSpan)
                    })
                  ForEach((object.segments ?? []).filter { $0.time >= model.timelineLower && $0.time <= model.timelineUpper }) { segment in
                    Button { model.selectSegment(object.id,at:segment.time) } label: {
                      Rectangle().fill(object.id == model.selected && model.editingSegment == segment.time ? Color.white : mint).frame(width:5,height:18)
                    }.buttonStyle(.plain)
                      .offset(x:max(0,min(g.size.width-5,g.size.width*(segment.time-model.timelineLower)/model.timelineSpan)))
                      .help(clockText(segment.time)+" · "+segment.changedFields.map(\.title).joined(separator:", "))
                  }
                  Rectangle().fill(.white.opacity(0.6)).frame(width:1)
                    .offset(x:g.size.width*(model.time-model.timelineLower)/model.timelineSpan).allowsHitTesting(false)
                }
              }.frame(height:18).clipped()
            }.font(.system(size:10))
          }
        }.padding(.horizontal,20).padding(.vertical,10)
      }
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
        Text("Use ‘Edit widget background…’ in the inspector to import, align, key or export artwork.")
          .font(.caption2).foregroundStyle(muted)
      }.padding(.top, 10)
    }.font(.system(size: 11))
  }
  func field(_ name: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading) { Text(name).foregroundStyle(muted); TextField(name, value: value, format: .number) }
  }
}
