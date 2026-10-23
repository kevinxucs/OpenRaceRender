import AVFoundation
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class EditorModel: ObservableObject {
  @Published var project = RaceProject() { didSet {
    schedulePreview()
    if oldValue.inputs.map(\.dataSettings) != project.inputs.map(\.dataSettings) { scheduleTelemetry() }
  } }
  @Published var telemetry: [Int: Telemetry] = [:]
  @Published var selected: UUID? { didSet { if oldValue != selected { editingSegment = nil } } }
  @Published var editingSegment: Double?
  @Published var previewPlayer: AVPlayer?
  @Published var previewMuted = false { didSet { previewPlayer?.isMuted = previewMuted } }
  @Published var showSync = false
  @Published var selectedInput: UUID?
  @Published var time: Double = 0
  @Published var playing = false
  @Published var busy = false
  @Published var status = "Ready · Open a project or add video and telemetry"
  @Published var error: String?
  @Published var showTemplates = false
  @Published var showExport = false
  @Published var exportProgress: Float?
  @Published var exportStart: Double = 0
  @Published var exportDuration: Double = 10
  @Published var fileURL: URL?
  @Published var dirty = false
  private var previewTask: Task<Void, Never>?
  private var telemetryTask: Task<Void, Never>?
  private var previewObservation: NSKeyValueObservation?
  var exporter: VideoExporter?
  private var timer: Timer?
  private var epoch = 0.0
  private var epochTime = 0.0
  private var undoStack: [RaceProject] = []
  private var redoStack: [RaceProject] = []
  var scene: RenderScene { RenderScene(project: project, telemetry: telemetry) }
  var activeData: Telemetry? { telemetry.sorted { $0.key < $1.key }.first?.value }
  var dataIndex: Int? { project.inputs.first { $0.kind == "data" }?.legacyIndex }
  var dataTime: Double { dataIndex.flatMap { project.sourceTime(for: $0, at: time) } ?? -1 }
  var dataOffset: Double { project.inputs.first { $0.kind == "data" }?.offset ?? 0 }
  func projectTime(for source: Double, inputIndex: Int? = nil) -> Double {
    project.placements.first { $0.input.legacyIndex == (inputIndex ?? dataIndex) }?.projectTime(for: source) ?? source
  }
  init() {
    timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }
  func checkpoint() {
    undoStack.append(project)
    if undoStack.count > 60 { undoStack.removeFirst() }
    redoStack = []
    dirty = true
  }
  func undo() {
    guard let p = undoStack.popLast() else { return }
    redoStack.append(project)
    project = p
    dirty = true
    configurePlayers()
  }
  func redo() {
    guard let p = redoStack.popLast() else { return }
    undoStack.append(project)
    project = p
    dirty = true
    configurePlayers()
  }
  func objectBinding(_ id: UUID) -> Binding<DisplayObject> {
    Binding(
      get: {
        let object = self.project.objects.first { $0.id == id } ?? DisplayObject(name: "", kind: .text)
        return self.editingSegment.map { object.resolved(at: $0) } ?? object
      },
      set: { value in
        guard let i = self.project.objects.firstIndex(where: { $0.id == id }) else { return }
        self.checkpoint()
        self.updateObject(at: i, value: value)
      })
  }
  func inputBinding(_ id: UUID) -> Binding<MediaInput> {
    Binding(
      get: {
        self.project.inputs.first { $0.id == id } ?? MediaInput(name: "", path: "", kind: "data")
      },
      set: { value in
        guard let i = self.project.inputs.firstIndex(where: { $0.id == id }) else { return }
        self.checkpoint()
        self.project.inputs[i] = value
        self.seek(self.time)
      })
  }
  func tick() {
    guard playing else { return }
    let t = epochTime + CFAbsoluteTimeGetCurrent() - epoch
    if t >= project.duration {
      seek(project.duration)
      pause()
    } else {
      time = t
    }
  }
  func togglePlayback() { playing ? pause() : play() }
  func play() {
    if time >= project.duration { seek(0) }
    epoch = CFAbsoluteTimeGetCurrent()
    epochTime = time
    playing = true
    syncPlayers(play: true)
  }
  func pause() {
    playing = false
    previewPlayer?.pause()
  }
  func seek(_ t: Double) {
    time = max(0, min(project.duration, t))
    epochTime = time
    epoch = CFAbsoluteTimeGetCurrent()
    syncPlayers(play: playing)
  }
  func syncPlayers(play: Bool) {
    guard let player = previewPlayer else { return }
    player.seek(to: CMTime(seconds: time, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    if play { player.play() } else { player.pause() }
  }
  func schedulePreview() {
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let self else { return }
        let scene = self.scene
        guard scene.project.inputs.contains(where: { $0.kind == "video" && $0.exists }) else {
          self.previewPlayer?.pause(); self.previewPlayer = nil; return
        }
        let prepared = try await VideoExporter.prepare(scene: scene)
        try Task.checkCancellation()
        let item = AVPlayerItem(asset: prepared.composition)
        item.videoComposition = prepared.video
        item.audioMix = prepared.audio
        let player = AVPlayer(playerItem: item)
        player.isMuted = self.previewMuted
        self.previewPlayer?.pause()
        self.previewPlayer = player
        self.previewObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
          guard item.status == .readyToPlay else { return }
          Task { @MainActor in
            guard let self, self.previewPlayer === player else { return }
            self.syncPlayers(play: self.playing)
          }
        }
        self.syncPlayers(play: self.playing)
      } catch is CancellationError {} catch {
        guard !Task.isCancelled else { return }
        self?.status = "Preview: " + error.localizedDescription
      }
    }
  }
  func configurePlayers() { schedulePreview() }
  func scheduleTelemetry() {
    telemetryTask?.cancel()
    telemetryTask = Task {
      do {
        try await Task.sleep(nanoseconds: 400_000_000)
        let result = try await Self.loadTelemetry(project)
        try Task.checkCancellation()
        telemetry = result; schedulePreview()
      } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func updateObject(at index: Int, value: DisplayObject) {
    if let time = editingSegment {
      let old = project.objects[index].resolved(at: time)
      project.objects[index].editSegment(at: time, from: old, to: value)
      // These controls configure the whole object, independent of segment overrides.
      project.objects[index].name = value.name
      project.objects[index].minimum = value.minimum
      project.objects[index].maximum = value.maximum
      project.objects[index].picture = value.picture
      project.objects[index].gauge = value.gauge
    } else { project.objects[index] = value }
  }
  func addSegment() {
    guard let index = project.objects.firstIndex(where: { $0.id == selected }), time > 0 else { return }
    checkpoint()
    var segments = project.objects[index].segments ?? []
    if !segments.contains(where: { abs($0.time-time) < 0.000001 }) { segments.append(ObjectSegment(time: time)) }
    project.objects[index].segments = segments.sorted { $0.time < $1.time }
    editingSegment = time
  }
  func removeSegment() {
    guard let index = project.objects.firstIndex(where: { $0.id == selected }), let t = editingSegment else { return }
    checkpoint(); project.objects[index].segments?.removeAll { $0.time == t }; editingSegment = nil
  }
  func joinPrevious(_ id: UUID) {
    guard let i = project.inputs.firstIndex(where: { $0.id == id }), i > 0,
      ["video", "audio"].contains(project.inputs[i].kind), project.inputs[i-1].kind == project.inputs[i].kind else { return }
    checkpoint()
    let root = project.inputs[i-1].joinedTo ?? project.inputs[i-1].legacyIndex
    let child = project.inputs[i].legacyIndex
    project.inputs[i].joinedTo = root
    for j in project.inputs.indices where project.inputs[j].joinedTo == child { project.inputs[j].joinedTo = root }
    project.objects.removeAll { $0.inputIndex == child && [.video, .audio].contains($0.kind) }
  }
  func unjoin(_ id: UUID) {
    guard let i = project.inputs.firstIndex(where: { $0.id == id }), project.inputs[i].joinedTo != nil else { return }
    checkpoint(); project.inputs[i].joinedTo = nil
    var o = DisplayObject(name: project.inputs[i].name, kind: project.inputs[i].kind == "video" ? .video : .audio)
    o.inputIndex = project.inputs[i].legacyIndex; o.x = 0; o.y = 0; o.width = 100; o.height = 100
    project.objects.insert(o, at: 0)
  }
  func removeInput(_ id: UUID) {
    guard let input = project.inputs.first(where: { $0.id == id }) else { return }
    checkpoint()
    let ids = Set(project.inputs.filter { $0.id == id || $0.joinedTo == input.legacyIndex }.map(\.legacyIndex))
    project.inputs.removeAll { ids.contains($0.legacyIndex) }
    project.objects.removeAll { ids.contains($0.inputIndex) }
    for i in project.objects.indices {
      project.objects[i].segments = project.objects[i].segments?.map { segment in
        var segment = segment
        if let index = segment.inputIndex, ids.contains(index) { segment.visible = false; segment.inputIndex = nil }
        return segment
      }
    }
    for index in ids { telemetry.removeValue(forKey: index) }
    selectedInput = nil
  }
  func synchronize(inputIndex: Int, sourceTime: Double) {
    guard let i = project.inputs.firstIndex(where: { $0.legacyIndex == inputIndex }) else { return }
    checkpoint()
    let timing = project.inputs[i].timing ?? InputTiming()
    guard sourceTime >= timing.trimStart, sourceTime <= (timing.trimEnd ?? project.inputs[i].duration) else {
      error = "The event is outside this source's trim range. Adjust the trim first."; return
    }
    project.inputs[i].offset = sourceTime - timing.trimStart - (time-timing.projectStart)*timing.safeRate
    seek(time)
  }
  func useExportRange(_ range: ClosedRange<Double>) {
    exportStart = range.lowerBound; exportDuration = range.upperBound-range.lowerBound
  }
  func confirmDiscard() -> Bool {
    guard dirty else { return true }
    let alert = NSAlert()
    alert.messageText = "Save your project changes?"
    alert.informativeText = "You have unsaved edits in \(project.name)."
    alert.addButton(withTitle: "Save…")
    alert.addButton(withTitle: "Discard")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      save()
      return !dirty
    case .alertSecondButtonReturn: return true
    default: return false
    }
  }
  func newProject() {
    guard confirmDiscard() else { return }
    pause()
    project = RaceProject()
    telemetry = [:]
    selected = nil
    selectedInput = nil
    fileURL = nil
    dirty = false
    time = 0
    undoStack = []
    redoStack = []
    configurePlayers()
    status = "New session"
  }
  func chooseOpen() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = ["rrp", "rrt", "rro", "orrp", "orrt"].compactMap {
      UTType(filenameExtension: $0)
    }
    if panel.runModal() == .OK, let url = panel.url { open(url) }
  }
  func open(_ url: URL) {
    if ["rrt", "rro", "orrt"].contains(url.pathExtension.lowercased()), !project.inputs.isEmpty {
      importLayout(url)
      return
    }
    guard confirmDiscard() else { return }
    pause()
    busy = true
    status = "Reading \(url.lastPathComponent)…"
    Task {
      do {
        var p = try await Task.detached { try RaceProject.read(url) }.value
        let loaded = try await Self.loadTelemetry(p)
        for i in p.inputs.indices {
          if let d = loaded[p.inputs[i].legacyIndex] {
            p.inputs[i].duration = d.duration
          } else if ["video", "audio"].contains(p.inputs[i].kind), p.inputs[i].exists {
            p.inputs[i].duration =
              (try? await AVURLAsset(url: URL(fileURLWithPath: p.inputs[i].path)).load(.duration)
                .seconds) ?? p.inputs[i].duration
          }
        }
        project = p
        telemetry = loaded
        selected = p.objects.first { $0.kind != .video }?.id
        selectedInput = nil
        time = 0
        fileURL = url.pathExtension.lowercased() == "orrp" ? url : nil
        dirty = false
        undoStack = []
        redoStack = []
        configurePlayers()
        status =
          "\(p.objects.count) displays · \(p.inputs.count) inputs · \(loaded.values.reduce(0){$0+$1.count}.formatted()) telemetry samples"
      } catch {
        self.error = error.localizedDescription
        status = "Could not open project"
      }
      busy = false
    }
  }
  nonisolated static func loadTelemetry(_ p: RaceProject) async throws -> [Int: Telemetry] {
    try await Task.detached {
      var result: [Int: Telemetry] = [:]
      for input in p.inputs where input.kind == "data" && input.exists {
        let data = try Telemetry(url: URL(fileURLWithPath: input.path))
        if let settings = input.dataSettings { data.configure(settings) }
        result[input.legacyIndex] = data
      }
      return result
    }.value
  }
  func save(as saveAs: Bool = false) {
    var url = fileURL
    if saveAs || url == nil {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = project.name + ".orrp"
      panel.allowedContentTypes = [UTType(filenameExtension: "orrp") ?? .json]
      guard panel.runModal() == .OK else { return }
      url = panel.url
    }
    guard let url = url else { return }
    do {
      try project.save(url)
      fileURL = url
      dirty = false
      status = "Saved \(url.lastPathComponent)"
    } catch { self.error = error.localizedDescription }
  }
  func saveTemplate() {
    saveLayout(selectedOnly: false)
  }
  func saveSelectedStyle() {
    saveLayout(selectedOnly: true)
  }
  func saveLayout(selectedOnly: Bool) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(project.name) Layout.orrt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      var p = project
      p.legacyData = nil
      p.sourcePath = nil
      p.explicitDuration = nil; p.rangeStart = nil; p.rangeEnd = nil
      if selectedOnly { p.objects = p.objects.filter { $0.id == selected } }
      let used = Set(p.objects.flatMap { [$0.inputIndex] + ($0.segments ?? []).compactMap(\.inputIndex) })
      p.inputs = p.inputs.filter { used.contains($0.legacyIndex) }
      for i in p.inputs.indices {
        p.inputs[i].path = ""; p.inputs[i].duration = 0; p.inputs[i].offset = 0
        p.inputs[i].timing = nil; p.inputs[i].joinedTo = nil; p.inputs[i].legacyOffset = nil
      }
      for i in p.objects.indices where p.objects[i].kind == .image {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: p.objects[i].text)), NSImage(data: data) != nil {
          p.objects[i].embeddedImage = data; p.objects[i].text = ""
        }
      }
      try p.save(url)
      status = "Saved reusable layout"
    } catch { self.error = error.localizedDescription }
  }
  func exportRRP() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = project.name + "-edited.rrp"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard url.path != project.sourcePath else {
        throw RaceError.invalid("Choose a new filename to preserve your original project.")
      }
      try project.patchLegacy().write(to: url, options: .atomic)
      status = "Saved compatible RRP copy"
    } catch { self.error = error.localizedDescription }
  }
  func chooseInputs() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK { addInputs(panel.urls) }
  }
  func addInputs(_ urls: [URL]) {
    checkpoint()
    busy = true
    Task {
      for url in urls {
        if ["rrt", "rro", "orrt"].contains(url.pathExtension.lowercased()) {
          importLayout(url)
          continue
        }
        let ext = url.pathExtension.lowercased()
        let kind =
          ["csv", "tsv", "txt", "gpx", "tcx", "nmea", "log", "vbo", "fit"].contains(ext)
          ? "data"
          : (["mp3", "wav", "m4a", "aac"].contains(ext)
            ? "audio" : (["png", "jpg", "jpeg", "tif", "bmp"].contains(ext) ? "image" : "video"))
        let index = (project.inputs.map(\.legacyIndex).max() ?? -1) + 1
        var input = MediaInput(
          name: url.deletingPathExtension().lastPathComponent, path: url.path, kind: kind,
          legacyIndex: index)
        do {
          if kind == "data" {
            let d = try await Task.detached { try Telemetry(url: url) }.value
            telemetry[index] = d
            input.duration = d.duration
          } else if kind != "image" {
            input.duration = try await AVURLAsset(url: url).load(.duration).seconds
          }
          project.inputs.append(input)
          if kind == "video" {
            var o = DisplayObject(name: input.name, kind: .video)
            o.inputIndex = index
            let firstVideo = !project.objects.contains { $0.kind == .video }
            o.x = firstVideo ? 0 : 70; o.y = firstVideo ? 0 : 70
            o.width = firstVideo ? 100 : 27; o.height = firstVideo ? 100 : 27
            if firstVideo { project.objects.insert(o, at: 0) } else { project.objects.append(o) }
          }
          if kind == "audio" {
            var o = DisplayObject(name: input.name, kind: .audio); o.inputIndex = index; project.objects.append(o)
          }
          if kind == "image" {
            var o = DisplayObject(name: input.name, kind: .image)
            o.text = url.path
            o.inputIndex = index
            project.objects.append(o)
          }
        } catch { self.error = error.localizedDescription }
      }
      configurePlayers()
      busy = false
      status = "Inputs added"
    }
  }
  func relink(_ id: UUID) {
    let panel = NSOpenPanel()
    guard panel.runModal() == .OK, let url = panel.url,
      let i = project.inputs.firstIndex(where: { $0.id == id })
    else { return }
    checkpoint()
    project.inputs[i].path = url.path
    busy = true
    Task {
      do {
        telemetry = try await Self.loadTelemetry(project)
        if let d = telemetry[project.inputs[i].legacyIndex] {
          project.inputs[i].duration = d.duration
        }
        configurePlayers()
        status = "Input relinked"
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  func addObject(_ kind: ObjectKind) {
    checkpoint()
    var o = DisplayObject(name: kind.title, kind: kind)
    o.inputIndex =
      project.inputs.first { $0.kind == (kind == .video ? "video" : "data") }?.legacyIndex ?? 0
    if kind == .rpm || kind == .lights { o.maximum = 8000 }
    if kind == .speed { o.maximum = 160 }
    if [.map, .gforce, .speed, .rpm].contains(kind) {
      o.width = 18
      o.height = 32
    }
    if [.timer, .lap, .text, .throttle, .lights, .gear].contains(kind) {
      o.width = 20
      o.height = 8
    }
    project.objects.append(o)
    selected = o.id
    selectedInput = nil
  }
  func deleteSelected() {
    guard let id = selected else { return }
    checkpoint()
    project.objects.removeAll { $0.id == id }
    selected = nil
  }
  func duplicate() {
    guard var o = project.objects.first(where: { $0.id == selected }) else { return }
    checkpoint()
    o.id = UUID()
    o.name += " Copy"
    o.x += 2
    o.y += 2
    o.legacyOffset = nil
    project.objects.append(o)
    selected = o.id
  }
  func move(_ direction: Int) {
    guard let i = project.objects.firstIndex(where: { $0.id == selected }),
      project.objects.indices.contains(i + direction)
    else { return }
    checkpoint()
    project.objects.swapAt(i, i + direction)
  }
  func importLayout(_ url: URL) {
    busy = true
    Task {
      do {
        let layout = try await Task.detached { try RaceProject.read(url) }.value
        if url.pathExtension.lowercased() == "rro" { applyStyle(layout) }
        else { apply(layout, replace: false, mapping: [:]) }
        status = "Imported \(layout.objects.count) displays from \(url.lastPathComponent)"
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  func applyStyle(_ layout: RaceProject) {
    guard var style = layout.objects.first else { return }
    guard let index = project.objects.firstIndex(where: { $0.id == selected }) else {
      apply(layout, replace: false, mapping: [:]); return
    }
    checkpoint()
    let old = project.objects[index]
    let kind = style.kind == .video ? "video" : (style.kind == .audio ? "audio" : (style.kind == .image ? "image" : "data"))
    let oldSource = project.inputs.first { $0.legacyIndex == old.inputIndex }
    style.inputIndex = oldSource?.kind == kind ? old.inputIndex : project.inputs.first { $0.kind == kind && $0.joinedTo == nil }?.legacyIndex ?? -1
    style.id = old.id; style.name = old.name; style.segments = old.segments; style.legacyOffset = nil
    project.objects[index] = style
    project.warnings += layout.warnings.filter { !project.warnings.contains($0) }
  }
  func apply(_ layout: RaceProject, replace: Bool, mapping: [Int: Int]) {
    checkpoint()
    if replace {
      let includesVideo = layout.objects.contains { $0.kind == .video }
      project.objects.removeAll { includesVideo || ($0.kind != .video && $0.kind != .audio) }
    }
    for var o in layout.objects {
      func remap(_ index: Int) -> Int {
        let source = layout.inputs.first { $0.legacyIndex == index }
        return mapping[index] ?? project.inputs.first {
          $0.kind == (source?.kind ?? (o.kind == .video ? "video" : "data")) && $0.joinedTo == nil
        }?.legacyIndex ?? project.inputs.first { $0.kind == "data" }?.legacyIndex ?? -1
      }
      o.inputIndex = remap(o.inputIndex)
      o.segments = o.segments?.map { segment in
        var segment = segment
        if let index = segment.inputIndex { segment.inputIndex = remap(index) }
        return segment
      }
      o.id = UUID()
      o.legacyOffset = nil
      project.objects.append(o)
    }
    project.warnings += layout.warnings.filter { !project.warnings.contains($0) }
    selected = project.objects.last?.id
  }
  func snapshot() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = project.name + "-frame.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scene = scene
    let t = time
    busy = true
    Task {
      do {
        try await Task.detached { try VideoExporter.snapshot(scene: scene, time: t, to: url) }.value
        status = "Snapshot saved"
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  func exportVideo() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = project.name + "-render.mp4"
    panel.allowedContentTypes = [.mpeg4Movie]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if FileManager.default.fileExists(atPath: url.path) {
      error = "Choose a new filename; export does not overwrite existing files."
      return
    }
    pause()
    showExport = false
    let exporter = VideoExporter()
    self.exporter = exporter
    exportProgress = 0
    let scene = scene
    let start = exportStart
    let duration = exportDuration
    let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) {
      [weak self] _ in Task { @MainActor in self?.exportProgress = exporter.progress }
    }
    Task {
      do {
        try await exporter.export(scene: scene, to: url, start: start, duration: duration)
        status = "Export complete · \(url.lastPathComponent)"
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } catch { self.error = error.localizedDescription }
      progressTimer.invalidate()
      exportProgress = nil
      self.exporter = nil
    }
  }
}
