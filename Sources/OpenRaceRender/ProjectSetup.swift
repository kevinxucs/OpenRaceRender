import RaceCore
import SwiftUI

extension EditorModel {
  var speedUnitBinding: Binding<String> {
    Binding(get:{ self.project.speedUnit },set:{ self.setPreferredSpeedUnit($0) })
  }
  func setPreferredSpeedUnit(_ unit:String) {
    guard RaceProject.speedUnits.contains(unit) else { return }
    preferredSpeedUnit = unit
    projectBinding(\.speedUnit).wrappedValue = unit
  }
  func setProjectNotes(_ text:String) {
    let value: String? = text.isEmpty ? nil : text
    guard project.notes != value else { return }
    checkpoint(); project.notes = value
  }
  func matchProjectLength(to index:Int?) {
    do {
      var updated = project; try updated.matchLength(to:index)
      guard updated != project else { return }
      checkpoint(); project = updated
    } catch { self.error = error.localizedDescription }
  }
  func setProjectLength(_ seconds:Double) {
    do {
      var updated = project; try updated.setManualLength(seconds)
      guard updated != project else { return }
      checkpoint(); project = updated
    } catch { self.error = error.localizedDescription }
  }
  func beginProjectSetup() { pause(); showProjectSetup = true }
  var synchronizationPreviewActive: Bool { showSync || setupSyncActive }
}

struct ProjectLengthControls: View {
  @ObservedObject var model:EditorModel
  var mode: Int { model.project.explicitDuration != nil ? 2 : model.project.lengthInputIndex != nil ? 1 : 0 }
  var body:some View {
    VStack(alignment:.leading,spacing:9) {
      Picker("Project length",selection:Binding(get:{mode},set:{ value in
        if value == 2 { model.setProjectLength(model.project.duration) }
        else if value == 1, let input = model.project.lengthInputs.first { model.matchProjectLength(to:input.legacyIndex) }
        else { model.matchProjectLength(to:nil) }
      })) {
        Text("Longest input").tag(0)
        Text("Match an input").tag(1)
        Text("Manual").tag(2)
      }
      if mode == 1 {
        Picker("Length source",selection:Binding(get:{model.project.lengthInputIndex ?? -1},set:{model.matchProjectLength(to:$0)})) {
          if !model.project.lengthInputs.contains(where:{ $0.legacyIndex == model.project.lengthInputIndex }) {
            Text("Unavailable source").tag(model.project.lengthInputIndex ?? -1)
          }
          ForEach(model.project.lengthInputs) { Text($0.name).tag($0.legacyIndex) }
        }
      } else if mode == 2 {
        NumberSetting("Project seconds",value:Binding(get:{model.project.explicitDuration ?? 60},set:{model.setProjectLength($0)}))
      }
      Text(model.project.lengthSummary + " · " + clockText(model.project.duration))
        .font(.caption).foregroundStyle(mode == 1 ? mint : mode == 2 ? .blue : muted)
    }
  }
}

private enum SetupTool: Identifiable {
  case trim(UUID), sync(Int), template(Int?)
  var id:String {
    switch self {
    case .trim(let id): return "trim-\(id)"
    case .sync(let index): return "sync-\(index)"
    case .template(let index): return "template-\(index ?? -1)"
    }
  }
}

struct ProjectSetupSheet: View {
  @ObservedObject var model:EditorModel
  @Environment(\.dismiss) var dismiss
  @State private var primary = -1
  @State private var dataIndex = -1
  @State private var tool:SetupTool?
  var primaryInput:MediaInput? { model.project.lengthInputs.first { $0.legacyIndex == primary } }
  var dataInputs:[MediaInput] { model.project.lengthInputs.filter { $0.kind == "data" } }
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      HStack { Text("Project setup").font(.title2); Spacer(); Button("Add inputs…",action:model.chooseInputs).disabled(model.busy) }
      if model.busy { ProgressView("Reading inputs…") }
      if let error = model.error {
        HStack { Text(error).font(.caption).foregroundStyle(.red); Spacer(); Button("Dismiss") { model.error = nil } }
      }
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          primaryStep
          Divider()
          synchronizationStep
          Divider()
          layoutStep
          Divider()
          settingsStep
        }.padding(2)
      }
      HStack {
        Toggle("Use setup for new sessions",isOn:$model.setupOnNewProjects)
        Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      Text("Changes apply to this project as you go and can be undone in the editor.").font(.caption).foregroundStyle(muted)
    }.padding(22).frame(width:760,height:720).background(bg).preferredColorScheme(.dark).tint(mint)
      .textFieldStyle(.roundedBorder)
      .onAppear { refreshInputs() }
      .onChange(of:model.project.inputs.map(\.id)) { _,_ in refreshInputs() }
      .onDisappear { model.setupSyncActive = false; model.pause() }
      .sheet(item:$tool,onDismiss:{ model.setupSyncActive = false; model.pause() }) { value in
        switch value {
        case .trim(let id):
          if model.project.inputs.contains(where:{ $0.id == id }) { SourceTrimEditor(model:model,input:model.inputBinding(id)) }
        case .sync(let index):
          SyncSheet(model:model,initialInputIndex:index)
        case .template(let index):
          TemplateBrowser(model:model,preferredDataIndex:index)
        }
      }
  }
  var primaryStep:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("1. Choose and trim the primary input").font(.headline)
      Picker("Primary input",selection:$primary) {
        Text("Choose an input").tag(-1)
        ForEach(model.project.lengthInputs) { Text($0.name).tag($0.legacyIndex) }
      }
      if let input = primaryInput {
        HStack {
          Button("Trim start & end…") { tool = .trim(input.id) }.disabled(input.isJoinRoot == true || model.busy)
          Button("Set project length to match") { model.matchProjectLength(to:primary) }.disabled(model.busy)
          if model.project.lengthInputIndex == primary && model.project.explicitDuration == nil {
            Label("Length follows this input",systemImage:"link").font(.caption).foregroundStyle(mint)
          }
        }
        if input.isJoinRoot == true { Text("For a joined stream, trim its physical clips in the input inspector.").font(.caption).foregroundStyle(muted) }
      } else { Text("Add a video, audio or telemetry file to begin.").font(.callout).foregroundStyle(muted) }
    }
  }
  var synchronizationStep:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("2. Synchronize the other inputs").font(.headline)
      ForEach(model.project.lengthInputs.filter { $0.legacyIndex != primary }) { input in
        HStack {
          Label(input.name,systemImage:input.kind == "data" ? "waveform.path" : "video").lineLimit(1)
          Spacer()
          Text("Offset \(input.offset.formatted(.number.precision(.fractionLength(3)))) s").font(.caption).foregroundStyle(muted)
          if input.kind == "data" {
            Button("Synchronize…") { model.pause(); model.setupSyncActive = true; tool = .sync(input.legacyIndex) }
              .disabled(model.busy || !model.project.inputs.contains(where:{$0.kind == "video"}))
          }
          Button("Edit input") { model.selected = nil; model.selectedInput = input.id; dismiss() }
        }
      }
      Text("Align a recorded lap/event to the video frame. Camera offsets and rates are available in Edit input.").font(.caption).foregroundStyle(muted)
    }
  }
  var layoutStep:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("3. Configure data and displays").font(.headline)
      Picker("Data input",selection:$dataIndex) {
        Text("No data input").tag(-1)
        ForEach(dataInputs) { Text($0.name).tag($0.legacyIndex) }
      }
      HStack {
        Button("Choose template…") { tool = .template(dataIndex < 0 ? nil : dataIndex) }.disabled(model.busy)
        Button("Configure data") {
          model.selected = nil; model.selectedInput = dataInputs.first(where:{$0.legacyIndex == dataIndex})?.id; dismiss()
        }.disabled(dataIndex < 0)
        Button("Add display objects") { model.showWidgets = true; model.selectedInput = nil; dismiss() }
      }
      Text("The selected data input is the default mapping for template data roles. The template dialog lets you map each role separately.").font(.caption).foregroundStyle(muted)
    }
  }
  var settingsStep:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("Project settings").font(.headline)
      TextField("Session name",text:model.projectBinding(\.name))
      ProjectLengthControls(model:model)
      Picker("Preferred speed unit",selection:model.speedUnitBinding) {
        ForEach(RaceProject.speedUnits,id:\.self) { Text($0).tag($0) }
      }
      Text("The chosen speed unit is also used for new sessions.").font(.caption).foregroundStyle(muted)
      TextField("Project notes",text:Binding(get:{model.project.notes ?? ""},set:{model.setProjectNotes($0)}),axis:.vertical).lineLimit(3...6)
    }
  }
  func refreshInputs() {
    if !model.project.lengthInputs.contains(where:{$0.legacyIndex == primary}) {
      primary = model.project.lengthInputIndex ?? model.project.lengthInputs.first(where:{$0.kind == "video"})?.legacyIndex
        ?? model.project.lengthInputs.first?.legacyIndex ?? -1
    }
    if !dataInputs.contains(where:{$0.legacyIndex == dataIndex}) {
      dataIndex = dataInputs.first(where:{$0.id == model.selectedInput})?.legacyIndex ?? dataInputs.first?.legacyIndex ?? -1
    }
  }
}
