import RaceCore
import SwiftUI
import UniformTypeIdentifiers

let mint = Color(red: 0.37, green: 0.88, blue: 0.71)
let bg = Color(red: 0.047, green: 0.065, blue: 0.09)
let panelColor = Color(red: 0.075, green: 0.10, blue: 0.14)
let muted = Color(red: 0.52, green: 0.59, blue: 0.68)

struct EditorView: View {
  @ObservedObject var model: EditorModel
  @State var bottomTab = 0
  @State var showSeek = false
  var body: some View {
    VStack(spacing: 0) {
      topBar
      CameraDataOffer(model:model)
      if let problem = model.recoveryProblem {
        HStack {Text(problem);Spacer();Button("Recovery details…"){model.showRecovery = true}}
          .font(.caption).foregroundStyle(.orange).padding(.horizontal,20).padding(.vertical,6)
      }
      if !model.missingInputs.isEmpty {
        HStack {
          Label("\(model.missingInputs.count) missing input\(model.missingInputs.count == 1 ? "" : "s") · Choose replacement files to restore this session.", systemImage: "exclamationmark.triangle")
          Spacer()
          Button("Review missing files", action: model.reviewMissingInput)
        }.font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 20).padding(.vertical, 8)
      }
      Divider()
      HStack(spacing: 0) {
        sidebar.frame(width: 234)
        Divider()
        VStack(spacing: 0) {
          previewHeader
          GeometryReader { g in
            let aspect = Double(max(1,model.project.width)) / Double(max(1,model.project.height))
            let w = min(g.size.width - 40, (g.size.height - 32) * aspect)
            let h = w / aspect
            ZStack {
              bg
              if model.project.inputs.isEmpty && model.project.objects.isEmpty && !model.showWidgets {
                emptyState
              } else {
                Preview(model: model).frame(width: max(1, w), height: max(1, h))
                  .shadow(
                  color: .black.opacity(0.5), radius: 15, y: 6)
              }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          transport
        }.frame(minWidth: 480)
        Divider()
        inspector.frame(width: 272)
      }
      Divider()
      timeline.frame(height: 200)
      Divider()
      footer
    }
    .background(bg).preferredColorScheme(.dark).tint(mint)
    .frame(minWidth: 1100, minHeight: 760)
    .sheet(isPresented:$model.showRecovery) { RecoverySheet(model:model) }
    .sheet(isPresented:$model.showDiagnostics) { DiagnosticsSheet(model:model) }
    .sheet(isPresented:$model.showStereoLayout) { StereoLayoutSheet(model:model) }
    .sheet(isPresented:$model.showSphericalMetadata) { SphericalMetadataSheet() }
    .sheet(item:$model.youTubeUploadRequest) { YouTubeUploadSheet(request:$0) }
    .sheet(isPresented: $model.showNetworkReceive) { NetworkReceiveSheet(model:model) }
    .sheet(isPresented: $model.showTemplates) { TemplateBrowser(model: model) }
    .sheet(isPresented: $model.showSync) { SyncSheet(model: model) }
    .sheet(isPresented: $model.showExport) { ExportSheet(model: model) }
    .sheet(isPresented: $model.showPreviewSettings) { PreviewSettingsSheet(model:model) }
    .sheet(item:$model.scriptEditorRequest) { ScriptEditor(model:model,request:$0) }
    .sheet(isPresented: $model.showSaveTemplate) { SaveTemplateSheet(model: model) }
    .sheet(isPresented: $model.showWidgetStyles) { WidgetStyleBrowser(model: model) }
    .sheet(isPresented: $model.showProjectSetup) { ProjectSetupSheet(model:model) }
    .sheet(isPresented: $model.showSourceSync) { SourceSyncSheet(model:model) }
    .sheet(item:$model.finishLineInput) { FinishLineEditor(model:model,input:$0) }
    .sheet(item:$model.dataSetupRequest,onDismiss:{model.nextDataSetup()}) { DataSetupSheet(model:model,request:$0) }
    .sheet(item:$model.sequenceInput) { SequenceEditor(model:model,inputID:$0.id) }
    .alert(
      "OpenRaceRender",
      isPresented: Binding(get: { model.error != nil && model.dataSetupRequest == nil && model.finishLineInput == nil && !model.showExport && !model.showProjectSetup && !model.showSourceSync }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
      Task { @MainActor in
        var urls: [URL] = []
        for provider in providers {
          let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
          }
          if let url { urls.append(url) }
        }
        if let project = urls.first(where: { ["rrp", "orrp"].contains($0.pathExtension.lowercased()) }) {
          model.open(project)
        } else if !urls.isEmpty { model.addInputs(urls) }
      }
      return true
    }
  }
  var topBar: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 8).fill(mint).frame(width: 32, height: 32)
        Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(bg).font(
          .system(size: 20, weight: .bold))
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("OpenRaceRender").font(.system(size: 14, weight: .bold))
        Text(model.project.name + (model.dirty ? " •" : "")).font(.system(size: 11))
          .foregroundStyle(muted).lineLimit(1)
      }
      Spacer()
      tool("Open", icon: "folder", action: model.chooseOpen)
      tool("Add input", icon: "plus.rectangle.on.folder", action: model.chooseInputs)
      tool("Setup", icon: "list.number", action: model.beginProjectSetup)
      tool("Templates", icon: "square.grid.2x2") { model.showTemplates = true }
      tool("Save", icon: "square.and.arrow.down") { model.save() }
      Rectangle().fill(muted.opacity(0.25)).frame(width: 1, height: 24)
      Menu {
        Button("Data event synchronization…") { model.showSync = true }.disabled(model.dataIndex == nil)
        Button("Cameras side by side…",action:model.beginSourceSync)
      } label: { Label("Sync",systemImage:"arrow.left.and.right") }.fixedSize()
      Button(action: model.prepareExport) {
        Label("Export video", systemImage: "arrow.up.right").font(
          .system(size: 12, weight: .semibold)
        ).padding(.horizontal, 10).padding(.vertical, 7)
      }.buttonStyle(.borderedProminent).foregroundStyle(bg).disabled(
        model.exportProgress != nil)
    }.padding(.horizontal, 20).frame(height: 66).background(panelColor)
  }
  func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon).font(.system(size: 12)).padding(.vertical, 5)
    }.buttonStyle(.borderless).foregroundStyle(.white.opacity(0.85))
  }
  func sectionLabel(_ text: String) -> some View {
    Text(text).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(muted)
  }
  var sidebar: some View {
    VStack(spacing: 0) {
      if model.showWidgets { WidgetPalette(model: model); Divider() }
      HStack {
        sectionLabel("DISPLAY OBJECTS")
        Spacer()
        Text("\(model.project.objects.count)").font(.system(size: 10, design: .monospaced))
          .foregroundStyle(muted)
        Button { model.showWidgets.toggle() } label: { Image(systemName: "square.grid.2x2").foregroundStyle(mint) }.buttonStyle(.plain).help("Show widget palette")
        Menu {
          ForEach(ObjectKind.allCases.filter { $0 != .group }, id: \.self) { kind in
            Button(kind.title) { model.addObject(kind) }
          }
        } label: {
          Image(systemName: "plus").foregroundStyle(mint)
        }.menuStyle(.borderlessButton).frame(width: 20)
      }.padding(16)
      ScrollView {
        LazyVStack(spacing: 3) {
          ForEach(Array(model.project.objects.reversed())) { o in
            HStack(spacing: 8) {
              Image(systemName: o.kind.symbol).frame(width: 18).foregroundStyle(
                model.selectedIDs.contains(o.id) ? mint : muted)
              VStack(alignment: .leading, spacing: 3) {
                Text(o.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(o.style.isEmpty ? o.kind.title : o.style).font(.system(size: 9))
                  .foregroundStyle(muted).lineLimit(1)
              }
              Spacer(minLength: 0)
              Button {
                model.checkpoint()
                if let i = model.project.objects.firstIndex(where: { $0.id == o.id }) {
                  var value = model.objectBinding(o.id).wrappedValue
                  value.visible.toggle()
                  model.updateObject(at: i, value: value)
                }
              } label: {
                Image(systemName: o.visible ? "eye" : "eye.slash").font(.system(size: 10))
                  .foregroundStyle(o.visible ? muted : muted.opacity(0.35))
              }.buttonStyle(.plain)
            }.padding(.leading, CGFloat(min(8, model.project.ancestors(of: o.id).count))*12)
            .padding(.horizontal, 10).padding(.vertical, 8).background(
              model.selectedIDs.contains(o.id) ? mint.opacity(0.09) : .clear
            ).overlay(alignment: .leading) {
              if model.selectedIDs.contains(o.id) { Rectangle().fill(mint).frame(width: 2) }
            }.contentShape(Rectangle()).onTapGesture {
              model.selectDisplay(o.id, modifiers: NSEvent.modifierFlags)
            }
            .contextMenu {
              Button("Group selection", action: model.groupSelection).disabled(model.selectedIDs.count < 2)
              Button("Ungroup selection", action: model.ungroupSelection)
              Button("Duplicate") {
                if !model.selectedIDs.contains(o.id) { model.selected = o.id }
                model.duplicate()
              }
              Button("Bring forward") {
                if !model.selectedIDs.contains(o.id) { model.selected = o.id }
                model.move(1)
              }
              Button("Send backward") {
                if !model.selectedIDs.contains(o.id) { model.selected = o.id }
                model.move(-1)
              }
              Button("Delete", role: .destructive) {
                if !model.selectedIDs.contains(o.id) { model.selected = o.id }
                model.deleteSelected()
              }
            }
          }
        }.padding(.horizontal, 7)
      }
      Divider()
      if !model.showWidgets {
      HStack {
        sectionLabel("INPUT FILES")
        Spacer()
        Button(action: model.chooseInputs) { Image(systemName: "plus").foregroundStyle(mint) }
          .buttonStyle(.plain)
      }.padding(16)
      ScrollView {
        VStack(spacing: 4) {
          ForEach(model.project.inputs) { input in
            SourceListRow(model:model,input:input)
          }
        }
      }.frame(height: 130).padding(.horizontal, 7)
      } else {
        Button("Show input files (\(model.project.inputs.count))") { model.showWidgets = false }
          .font(.system(size: 10)).padding(10)
      }
    }.background(panelColor)
  }
  var previewHeader: some View {
    let options = model.previewOptions
    let size = options.size ?? CGSize(width:model.project.width,height:model.project.height)
    return HStack {
      sectionLabel("COMPOSITION")
      if model.usesDesignSamples { Text("SAMPLE DATA").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange).help("Design preview only. Sample values are never saved or exported.") }
      Text("\(Int(size.width)) × \(Int(size.height)) preview").font(
        .system(size: 10, design: .monospaced)
      ).foregroundStyle(muted).help("Project canvas: \(model.project.width) × \(model.project.height)")
      Spacer()
      if model.busy { ProgressView().controlSize(.small) }
      Text("\((options.fps ?? model.project.fps).formatted()) FPS").font(
        .system(size: 9, weight: .bold, design: .monospaced)
      ).foregroundStyle(muted)
      Button { model.showPreviewSettings = true } label: { Image(systemName:"slider.horizontal.3") }
        .buttonStyle(.plain).help("Preview settings")
      Button(action:model.openCompositionWindow) { Image(systemName:"arrow.up.left.and.arrow.down.right") }
        .buttonStyle(.plain).help("Full-screen composition")
      Button(action: model.snapshot) { Image(systemName: "camera").foregroundStyle(muted) }
        .buttonStyle(.plain).help("Save current frame as PNG")
    }.padding(.horizontal, 20).frame(height: 42)
  }
  var emptyState: some View {
    VStack(spacing: 18) {
      Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 46, weight: .ultraLight))
        .foregroundStyle(mint)
      Text("Your footage. Your data.").font(.system(size: 27, weight: .medium))
      Text("Build telemetry videos with an open source, native editor.").font(.system(size: 12))
        .foregroundStyle(muted)
      HStack(spacing: 12) {
        Button("Open RaceRender project…", action: model.chooseOpen).buttonStyle(.borderedProminent)
          .foregroundStyle(bg)
        Button("Add footage & data…", action: model.chooseInputs).buttonStyle(.bordered)
      }
      Text("RRP PROJECTS  /  RRT TEMPLATES  /  RRO STYLES  /  RACECHRONO RCZ & CSV").font(
        .system(size: 9, weight: .medium)
      ).tracking(1).foregroundStyle(muted).padding(.top, 8)
    }
  }
  var transport: some View {
    HStack(spacing: 14) {
      Button {
        model.seek(0)
      } label: {
        Image(systemName: "backward.end.fill")
      }
      Button {
        model.seek(model.time - 1 / model.project.fps)
      } label: {
        Image(systemName: "backward.frame.fill")
      }
      Button(action: model.togglePlayback) {
        Image(systemName: model.playing ? "pause.fill" : "play.fill").foregroundStyle(mint).font(
          .system(size: 17)
        ).frame(width: 25)
      }.keyboardShortcut(.space, modifiers: [])
      Button {
        model.seek(model.time + 1 / model.project.fps)
      } label: {
        Image(systemName: "forward.frame.fill")
      }
      Button(clockText(model.time)) { showSeek.toggle() }
        .font(.system(size: 12, weight: .medium, design: .monospaced)).help("Go to exact time")
        .popover(isPresented: $showSeek) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Go to time (seconds)")
            TextField("Project time", value: Binding(get: { model.time }, set: { model.seek($0) }), format: .number.precision(.fractionLength(0...4)))
              .textFieldStyle(.roundedBorder)
            Button("Done") { showSeek = false }
          }.padding(18).frame(width: 240)
        }
      Text("/  " + clockText(model.project.duration)).font(.system(size: 10, design: .monospaced))
        .foregroundStyle(model.project.explicitDuration != nil ? Color.blue : model.project.lengthInputIndex != nil ? mint : muted)
        .help(model.project.lengthSummary)
      Spacer()
      Button { model.previewMuted.toggle() } label: { Image(systemName: model.previewMuted ? "speaker.slash" : "speaker.wave.2") }.help("Mute preview audio")
      Button("In", action: model.markStart).help("Mark export start at playhead (I)")
      Button("Out", action: model.markEnd).help("Mark export end at playhead (O)")
      Menu {
        Button("Mark export start here", action: model.markStart)
        Button("Mark export end here", action: model.markEnd)
        Button("Clear export marks", action: model.clearMarks)
      } label: { Image(systemName: "flag.checkered") }.frame(width: 24)
      Picker("Speed units", selection: model.speedUnitBinding) {
        Text("MPH").tag("mph")
        Text("km/h").tag("km/h")
        Text("m/s").tag("m/s")
        Text("Knots").tag("knots")
      }.labelsHidden().frame(width: 78)
    }.buttonStyle(.plain).padding(.horizontal, 20).frame(height: 48).background(
      panelColor.opacity(0.7))
  }
  var inspector: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        sectionLabel("INSPECTOR")
        Spacer()
        Image(systemName: "slider.horizontal.3").foregroundStyle(muted)
      }.padding(16)
      Divider()
      ScrollView {
        if model.selectedIDs.count > 1 {
          MultipleSelectionInspector(model: model)
        } else if let id = model.selected, model.project.objects.contains(where: { $0.id == id }) {
          ObjectInspector(object: model.objectBinding(id), model: model)
        } else if let id = model.selectedInput,
          model.project.inputs.contains(where: { $0.id == id })
        {
          if model.project.inputs.first(where:{$0.id == id})?.isTimeFiller == true {
            TimeFillerInspector(model:model,input:model.inputBinding(id))
          } else { InputInspector(input: model.inputBinding(id), model: model) }
        } else {
          projectInspector
        }
      }
    }.background(panelColor)
  }
  var projectInspector: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Session settings").font(.system(size: 16, weight: .semibold))
      TextField("Session name", text: model.projectBinding(\.name))
      Button("Project setup…",action:model.beginProjectSetup)
      SphericalWorkspaceControls(model:model)
      TextField("Project notes", text: Binding(get: { model.project.notes ?? "" }, set: { model.setProjectNotes($0) }), axis: .vertical).lineLimit(2...6)
      HStack {
        TextField("Width", value: model.projectBinding(\.width), format: .number)
        Text("×").foregroundStyle(muted)
        TextField("Height", value: model.projectBinding(\.height), format: .number)
      }
      Picker("Frame rate", selection: model.projectBinding(\.fps)) {
        ForEach([24.0, 25, 29.97, 30, 50, 59.94, 60], id: \.self) { Text($0.formatted()).tag($0) }
      }
      ProjectLengthControls(model:model)
      Divider()
      Text(
        "Click a display to edit its position and data source. Drag it in the preview; drag its upper right handle to resize. Hold Shift to snap to whole percentages."
      ).font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
      Button("Start blank layout", action: model.blankLayout)
      Button("Show widget palette") { model.showWidgets = true }
      Button("Save layout as template…", action: model.saveTemplate)
      Button("Export RaceRender project…", action: model.exportRRP)
    }.textFieldStyle(.roundedBorder).padding(16)
  }
  var timeline: some View {
    VStack(spacing: 0) {
      HStack(spacing: 22) {
        ForEach(
          Array(["Timeline", "Objects", "Telemetry", "Laps", "Import report"].enumerated()), id: \.offset
        ) { i, t in
          Button {
            bottomTab = i
          } label: {
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(
              bottomTab == i ? mint : muted
            ).padding(.vertical, 12).overlay(alignment: .bottom) {
              if bottomTab == i { Rectangle().fill(mint).frame(height: 2) }
            }
          }.buttonStyle(.plain)
        }
        Spacer()
        Text("\(model.activeData?.count.formatted() ?? "0") samples").font(
          .system(size: 10, design: .monospaced)
        ).foregroundStyle(muted)
      }.padding(.horizontal, 20).background(panelColor)
      if bottomTab == 0 {
        VStack(spacing: 6) {
          TimelineZoomControls(model:model)
          HStack {
            Text(clockText(model.timelineLower))
            Spacer()
            Text(clockText((model.timelineLower+model.timelineUpper)/2))
            Spacer()
            Text(clockText(model.timelineUpper))
          }.font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
          TimelineGraph(model: model).frame(height: 45)
          HStack {
            Text("Export: " + clockText(model.project.defaultExportRange.lowerBound) + " → " + clockText(model.project.defaultExportRange.upperBound)).foregroundStyle(mint)
            Spacer()
            if model.project.rangeStart != nil || model.project.rangeEnd != nil { Button("Clear marks", action: model.clearMarks).buttonStyle(.plain) }
          }.font(.system(size: 10, design: .monospaced))
          Slider(
            value: Binding(get: { max(model.timelineLower,min(model.timelineUpper,model.time)) }, set: { model.seek($0) }),
            in: model.timelineLower...max(model.timelineLower+0.001,model.timelineUpper),onEditingChanged:model.setPreviewSeeking
          ).controlSize(.small)
          HStack(spacing: 12) {
            Label("Video", systemImage: "video.fill").foregroundStyle(Color.blue)
            Rectangle().fill(Color.blue.opacity(0.25)).frame(height: 13).overlay(
              alignment: .leading
            ) {
              Text(model.project.inputs.first { $0.kind == "video" }?.name ?? "No video").font(
                .system(size: 8)
              ).padding(.leading, 8)
            }
            Label("Data", systemImage: "waveform.path").foregroundStyle(mint)
            Rectangle().fill(mint.opacity(0.2)).frame(height: 13).overlay(alignment: .leading) {
              Text(model.activeData?.title ?? "No telemetry").font(.system(size: 8)).lineLimit(1)
                .padding(.leading, 8)
            }
          }.font(.system(size: 9))
        }.padding(.horizontal, 20).padding(.vertical, 10)
      } else if bottomTab == 1 {
        ObjectTracks(model: model)
      } else if bottomTab == 2 {
        telemetryPanel
      } else if bottomTab == 3 {
        lapPanel
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            if model.project.warnings.isEmpty { Text("No compatibility issues reported.") }
            ForEach(model.project.warnings, id: \.self) {
              Text("•  " + $0).font(.system(size: 11)).foregroundStyle(muted)
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
      }
      Spacer(minLength: 0)
    }
  }
  var telemetryPanel: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(["speed", "rpm", "gear", "throttle", "gx", "gy", "coolant", "intake"], id: \.self) {
          key in
          VStack(alignment: .leading, spacing: 12) {
            Text(key.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1)
              .foregroundStyle(muted)
            Text(liveValue(key)).font(.system(size: 24, weight: .medium, design: .monospaced))
              .foregroundStyle(key == "speed" ? mint : .white)
            Text(
              model.activeData?.aliases[key].map { model.activeData!.headers[$0] }
                ?? "Channel unavailable"
            ).font(.system(size: 8)).foregroundStyle(muted).lineLimit(1)
          }.padding(14).frame(width: 130, alignment: .leading).background(panelColor).clipShape(
            RoundedRectangle(cornerRadius: 6))
        }
      }.padding(16)
    }
  }
  func liveValue(_ key: String) -> String {
    let v =
      key == "speed"
      ? model.activeData?.speed(at: model.dataTime, unit: model.project.speedUnit)
      : model.activeData?.value(key, at: model.dataTime, interpolate: key != "gear")
    return v.map { String(format: key == "gx" || key == "gy" ? "%.2f" : "%.0f", $0) } ?? "—"
  }
  var lapPanel: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(model.activeData?.laps ?? []) { lap in
          Button {
            model.seek(model.projectTime(for: lap.start))
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text("LAP \(lap.number)").font(.system(size: 9, weight: .bold)).foregroundStyle(muted)
              Text(clockText(lap.duration)).font(.system(size: 18, design: .monospaced))
              Text(
                lap.complete
                  ? (model.activeData?.bestLap?.number == lap.number ? "BEST LAP" : "Complete")
                  : "Partial lap"
              ).font(.system(size: 9)).foregroundStyle(
                model.activeData?.bestLap?.number == lap.number ? mint : muted)
            }.padding(14).background(panelColor).clipShape(RoundedRectangle(cornerRadius: 6))
          }.buttonStyle(.plain)
        }
      }.padding(16)
    }
  }
  var footer: some View {
    HStack {
      Circle().fill(model.busy ? Color.orange : mint).frame(width: 5, height: 5)
      Text(model.status).font(.system(size: 10)).lineLimit(1)
      Spacer()
      if let progress = model.exportProgress {
        ProgressView(value: Double(progress)).frame(width: 140)
        Text("\(Int(progress*100))%").font(.system(size: 10, design: .monospaced))
        Button("Cancel") { model.exporter?.cancel() }.font(.system(size: 10))
      }
      Text("OPEN SOURCE  ·  NATIVE macOS").font(.system(size: 8, weight: .medium)).tracking(1)
        .foregroundStyle(muted)
    }.padding(.horizontal, 16).frame(height: 28).background(panelColor)
  }
}

struct ObjectInspector: View {
  @Binding var object: DisplayObject
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: object.kind.symbol).foregroundStyle(mint)
        Text(object.kind.title).font(.system(size: 16, weight: .semibold))
      }
      SegmentControls(model: model, object: model.project.objects.first { $0.id == object.id } ?? object)
      TextField("Display label", text: $object.name)
      if object.kind == .group {
        Text("Group edits move and resize all members, including their timeline geometry.").font(.caption).foregroundStyle(.secondary)
        Button("Ungroup displays", action: model.ungroupSelection)
      }
      if ![.video, .audio, .group].contains(object.kind) {
        Button("Choose widget style…") { model.showWidgetStyles = true }
        Text(object.style.isEmpty ? "Native style" : object.style).font(.system(size: 10)).foregroundStyle(muted).lineLimit(2)
      }
      Toggle("Visible", isOn: $object.visible)
      Divider()
      small("POSITION & SIZE (%)")
      HStack {
        field("X", $object.x)
        field("Y", $object.y)
      }
      HStack {
        field("Width", $object.width)
        field("Height", $object.height)
      }
      Toggle("Keep aspect ratio when resizing", isOn: $model.lockWidgetAspect)
      Menu("Align to canvas") {
        if model.project.sphericalWorkspace == true {Button("Fill 360 workspace",action:model.fillSphericalSelection);Divider()}
        ForEach(["Left", "Horizontal center", "Right", "Top", "Vertical center", "Bottom"], id: \.self) { alignment in
          Button(alignment) { model.alignWidget(alignment) }
        }
      }
      Text("Option-arrow: move 1 pixel. Add Shift for 10 pixels.").font(.system(size: 9)).foregroundStyle(muted)
      HStack {
        Text("Opacity").font(.system(size: 11)).foregroundStyle(muted)
        Slider(value: $object.opacity, in: 0...1)
      }
      if ![.group,.audio].contains(object.kind) {RGBChannelControls(object:$object)}
      Divider()
      small("DATA SOURCE")
      Picker("Input", selection: $object.inputIndex) {
        Text("None").tag(-1)
        ForEach(model.project.inputs.filter { $0.joinedTo == nil && (object.kind == .image ? ($0.kind == "data" || $0.legacyIndex == object.inputIndex) : $0.kind == (object.kind == .video ? "video" : object.kind == .audio ? "audio" : "data")) }) { Text($0.name).tag($0.legacyIndex) }
      }.labelsHidden()
      if ![.video, .audio, .image, .text, .shape].contains(object.kind) || object.imageUsesData {
        Picker("Channel", selection: $object.channel) {
          Text("Automatic").tag("")
          if !object.channel.isEmpty, !(model.telemetry[object.inputIndex]?.headers.contains(object.channel) ?? false) {
            Text(object.channel).tag(object.channel)
          }
          ForEach(model.telemetry[object.inputIndex]?.headers ?? [], id: \.self) {
            Text($0).tag($0)
          }
        }.labelsHidden()
        if !object.resolvedChannel.isEmpty, let data = model.telemetry[object.inputIndex] {
          if let index = data.channelIndex(object.resolvedChannel) {
            Text("Using \(data.headers[index])").font(.system(size: 10)).foregroundStyle(muted)
            if let provenance = data.provenance(for:object.resolvedChannel), provenance.kind != .recorded {
              Text(provenance.details).font(.system(size:10)).foregroundStyle(mint)
            }
          } else {
            Text("Channel unavailable in this input").font(.system(size: 10)).foregroundStyle(.orange)
          }
        }
        if object.kind != .image {
          if object.hasStyleRange { WidgetRangeControls(object: $object) }
          else { HStack {
            field("Min", $object.minimum)
            field("Max", $object.maximum)
          } }
          if !object.hasScriptStyleSettings && object.legacyType != 31 && object.kind != .graph {
          ColorPicker(
            "Accent",
            selection: Binding(
              get: { Color(cgColor: OverlayRenderer.color(object.color)) },
              set: { c in
                if let rgb = NSColor(c).usingColorSpace(.deviceRGB) {
                  object.color = String(
                    format: "#%02X%02X%02X", Int(rgb.redComponent * 255),
                    Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
                }
              }))
          }
        }
      }
      if ![.video,.audio,.image,.group].contains(object.kind) { BackgroundControls(model:model,object:$object) }
      if object.kind == .image { ImageControlControls(object: $object, inputs: model.project.inputs) }
      if object.hasScriptStyleSettings { ScriptStyleControls(object: $object) }
      if object.canEditScripts {
        Button(object.hasScriptStyleSettings ? "Edit drawing scripts…" : "Create drawing scripts…") {model.beginScriptEditor(object.id)}
      }
      if object.hud != nil {
        HUDControls(settings: Binding(get: { object.hud! }, set: { object.hud = $0 }))
      }
      if [.speed, .rpm, .gauge].contains(object.kind) {
        GaugeControls(settings: Binding(get: { object.gauge ?? GaugeSettings() }, set: { object.gauge = $0 }))
        GaugeDesignControls(object: $object)
      }
      if object.kind == .map {
        MapDisplayControls(object:$object,data:model.telemetry[object.inputIndex])
        MapComparisonControls(model:model,object:$object)
      }
      if object.kind == .timer { TimerControls(object:$object,model:model) }
      if object.kind == .graph { GraphControls(object: $object, headers: model.telemetry[object.inputIndex]?.headers ?? []) }
      if object.kind == .text {
        TextField("Text", text: $object.text, axis: .vertical).lineLimit(2...5)
        TypographyControls(settings: Binding(get: { object.typography ?? TextSettings() }, set: { object.typography = $0 }), color: $object.color)
      }
      if object.kind == .shape {
        ShapeControls(settings: Binding(get: { object.shape ?? ShapeSettings() }, set: { object.shape = $0 }), color: $object.color)
      }
      if [.video, .audio].contains(object.kind) {
        AudioControls(settings: Binding(get: { object.audio ?? AudioSettings() }, set: { object.audio = $0 })).id(object.id)
      }
      Divider()
      if [.video, .image].contains(object.kind),
        let input = model.project.inputs.first(where: { $0.legacyIndex == object.inputIndex }) {
        Button("Edit input picture settings…") { model.selected = nil; model.selectedInput = input.id }
          .help("Adjust every display that uses this input, including imported RaceRender picture settings.")
        Text("The adjustments below affect only this display.").font(.system(size: 10)).foregroundStyle(muted)
      }
      PictureControls(settings: Binding(get: { object.picture ?? PictureSettings() }, set: { object.picture = $0 }), media: [.video, .image].contains(object.kind))
      small(model.editingSegment == nil ? "ACTIVE TIME RANGE" : "ACTIVE TIME RANGE · EDIT IN BASE SETTINGS")
      HStack {
        field("Start (s)", $object.start)
        field("End (s)", $object.end)
      }
      if !object.style.isEmpty {
        Text("Imported style: \(object.style)").font(.system(size: 10)).foregroundStyle(muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button("Save this display as a reusable style…", action: model.saveSelectedStyle)
      HStack {
        Button("Duplicate", action: model.duplicate)
        Button(role: .destructive, action: model.deleteSelected) { Image(systemName: "trash") }
        Spacer()
        Button {
          model.move(-1)
        } label: {
          Image(systemName: "arrow.down")
        }
        Button {
          model.move(1)
        } label: {
          Image(systemName: "arrow.up")
        }
      }
    }.textFieldStyle(.roundedBorder).controlSize(.small).padding(16)
  }
  func small(_ s: String) -> some View {
    Text(s).font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(muted)
  }
  func field(_ label: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.system(size: 10)).foregroundStyle(muted)
      TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
    }
  }
}

struct InputInspector: View {
  @Binding var input: MediaInput
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(alignment: .leading, spacing: 17) {
      Text("Input settings").font(.system(size: 16, weight: .semibold))
      TextField("Label", text: $input.name)
      Text(input.path).font(.system(size: 10)).foregroundStyle(muted).textSelection(.enabled)
        .lineLimit(5)
      if !input.path.isEmpty && !input.exists {
        Label("File unavailable. Relink to restore preview and export.", systemImage: "exclamationmark.triangle")
          .font(.system(size: 11)).foregroundStyle(.orange)
      }
      if input.isJoinRoot == true {
        Text("Joined stream · source files are configured in its child clips.").font(.caption).foregroundStyle(muted)
      } else {
        Button(input.path.isEmpty ? "Choose source file…" : "Relink file…") { model.relink(input.id) }
          .disabled(model.busy)
      }
      Divider()
      Text("Synchronization").font(.system(size: 13, weight: .semibold))
      Text("Increase the offset to advance this source relative to its trimmed start. Set playback rate and project delay below.").font(
        .system(size: 11)
      ).foregroundStyle(muted)
      TextField(
        "Offset in seconds", value: $input.offset, format: .number.precision(.fractionLength(0...6))
      )
      HStack {
        Button("−1 s") { input.offset -= 1 }
        Button("−0.1") { input.offset -= 0.1 }
        Button("+0.1") { input.offset += 0.1 }
        Button("+1 s") { input.offset += 1 }
      }
      if input.kind == "data" {
        HStack {
          Button("−1 frame") { model.nudgeOffset(input.id, frames: -1) }
          Button("+1 frame") { model.nudgeOffset(input.id, frames: 1) }
        }.help("Adjust synchronization by one video frame at the project's frame rate and this input's playback rate.")
      }
      Text("Source at playhead: " + clockText(model.project.sourceTime(for: input.legacyIndex, at: model.time) ?? -1)).font(
        .system(size: 10, design: .monospaced)
      ).foregroundStyle(mint)
      if ["video","audio"].contains(input.kind) && input.isJoinRoot != true {
        Divider()
        AudioControls(settings: Binding(get: { input.audio ?? AudioSettings() }, set: { input.audio = $0 }), source: true, sourceVolume:$input.volume).id(input.id)
      }
      InputTimingControls(input: $input, model: model)
      if let d = model.telemetry[input.legacyIndex] {
        Divider()
        Text("\(d.count.formatted()) samples\n\(d.headers.count) channels\n\(d.laps.count) laps")
          .font(.system(size: 11, design: .monospaced)).foregroundStyle(muted).lineSpacing(6)
      }
    }.textFieldStyle(.roundedBorder).controlSize(.small).padding(16)
  }
}

struct TimelineGraph: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    Canvas { c, size in
      let d = model.activeData
      let maxTime = model.timelineSpan
      let startTime = model.timelineLower
      var path = Path()
      var started = false
      for i in 0..<500 {
        let t = startTime + Double(i) / 499 * maxTime
        if let d, let index = model.dataIndex, let source = model.project.sourceTime(for:index,at:t),
          source >= 0, source <= d.duration, let v = d.speed(at:source,unit:model.project.speedUnit) {
          let p = CGPoint(
            x: Double(i) / 499 * size.width, y: size.height - max(0, min(1, v / 160)) * size.height)
          if started {
            path.addLine(to: p)
          } else {
            path.move(to: p)
            started = true
          }
        } else { started = false }
      }
      c.stroke(path, with: .color(mint.opacity(0.7)), lineWidth: 1)
      for lap in d?.laps ?? [] {
        let x = (model.projectTime(for: lap.start)-startTime) / maxTime * size.width
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        c.stroke(
          line, with: .color(muted.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
      }
      if model.project.rangeStart != nil || model.project.rangeEnd != nil {
        let range = model.project.defaultExportRange
        let a = (range.lowerBound-startTime)/maxTime*size.width, b = (range.upperBound-startTime)/maxTime*size.width
        c.fill(Path(CGRect(x: a, y: 0, width: max(0, b-a), height: size.height)), with: .color(mint.opacity(0.12)))
        for (position, color) in [(a, Color.green), (b, Color.red)] {
          var mark = Path(); mark.move(to: CGPoint(x: position, y: 0)); mark.addLine(to: CGPoint(x: position, y: size.height))
          c.stroke(mark, with: .color(color), lineWidth: 2)
        }
      }
      let x = (model.time-startTime) / maxTime * size.width
      var cursor = Path()
      cursor.move(to: CGPoint(x: x, y: 0))
      cursor.addLine(to: CGPoint(x: x, y: size.height))
      c.stroke(cursor, with: .color(.white), lineWidth: 1.5)
    }.background(panelColor).clipped().contentShape(Rectangle()).gesture(
      DragGesture(minimumDistance: 0).onChanged {
        event in /* width supplied by GeometryReader below */
      }
    )
    .overlay {
      GeometryReader { g in
        Color.clear.contentShape(Rectangle()).gesture(
          DragGesture(minimumDistance: 0).onChanged { v in
            model.setPreviewSeeking(true)
            model.seek(model.timelineLower + max(0,min(1,v.location.x/max(1,g.size.width)))*model.timelineSpan)
          }.onEnded { _ in model.setPreviewSeeking(false) })
      }
    }
  }
}
