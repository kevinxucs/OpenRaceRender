import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

struct DataSetupRequest:Identifiable {
  let id = UUID()
  var url:URL
  var headers:[String]
  var rows:[[String]] = []
  var revision:UUID
  var original:MediaInput?
  var settings:DataSettings { original?.dataSettings ?? DataSettings() }
}
struct DataSetupPreview {
  var url:URL
  var settings:DataSettings
  var data:Telemetry
  static func load(_ url:URL,settings:DataSettings) async throws -> Self {
    try await Task.detached { Self(url:url,settings:settings,data:try Telemetry(url:url,settings:settings)) }.value
  }
}

extension EditorModel {
  func enqueueDataSetup(_ request:DataSetupRequest) {
    guard request.revision == documentRevision else { return }
    if dataSetupRequest == nil { dataSetupRequest = request }
    else { dataSetupQueue.append(request) }
  }
  func nextDataSetup() {
    dataSetupQueue.removeAll{$0.revision != documentRevision}
    if dataSetupRequest == nil,!dataSetupQueue.isEmpty { dataSetupRequest = dataSetupQueue.removeFirst() }
  }
  func configureData(_ input:MediaInput) {
    guard input.kind == "data",input.exists else { error = "Relink this data source first."; return }
    let url = URL(fileURLWithPath:input.path)
    let columns = try? TelemetryColumnPreview.read(url)
    let headers = telemetry[input.legacyIndex]?.recordedHeaders ?? columns?.headers ?? []
    enqueueDataSetup(DataSetupRequest(url:url,headers:headers,rows:columns?.rows ?? [],revision:documentRevision,original:input))
  }
  /// Install the exact configuration that was previewed, as one undoable change.
  @discardableResult func applyDataSetup(_ request:DataSetupRequest,preview:DataSetupPreview) -> Bool {
    guard request.revision == documentRevision,preview.url.standardizedFileURL == request.url.standardizedFileURL else { return false }
    if let original = request.original {
      guard let index = project.inputs.firstIndex(where:{$0.id == original.id}),project.inputs[index] == original else { return false }
      checkpoint()
      project.inputs[index].dataSettings = preview.settings
      project.inputs[index].duration = preview.data.duration
      telemetry[original.legacyIndex] = preview.data
    } else {
      var input = MediaInput(name:request.url.deletingPathExtension().lastPathComponent,path:request.url.path,kind:"data")
      input.duration = preview.data.duration; input.dataSettings = preview.settings
      installInput(input,data:preview.data)
    }
    project.warnings += preview.data.warnings.filter{!project.warnings.contains($0)}
    configurePlayers(); status = "Data configuration applied · " + clockText(preview.data.duration)
    return true
  }
}

struct DataAssignmentControls:View {
  @Binding var settings:DataSettings
  var headers:[String]
  var body:some View {
    ForEach(DataRole.allCases,id:\.rawValue) { role in
      let value = settings.assignments[role.rawValue] ?? ""
      Picker(role.title,selection:Binding(get:{settings.assignments[role.rawValue] ?? ""},set:{settings.assignments[role.rawValue] = $0})) {
        Text("Automatic").tag("")
        if !value.isEmpty,!headers.contains(where:{$0.caseInsensitiveCompare(value) == .orderedSame}) { Text("Missing: " + value).tag(value) }
        ForEach(headers,id:\.self) { Text($0).tag($0) }
      }
    }
    TextField("Time units per second",value:Binding(get:{settings.timeUnitsPerSecond ?? 1},set:{settings.timeUnitsPerSecond = $0}),format:.number)
    Text("1 for seconds, 1000 for milliseconds. The first sample becomes session time zero.").font(.caption).foregroundStyle(.secondary)
    Toggle("Override recorded speed units",isOn:Binding(get:{settings.speedConversionEnabled ?? (settings.speedMultiplier != nil && settings.assignments["speed"]?.isEmpty == false)},set:{
      settings.speedConversionEnabled = $0 ? true : nil
      if !$0 { settings.speedMultiplier = nil; settings.speedUnit = nil }
    }))
    if settings.speedConversionEnabled == true || (settings.speedConversionEnabled == nil && settings.speedMultiplier != nil && settings.assignments["speed"]?.isEmpty == false) {
      TextField("Speed multiplier",value:Binding(get:{settings.speedMultiplier ?? 1},set:{settings.speedMultiplier = $0}),format:.number)
      Picker("Units after multiplication",selection:Binding(get:{settings.speedUnit ?? "mph"},set:{settings.speedUnit = $0})) {
        ForEach(RaceProject.speedUnits,id:\.self){Text($0).tag($0)}
      }
      Text("Recorded speed × multiplier, interpreted in these units, then converted for each widget.").font(.caption).foregroundStyle(.secondary)
    }
    Toggle("Convert GPS accuracy to meters",isOn:Binding(get:{settings.accuracyMultiplier != nil},set:{settings.accuracyMultiplier = $0 ? 1 : nil}))
    if settings.accuracyMultiplier != nil {
      TextField("Accuracy multiplier",value:Binding(get:{settings.accuracyMultiplier ?? 1},set:{settings.accuracyMultiplier = $0}),format:.number)
    }
  }
}

struct DataSetupSheet:View {
  @ObservedObject var model:EditorModel
  var request:DataSetupRequest
  @Environment(\.dismiss) private var dismiss
  @State private var settings:DataSettings
  @State private var preview:DataSetupPreview?
  @State private var loading = false
  @State private var failure:String?
  @State private var profileName:String
  @State private var includeTrack = false
  @State private var position:Double = 0
  init(model:EditorModel,request:DataSetupRequest) {
    self.model = model; self.request = request
    _settings = State(initialValue:request.settings)
    _profileName = State(initialValue:request.url.deletingPathExtension().lastPathComponent)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Configure data source").font(.title2.bold())
      Text(request.url.lastPathComponent).foregroundStyle(.secondary)
      HStack(alignment:.top,spacing:20) {
        ScrollView {
          Form {
            SourceLocationControls(settings:$settings)
            DataSmoothingControls(settings:$settings)
            DataAssignmentControls(settings:$settings,headers:request.headers)
          }.padding(8)
        }.frame(width:380)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          Text("Map recorded columns, then preview to check the session clock and values. Nothing is applied until you choose Apply.").font(.callout)
          if let preview {
            Text("\(preview.data.count.formatted()) samples · \(clockText(preview.data.duration))").font(.headline)
            if let name = preview.data.locationName {Text("Location: "+name).font(.caption)}
            valuePreview(preview.data)
            Slider(value:$position,in:0...max(0.001,preview.data.duration))
            Text("Session time: " + clockText(position)).font(.caption.monospacedDigit())
          } else if !request.rows.isEmpty {
            ScrollView([.horizontal,.vertical]) {
              Text(([request.headers]+request.rows).map{$0.joined(separator:"  |  ")}.joined(separator:"\n"))
                .font(.system(size:11,design:.monospaced)).textSelection(.enabled)
            }.frame(height:200)
          }
          if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
          Button(loading ? "Reading data…" : "Preview configuration") { Task { await loadPreview() } }.disabled(loading)
          Divider()
          TextField("Profile name",text:$profileName)
          Toggle("Include track / finish-line settings",isOn:$includeTrack)
          HStack {
            Button("Import profile…",action:importProfile)
            Button("Export profile…",action:exportProfile)
          }.disabled(loading)
          Text("OpenRaceRender .orrd profiles store data settings. Paths, synchronization offsets and video marks stay in the project. Native RaceRender data-profile files are not yet supported.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,8) }.frame(width:400)
      }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Apply") {
          if let preview,preview.settings == settings,model.applyDataSetup(request,preview:preview) { dismiss() }
          else { failure = "The source or document changed. Reopen data configuration and preview again." }
        }.keyboardShortcut(.defaultAction).disabled(preview == nil || loading)
      }
    }.padding(20).frame(width:840,height:690)
      .onChange(of:settings) { _ in preview = nil; failure = nil; position = 0 }
      .task { if request.original != nil { await loadPreview() } }
  }
  func valuePreview(_ data:Telemetry) -> some View {
    VStack(alignment:.leading,spacing:5) {
      ForEach(DataRole.allCases,id:\.rawValue) { role in
        if let value = data.value(role.rawValue,at:position) {
          Text("\(role.title): \(value.formatted(.number.precision(.fractionLength(0...3))))").font(.caption.monospacedDigit())
        }
      }
    }.frame(maxWidth:.infinity,alignment:.leading)
  }
  func loadPreview() async {
    loading = true; failure = nil; preview = nil
    let snapshot = settings
    defer { loading = false }
    do {
      let result = try await DataSetupPreview.load(request.url,settings:snapshot)
      guard !Task.isCancelled,settings == snapshot else { return }
      preview = result
    } catch { if settings == snapshot { failure = error.localizedDescription } }
  }
  func importProfile() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.data]
    panel.message = "Choose an OpenRaceRender .orrd data profile. Review missing columns and preview before applying."
    guard panel.runModal() == .OK,let url = panel.url else { return }
    do {
      let profile = try DataProfile.read(url)
      settings = profile.applying(to:settings); profileName = profile.name; includeTrack = profile.includesTrackSettings
    } catch { failure = error.localizedDescription }
  }
  func exportProfile() {
    do {
      let profile = DataProfile(name:profileName,settings:settings,includeTrackSettings:includeTrack)
      try profile.validate()
      let panel = NSSavePanel(); panel.nameFieldStringValue = profileName+".orrd"
      panel.allowedContentTypes = [UTType(exportedAs:"org.openracerender.data-profile",conformingTo:.json)]
      guard panel.runModal() == .OK,let url = panel.url else { return }
      try profile.save(url)
    } catch { failure = error.localizedDescription }
  }
}
