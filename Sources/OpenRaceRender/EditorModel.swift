import AVFoundation
import ImageIO
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class EditorModel: ObservableObject {
  @Published var project = RaceProject() { didSet {
    guard oldValue != project else { return }
    dirty = true
    if oldValue.inputs != project.inputs || oldValue.objects != project.objects || oldValue.width != project.width || oldValue.height != project.height || oldValue.fps != project.fps || oldValue.speedUnit != project.speedUnit || oldValue.explicitDuration != project.explicitDuration { schedulePreview() }
    let oldData = oldValue.inputs.filter { $0.kind == "data" }
    let newData = project.inputs.filter { $0.kind == "data" }
    if oldData.map(\.path) != newData.map(\.path) || oldData.map(\.legacyIndex) != newData.map(\.legacyIndex) || oldData.map(\.dataSettings) != newData.map(\.dataSettings) { scheduleTelemetry() }
  } }
  @Published var telemetry: [Int: Telemetry] = [:]
  @Published var selected: UUID? { didSet { if oldValue != selected { editingSegment = nil } } }
  @Published var editingSegment: Double?
  @Published var previewPlayer: AVPlayer?
  weak var canvasView: PreviewView?
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
  @Published var showWidgets = false { didSet { if oldValue != showWidgets { schedulePreview() } } }
  @Published var showWidgetStyles = false
  @Published var widgetLibraryRevision = 0
  @Published var lockWidgetAspect = true
  let widgetCatalog = WidgetCatalog()
  @Published var showSaveTemplate = false
  @Published var templateSelectedOnly = false
  @Published var templateIncludesVideo = false
  @Published var templateName = ""
  @Published var exportProgress: Float?
  @Published var exportStart: Double = 0
  @Published var exportDuration: Double = 0
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
  private var pendingInputs: [URL] = []
  private var importingInputs = false
  private var documentRevision = UUID()
  private(set) var openTask: Task<Void, Never>?
  private var openingURL: URL?
  var missingInputs: [MediaInput] { project.inputs.filter { !$0.path.isEmpty && !$0.exists } }
  func reviewMissingInput() {
    guard let input = missingInputs.first else { return }
    selected = nil; selectedInput = input.id
  }
  var scene: RenderScene { RenderScene(project: project, telemetry: telemetry) }
  var usesDesignSamples: Bool { showWidgets && project.objects.contains { ![.video, .audio, .image, .shape, .text, .group].contains($0.kind) } && telemetry.isEmpty && !project.inputs.contains { $0.kind == "data" && !$0.path.isEmpty } }
  var designScene: RenderScene { usesDesignSamples ? WidgetDesign.scene(project) : scene }
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
  func projectBinding<Value: Equatable>(_ keyPath: WritableKeyPath<RaceProject, Value>) -> Binding<Value> {
    Binding(get: { self.project[keyPath: keyPath] }, set: {
      guard self.project[keyPath: keyPath] != $0 else { return }
      self.checkpoint(); self.project[keyPath: keyPath] = $0
    })
  }
  func prepareExport() {
    guard exportProgress == nil else { status = "An export is already running"; return }
    guard project.inputs.contains(where: { $0.kind == "video" && !$0.path.isEmpty }) else {
      error = "Add or link a video file before exporting. Templates can be saved without media."; return
    }
    let range = project.defaultExportRange
    useExportRange(range)
    showExport = true
  }
  func markStart() { checkpoint(); project.markExportStart(at: time); status = "Export starts at " + clockText(time) }
  func markEnd() { checkpoint(); project.markExportEnd(at: time); status = "Export ends at " + clockText(time) }
  func clearMarks() {
    checkpoint(); project.rangeStart = nil; project.rangeEnd = nil
    if project.lastExport != nil { project.lastExport?.start = 0; project.lastExport?.duration = project.duration }
  }
  func blankLayout() {
    checkpoint()
    project.objects.removeAll { ![.video, .audio].contains($0.kind) }
    selected = nil; selectedInput = nil; showWidgets = true
    status = "Blank layout · drag widgets into the preview"
  }
  func objectBinding(_ id: UUID) -> Binding<DisplayObject> {
    Binding(
      get: {
        let object = self.project.objects.first { $0.id == id } ?? DisplayObject(name: "", kind: .text)
        return self.editingSegment.map { object.resolved(at: $0) } ?? object
      },
      set: { value in
        guard let i = self.project.objects.firstIndex(where: { $0.id == id }) else { return }
        guard self.objectBinding(id).wrappedValue != value else { return }
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
        guard self.project.inputs[i] != value else { return }
        self.checkpoint()
        self.project.inputs[i] = value
        self.seek(self.time)
      })
  }
  func nudgeOffset(_ id: UUID, frames: Int) {
    guard frames != 0, project.fps.isFinite, project.fps > 0,
      project.inputs.contains(where: { $0.id == id }) else { return }
    let binding = inputBinding(id)
    var input = binding.wrappedValue
    // Offsets are source seconds; one project frame spans rate/fps seconds.
    input.offset += Double(frames) * (input.timing?.safeRate ?? 1) / project.fps
    binding.wrappedValue = input
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
    guard t.isFinite else { return }
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
        let scene = self.designScene
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
    do {
      var updated = project
      try updated.synchronize(inputIndex: inputIndex, sourceTime: sourceTime, projectTime: time)
      checkpoint(); project = updated; seek(time)
      status = "Synchronized · source " + clockText(sourceTime) + " at video " + clockText(time)
    } catch { self.error = error.localizedDescription }
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
    documentRevision = UUID()
    openTask?.cancel(); openingURL = nil; busy = false
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
    // Finder can resend a request while a large project is loading. Coalesce it.
    guard openingURL != url.standardizedFileURL else { return }
    if ["rrt", "rro", "orrt"].contains(url.pathExtension.lowercased()), !project.inputs.isEmpty {
      importLayout(url)
      return
    }
    guard confirmDiscard() else { return }
    let revision = UUID()
    documentRevision = revision
    openTask?.cancel()
    openingURL = url.standardizedFileURL
    pause()
    busy = true
    status = "Reading \(url.lastPathComponent)…"
    openTask = Task {
      defer {
        if documentRevision == revision { busy = false; openingURL = nil }
      }
      do {
        var p = try await Task.detached { try RaceProject.read(url) }.value
        try Task.checkCancellation()
        let loaded = try await Self.loadTelemetry(p)
        for i in p.inputs.indices {
          if let d = loaded[p.inputs[i].legacyIndex] {
            p.inputs[i].duration = d.duration
            p.warnings += d.warnings.filter { !p.warnings.contains($0) }
          } else if ["video", "audio"].contains(p.inputs[i].kind), p.inputs[i].exists {
            p.inputs[i].duration =
              (try? await AVURLAsset(url: URL(fileURLWithPath: p.inputs[i].path)).load(.duration)
                .seconds) ?? p.inputs[i].duration
          }
        }
        try Task.checkCancellation()
        guard documentRevision == revision else { return }
        project = p
        telemetry = loaded
        selected = p.objects.first { $0.kind != .video }?.id
        selectedInput = nil
        if let missing = p.inputs.first(where: { !$0.path.isEmpty && !$0.exists }) {
          selected = nil; selectedInput = missing.id
        }
        time = 0
        fileURL = url.pathExtension.lowercased() == "orrp" ? url : nil
        dirty = false
        undoStack = []
        redoStack = []
        configurePlayers()
        status =
          "\(p.objects.count) displays · \(p.inputs.count) inputs · \(loaded.values.reduce(0){$0+$1.count}.formatted()) telemetry samples"
      } catch is CancellationError {
      } catch {
        guard documentRevision == revision else { return }
        self.error = error.localizedDescription
        status = "Could not open project"
      }
    }
  }
  nonisolated static func loadTelemetry(_ p: RaceProject) async throws -> [Int: Telemetry] {
    try await Task.detached {
      var result: [Int: Telemetry] = [:]
      for input in p.inputs where input.kind == "data" && input.exists {
        let data = try Telemetry(url: URL(fileURLWithPath: input.path), settings: input.dataSettings)
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
      panel.allowedContentTypes = [UTType(exportedAs: "org.openracerender.project", conformingTo: .json)]
      panel.nameFieldStringValue = project.name
      panel.isExtensionHidden = false
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
    templateSelectedOnly = false; templateIncludesVideo = false
    templateName = project.name + " Layout"; showSaveTemplate = true
  }
  func saveSelectedStyle() {
    guard let object = project.objects.first(where: { $0.id == selected }) else { return }
    templateSelectedOnly = true; templateIncludesVideo = true
    templateName = object.name; showSaveTemplate = true
  }
  func saveLayout() {
    do {
      var source = project
      if !templateIncludesVideo && !templateSelectedOnly { source.objects.removeAll { [.video, .audio].contains($0.kind) } }
      var layout = try source.reusableLayout(selected: templateSelectedOnly ? selected : nil)
      layout.name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
      if layout.name.isEmpty { layout.name = "Custom Layout" }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [UTType(exportedAs: "org.openracerender.template", conformingTo: .json)]
      panel.nameFieldStringValue = layout.name
      panel.isExtensionHidden = false
      let category = templateSelectedOnly ? "Styles" : "Templates"
      let folder = LayoutLibrary.userRoot().appendingPathComponent(category)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      panel.directoryURL = folder
      guard panel.runModal() == .OK, let url = panel.url else { return }
      try layout.save(url)
      widgetLibraryRevision += 1
      showSaveTemplate = false
      status = "Saved reusable " + (templateSelectedOnly ? "style" : "template") + " · " + url.lastPathComponent
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
    pendingInputs.append(contentsOf: urls)
    guard !importingInputs else { return }
    checkpoint()
    importingInputs = true; busy = true
    Task {
      while !pendingInputs.isEmpty {
        let url = pendingInputs.removeFirst()
        if ["rrt", "rro", "orrt"].contains(url.pathExtension.lowercased()) {
          do {
            let layout = try await Task.detached { try RaceProject.read(url) }.value
            if url.pathExtension.lowercased() == "rro" { applyStyle(layout) }
            else { apply(layout, replace: false, mapping: [:]) }
          } catch { self.error = error.localizedDescription }
          continue
        }
        let ext = url.pathExtension.lowercased()
        let kind =
          Telemetry.supportedExtensions.contains(ext)
          ? "data"
          : (["mp3", "wav", "m4a", "aac"].contains(ext)
            ? "audio" : (["png", "jpg", "jpeg", "tif", "bmp"].contains(ext) ? "image" : "video"))
        let placeholder = project.inputs.firstIndex { $0.kind == kind && $0.path.isEmpty && $0.joinedTo == nil }
        let index = placeholder.map { project.inputs[$0].legacyIndex } ?? ((project.inputs.map(\.legacyIndex).max() ?? -1) + 1)
        var input = MediaInput(
          name: url.deletingPathExtension().lastPathComponent, path: url.path, kind: kind,
          legacyIndex: index)
        do {
          if kind == "data" {
            let d = try await Task.detached { try Telemetry(url: url) }.value
            telemetry[index] = d
            input.duration = d.duration
            project.warnings += d.warnings.filter { !project.warnings.contains($0) }
          } else if kind != "image" {
            input.duration = try await AVURLAsset(url: url).load(.duration).seconds
          }
          if let placeholder { input.id = project.inputs[placeholder].id; project.inputs[placeholder] = input }
          else { project.inputs.append(input) }
          if kind == "data" && project.inputs.filter({ $0.kind == "data" }).count == 1 {
            for i in project.objects.indices where project.objects[i].inputIndex < 0 && ![.video, .audio, .image, .group].contains(project.objects[i].kind) {
              project.objects[i].inputIndex = index
            }
          }
          if kind == "video" && !project.objects.contains(where: { $0.kind == .video && $0.inputIndex == index }) {
            var o = DisplayObject(name: input.name, kind: .video)
            o.inputIndex = index
            let firstVideo = !project.objects.contains { $0.kind == .video }
            o.x = firstVideo ? 0 : 70; o.y = firstVideo ? 0 : 70
            o.width = firstVideo ? 100 : 27; o.height = firstVideo ? 100 : 27
            if firstVideo { project.objects.insert(o, at: 0) } else { project.objects.append(o) }
          }
          if kind == "audio" && !project.objects.contains(where: { $0.kind == .audio && $0.inputIndex == index }) {
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
      importingInputs = false; busy = false
      status = "Inputs added"
    }
  }
  func relink(_ id: UUID) {
    guard let input = project.inputs.first(where: { $0.id == id }) else { return }
    let panel = NSOpenPanel()
    panel.message = "Choose a replacement \(input.kind) file for \(input.name). Timing, picture and display settings are retained."
    switch input.kind {
    case "video": panel.allowedContentTypes = [.movie]
    case "audio": panel.allowedContentTypes = [.audio, .movie]
    case "image": panel.allowedContentTypes = [.image]
    default: panel.allowedContentTypes = Telemetry.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await relink(id, to: url) }
  }
  /// Validate first, then commit one undoable change. A failed or stale request never edits the document.
  @discardableResult func relink(_ id: UUID, to url: URL) async -> Bool {
    guard !busy, let original = project.inputs.first(where: { $0.id == id }) else { return false }
    let revision = documentRevision
    busy = true
    defer { busy = false }
    do {
      var replacement = original
      replacement.path = url.path
      guard replacement.exists else { throw RaceError.invalid("Choose an existing \(original.kind) file.") }
      var data: Telemetry?
      switch original.kind {
      case "data":
        data = try await Task.detached { try Telemetry(url: url, settings: original.dataSettings) }.value
        if let settings = original.dataSettings { data?.configure(settings) }
        replacement.duration = data!.duration
      case "video", "audio":
        let asset = AVURLAsset(url: url)
        let mediaType: AVMediaType = original.kind == "video" ? .video : .audio
        guard !(try await asset.loadTracks(withMediaType: mediaType)).isEmpty else {
          throw RaceError.invalid("The replacement has no \(original.kind) track.")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RaceError.invalid("The replacement has no playable duration.") }
        replacement.duration = duration
      case "image":
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
          throw RaceError.invalid("The replacement is not a readable image.")
        }
      default: throw RaceError.invalid("Unsupported input type: \(original.kind).")
      }
      guard documentRevision == revision,
        let i = project.inputs.firstIndex(where: { $0.id == id }), project.inputs[i] == original else { return false }
      checkpoint()
      project.inputs[i] = replacement
      if let data {
        telemetry[replacement.legacyIndex] = data
        project.warnings += data.warnings.filter { !project.warnings.contains($0) }
      }
      if original.kind == "image" {
        for j in project.objects.indices where project.objects[j].kind == .image && project.objects[j].inputIndex == original.legacyIndex && project.objects[j].text == original.path {
          project.objects[j].text = url.path
        }
      }
      configurePlayers()
      status = "Relinked \(original.name) · \(clockText(replacement.duration))"
      return true
    } catch {
      if documentRevision == revision { self.error = "Could not relink \(original.name). The previous source is unchanged.\n\n" + error.localizedDescription }
      return false
    }
  }
  func addObject(_ kind: ObjectKind, at point: CGPoint? = nil) {
    checkpoint()
    var o = DisplayObject(name: kind.title, kind: kind)
    o.inputIndex =
      project.inputs.first { $0.kind == (kind == .video ? "video" : "data") }?.legacyIndex ?? -1
    if kind == .rpm || kind == .lights { o.maximum = 8000 }
    if kind == .speed { o.maximum = 160 }
    if [.map, .gforce, .speed, .rpm, .gauge].contains(kind) {
      o.width = 18
      o.height = 32
    }
    if [.timer, .lap, .text, .throttle, .lights, .gear].contains(kind) {
      o.width = 20
      o.height = 8
    }
    if kind == .text { o.text = "Your text"; o.typography = TextSettings() }
    if kind == .shape { o.shape = ShapeSettings() }
    if kind == .gauge { var g = GaugeSettings(); g.design = GaugeDesign(); o.gauge = g }
    if let point { o = o.placed(at: point) }
    project.objects.append(o)
    selected = o.id
    selectedInput = nil
  }
  func addWidget(_ style: WidgetStyle, at point: CGPoint? = nil) {
    checkpoint()
    var o = style.object
    o.id = UUID(); o.legacyOffset = nil; o.legacyIndex = nil; o.parentIndex = -1
    o.start = 0; o.end = 1_000_000; o.segments = nil; o.visible = true
    o.inputIndex = project.inputs.first { $0.kind == (o.kind == .image ? "image" : "data") && $0.joinedTo == nil }?.legacyIndex ?? -1
    if let point { o = o.placed(at: point) }
    project.objects.append(o); selected = o.id; selectedInput = nil
    status = "Added " + style.name
  }
  func alignWidget(_ alignment: String) {
    guard let id = selected else { return }
    let binding = objectBinding(id)
    var o = binding.wrappedValue
    switch alignment {
    case "Left": o.x = 0
    case "Right": o.x = 100-o.width
    case "Top": o.y = 100-o.height
    case "Bottom": o.y = 0
    case "Horizontal center": o.x = (100-o.width)/2
    case "Vertical center": o.y = (100-o.height)/2
    default: return
    }
    binding.wrappedValue = o
  }
  func nudgeWidget(x: Double, y: Double) {
    guard let id = selected else { return }
    let binding = objectBinding(id)
    var o = binding.wrappedValue
    o.x += x / Double(project.width) * 100; o.y += y / Double(project.height) * 100
    binding.wrappedValue = o
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
  func applyStyle(_ layout: RaceProject, preservePlacement: Bool = true) {
    guard let style = layout.objects.first else { return }
    guard let index = project.objects.firstIndex(where: { $0.id == selected }) else {
      apply(layout, replace: false, mapping: [:]); return
    }
    let old = project.objects[index]
    guard style.kind == old.kind else {
      error = "Choose a \(old.kind.title) style for this widget. Add a different widget from the palette instead."; return
    }
    checkpoint()
    project.objects[index] = old.applyingStyle(style)
    if !preservePlacement {
      project.objects[index].x = style.x; project.objects[index].y = style.y
      project.objects[index].width = style.width; project.objects[index].height = style.height
      project.objects[index].picture = style.picture
    }
    status = "Applied " + (style.style.isEmpty ? style.name : style.style)
    project.warnings += layout.warnings.filter { !project.warnings.contains($0) }
  }
  func apply(_ layout: RaceProject, replace: Bool, mapping: [Int: Int]) {
    checkpoint()
    project.applyLayout(layout, replace: replace, mapping: mapping)
    selected = project.objects.last?.id; selectedInput = nil
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
  func availableOutputURL(_ url: URL) -> URL {
    guard FileManager.default.fileExists(atPath: url.path) else { return url }
    var number = 2
    while true {
      let next = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(number).mp4")
      if !FileManager.default.fileExists(atPath: next.path) { return next }
      number += 1
    }
  }
  var exportRangeError: String? {
    do {
      try project.validateExportRange(start: exportStart, duration: exportDuration)
      try project.validateExportAssets(start: exportStart, duration: exportDuration)
      return nil
    }
    catch { return error.localizedDescription }
  }
  func exportVideo() {
    if let message = exportRangeError { error = message; return }
    let panel = NSSavePanel()
    if let path = project.lastExport?.path {
      let previous = URL(fileURLWithPath: path)
      panel.directoryURL = previous.deletingLastPathComponent()
      panel.nameFieldStringValue = availableOutputURL(previous).lastPathComponent
    } else { panel.nameFieldStringValue = project.name + "-render.mp4" }
    panel.allowedContentTypes = [.mpeg4Movie]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if FileManager.default.fileExists(atPath: url.path) {
      error = "Choose a new filename; export does not overwrite existing files."
      return
    }
    project.lastExport = ExportDestination(path: url.path, start: exportStart, duration: exportDuration)
    if let fileURL {
      do { try project.save(fileURL); dirty = false }
      catch { self.error = error.localizedDescription; return }
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
