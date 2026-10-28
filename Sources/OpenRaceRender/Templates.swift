import RaceCore
import Compression
import SwiftUI

struct TemplateBrowser: View {
  @ObservedObject var model: EditorModel
  var preferredDataIndex: Int?
  @Environment(\.dismiss) var dismiss
  @State var files: [LayoutLibrary.Entry] = []
  @State var search = ""
  @State var category = LayoutLibrary.Category.templates
  @State var selected: URL?
  @State var layout: RaceProject?
  @State var loading = false
  @State var failure: String?
  @State var replace = true
  @State var mapping: [Int: Int] = [:]
  @State var thumbnails: [URL: NSImage] = [:]
  @State var scanning = false
  @State var importing = false
  @State var importMessage: String?
  @State var scanTask: Task<Void, Never>?
  var isStyle: Bool { category != .templates || selected?.pathExtension.lowercased() == "rro" }
  var filtered: [LayoutLibrary.Entry] {
    files.filter { $0.category == category }.filter {
      search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text("Layout library").font(.system(size: 23, weight: .semibold))
          Text("Use your RaceRender templates or start with an original layout.").font(
            .system(size: 12)
          ).foregroundStyle(muted)
        }
        Spacer()
        Button("Import library…", action: importLibrary).disabled(importing)
        Button("Choose folder…", action: chooseFolder)
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain)
      }.padding(24)
      Divider()
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          Picker("Library", selection: $category) {
            ForEach(LayoutLibrary.Category.allCases, id: \.self) { category in
              Text(category.rawValue).tag(category)
            }
          }.pickerStyle(.segmented)
            .onChange(of: category) { _, _ in selected = nil; layout = nil; failure = nil }
          TextField("Search library", text: $search)
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 14) {
              if category == .templates {
                ForEach(["Blank", "Apex GT", "Apex GT Road", "Apex Telemetry", "Apex Road", "Circuit", "Minimal", "Broadcast"], id: \.self) { name in
                  Button {
                    selected = nil
                    layout = builtin(name)
                    mapping = [:]
                    failure = nil
                  } label: {
                    VStack(alignment: .leading, spacing: 8) {
                      ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(bg)
                        Image(
                          systemName: name == "Circuit"
                            ? "gauge.with.dots.needle.67percent"
                            : (name == "Minimal" ? "speedometer" : "rectangle.3.group")
                        ).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(mint)
                      }.frame(height: 96)
                      Text(name).font(.system(size: 11, weight: .semibold))
                      Text("OPENRACERENDER").font(.system(size: 8)).tracking(1).foregroundStyle(
                        muted)
                    }.padding(9).background(panelColor).clipShape(RoundedRectangle(cornerRadius: 7))
                  }.buttonStyle(.plain)
                }
              }
              ForEach(filtered) { entry in
                let url = entry.url
                Button {
                  load(url)
                } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    if let thumbnail = thumbnails[url] {
                      Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).frame(
                        height: 96
                      ).clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                      Rectangle().fill(bg).frame(height: 96)
                    }
                    Text(displayName(url)).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                      .frame(height: 28, alignment: .topLeading)
                    Text(url.pathExtension.uppercased()).font(.system(size: 8)).foregroundStyle(
                      muted)
                  }.padding(9).background(selected == url ? mint.opacity(0.1) : panelColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7)).overlay {
                      RoundedRectangle(cornerRadius: 7).stroke(
                        selected == url ? mint : .clear, lineWidth: 1)
                    }
                }.buttonStyle(.plain).task(id: url) {
                  if thumbnails[url] == nil {
                    let image = await Task.detached(priority: .utility) { Self.thumbnail(url) }.value
                    if let image { thumbnails[url] = image }
                  }
                }
              }
            }.padding(.vertical, 4)
          }
          Text(importMessage ?? "\(filtered.count) library files" + (importing ? " · importing…" : scanning ? " · scanning…" : "")).font(
            .system(size: 10)
          ).foregroundStyle(muted)
        }.padding(20).frame(width: 550)
        Divider()
        VStack(alignment: .leading, spacing: 16) {
          if loading {
            ProgressView("Reading layout…")
          } else if let p = layout {
            Text(p.name).font(.system(size: 18, weight: .semibold))
            Text("\(p.objects.count) display objects").foregroundStyle(mint).font(.system(size: 12))
            Divider()
            ForEach(p.inputs) { input in
              Picker(
                input.name,
                selection: Binding(
                  get: {
                    mapping[input.legacyIndex] ?? defaultInput(for:input)
                  }, set: { mapping[input.legacyIndex] = $0 })
              ) {
                Text("None").tag(-1)
                ForEach(model.project.inputs.filter { $0.kind == input.kind && $0.joinedTo == nil }) { Text($0.name).tag($0.legacyIndex) }
              }
            }
            if isStyle {
              Text(model.selected == nil ? "Adds a display to this project." : "Applies this style to the selected display. Existing timeline segments are retained.").font(.system(size: 11)).foregroundStyle(muted)
            } else {
              Toggle("Replace current layout", isOn: $replace).font(.system(size: 12))
            }
            ScrollView {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(p.objects) { o in
                  Label(o.name, systemImage: o.kind.symbol).font(.system(size: 11)).foregroundStyle(
                    muted)
                }
              }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !p.warnings.isEmpty {
              Text(p.warnings.first ?? "").font(.system(size: 10)).foregroundStyle(muted).lineLimit(
                4)
            }
          } else {
            Image(systemName: "square.grid.2x2").font(.system(size: 32, weight: .ultraLight))
              .foregroundStyle(mint)
            Text("Select a layout").font(.system(size: 17))
            Text(
              "Import saved geometry, style settings, drawing scripts and embedded artwork from your local library. Unsupported effects use a native fallback."
            ).font(.system(size: 12)).foregroundStyle(muted)
          }
          if let failure = failure {
            Text(failure).font(.system(size: 11)).foregroundStyle(.orange)
          }
          Spacer()
          Button("Import another file…") {
            let p = NSOpenPanel()
            p.directoryURL = LayoutLibrary.userRoot()
            if p.runModal() == .OK, let url = p.url { load(url) }
          }
        }.padding(22).frame(width: 290)
      }
      Divider()
      HStack {
        Button("Open library folder", action: openLibraryFolder).font(.system(size: 10))
        Spacer()
        Button("Cancel") { dismiss() }
        Button(isStyle ? "Apply style" : "Apply layout") {
          if let p = layout {
            if isStyle { model.applyStyle(p, preservePlacement: category != .videoPositions) }
            else if p.name == "Blank" && p.objects.isEmpty { model.blankLayout() }
            else { model.apply(p, replace: replace, mapping: resolvedMapping(p)) }
            dismiss()
          }
        }.buttonStyle(.borderedProminent).foregroundStyle(bg).disabled(layout == nil || loading)
      }.padding(20)
    }.frame(width: 840, height: 630).background(bg).preferredColorScheme(.dark).tint(mint)
      .onAppear {
        scan(LayoutLibrary.defaultRoots())
      }.onDisappear { scanTask?.cancel() }
  }
  func displayName(_ u: URL) -> String {
    u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Data - ", with: "")
      .replacingOccurrences(of: "Project - ", with: "").replacingOccurrences(of: "_", with: "")
  }
  func defaultInput(for input:MediaInput) -> Int {
    if input.kind == "data", let preferredDataIndex,
      model.project.inputs.contains(where:{$0.legacyIndex == preferredDataIndex && $0.kind == "data" && $0.joinedTo == nil}) { return preferredDataIndex }
    return model.project.inputs.first(where:{$0.kind == input.kind && $0.joinedTo == nil})?.legacyIndex ?? -1
  }
  func resolvedMapping(_ layout:RaceProject) -> [Int:Int] {
    Dictionary(uniqueKeysWithValues:layout.inputs.map { ($0.legacyIndex,mapping[$0.legacyIndex] ?? defaultInput(for:$0)) })
  }
  func chooseFolder() {
    let p = NSOpenPanel()
    p.directoryURL = LayoutLibrary.userRoot()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    if p.runModal() == .OK, let url = p.url { scan(url) }
  }
  func importLibrary() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    panel.message = "Copy templates, styles and artwork into your OpenRaceRender library. Existing customizations and source files are preserved."
    guard panel.runModal() == .OK, let source = panel.url else { return }
    importing = true; importMessage = nil; failure = nil
    Task {
      do {
        let result = try await Task.detached(priority: .utility) { try LayoutLibrary.importLibrary(from: source) }.value
        importMessage = "Imported \(result.imported) files · kept \(result.keptExisting) existing files"
        scan(LayoutLibrary.defaultRoots())
      } catch { failure = error.localizedDescription }
      importing = false
    }
  }
  func openLibraryFolder() {
    let folder = LayoutLibrary.userRoot()
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      NSWorkspace.shared.open(folder)
    } catch { failure = error.localizedDescription }
  }
  func scan(_ root: URL) {
    scan([root])
  }
  func scan(_ roots: [URL]) {
    scanTask?.cancel(); files = []; scanning = true
    scanTask = Task {
      var seen = Set<String>()
      for root in roots {
        let entries = await Task.detached(priority: .utility) { LayoutLibrary.entries(in: [root]) }.value
        guard !Task.isCancelled else { return }
        for entry in entries {
          let key = (entry.category.rawValue + "/" + entry.relativePath).lowercased()
          if seen.insert(key).inserted { files.append(entry) }
        }
      }
      scanning = false
    }
  }
  func load(_ url: URL) {
    selected = url
    loading = true
    layout = nil
    failure = nil
    Task {
      do {
        let p = try await Task.detached { try RaceProject.read(url) }.value
        if selected == url {
          layout = p
          mapping = [:]
        }
      } catch { failure = error.localizedDescription }
      loading = false
    }
  }
  nonisolated static func thumbnail(_ url: URL) -> NSImage? {
    if url.pathExtension.lowercased() == "orrt", let p = try? RaceProject.read(url),
      let c = CGContext(data: nil, width: 180, height: 101, bitsPerComponent: 8, bytesPerRow: 0,
        space: OverlayRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
      OverlayRenderer.draw(c, scene: RenderScene(project: p, telemetry: [:]), time: 0, size: CGSize(width: 180, height: 101))
      if let image = c.makeImage() { return NSImage(cgImage: image, size: NSSize(width: 180, height: 101)) }
    }
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    guard var bytes = try? h.read(upToCount: 65536), bytes.count >= 20 else { return nil }
    let magic = String(data: bytes.prefix(4), encoding: .ascii) ?? ""
    let w = magic.hasPrefix("rro") ? 120 : 180
    let hgt = 120
    func u32(_ position: Int) -> UInt32 {
      guard position+4 <= bytes.count else { return 0 }
      return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[position+$1]) << ($1*8) }
    }
    var start = magic.hasPrefix("rro") ? 16 : (u32(64817) == 136 ? 13 : 12)
    if magic == "rro3" {
      let length = Int(u32(16) & 0x7fff_ffff)
      guard length > 0, 20+length <= bytes.count else { return nil }
      let packed = Data(bytes[20..<20+length])
      var output = [UInt8](repeating: 0, count: w*hgt*3)
      let count = output.withUnsafeMutableBufferPointer { destination in
        packed.withUnsafeBytes { source in
          compression_decode_buffer(destination.baseAddress!, destination.count, source.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
        }
      }
      guard count == output.count else { return nil }
      bytes = Data(output); start = 0
    }
    guard ["rrt1", "rrt2", "rro1", "rro2", "rro3"].contains(magic), bytes.count >= start + w * hgt * 3
    else { return nil }
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: hgt, bitsPerSample: 8, samplesPerPixel: 3,
        hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 3,
        bitsPerPixel: 24), let dest = rep.bitmapData
    else { return nil }
    for y in 0..<hgt {
      for x in 0..<w {
        let s = start + ((hgt - y - 1) * w + x) * 3
        let d = (y * w + x) * 3
        dest[d] = bytes[s + 2]
        dest[d + 1] = bytes[s + 1]
        dest[d + 2] = bytes[s]
      }
    }
    let image = NSImage(size: NSSize(width: w, height: hgt))
    image.addRepresentation(rep)
    return image
  }
  func builtin(_ name: String) -> RaceProject {
    if name == "Apex Telemetry" { return ApexTemplate.make() }
    if name == "Apex Road" { return ApexTemplate.make(road: true) }
    if name == "Apex GT" { return ApexTemplate.make(gt: true) }
    if name == "Apex GT Road" { return ApexTemplate.make(road: true, gt: true) }
    var p = RaceProject()
    p.name = name
    p.inputs = [MediaInput(name: "Telemetry", path: "", kind: "data", legacyIndex: 0)]
    func add(_ kind: ObjectKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
      var o = DisplayObject(name: kind.title, kind: kind)
      o.x = x
      o.y = y
      o.width = w
      o.height = h
      o.maximum = kind == .rpm || kind == .lights ? 8000 : (kind == .speed ? 160 : 100)
      p.objects.append(o)
    }
    if name == "Blank" { p.inputs = []; return p }
    if name == "Minimal" {
      add(.speed, 3, 3, 13, 23)
      add(.timer, 78, 4, 19, 7)
      add(.map, 80, 72, 18, 25)
    } else if name == "Broadcast" {
      add(.speed, 3, -12, 22, 39)
      add(.rpm, 21, -12, 22, 39)
      add(.gear, 44, 3, 6, 8)
      add(.throttle, 52, 3, 20, 5)
      add(.timer, 75, 3, 22, 8)
      add(.map, 78, 68, 20, 30)
      add(.lap, 3, 85, 10, 10)
    } else {
      add(.speed, 2, 3, 17, 30)
      add(.rpm, 20, 3, 17, 30)
      add(.gear, 38, 4, 6, 8)
      add(.lights, 35, 16, 18, 4)
      add(.throttle, 46, 4, 24, 5)
      add(.timer, 74, 4, 23, 8)
      add(.map, 78, 68, 20, 30)
      add(.gforce, 3, 70, 15, 26)
    }
    return p
  }
}

struct ExportSheet: View {
  @ObservedObject var model: EditorModel
  @Environment(\.dismiss) var dismiss
  @State var firstLap = -1
  @State var lastLap = -1
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Export telemetry video").font(.system(size:24,weight:.semibold))
      Text("H.264 MP4 · AAC · independent output configuration").font(.caption).foregroundStyle(muted)
      if !model.project.inputs.contains(where:{$0.kind == "video" && $0.isTimeFiller != true}) {
        Text("Camera-free video: graphics and audio render over black. Use a full-canvas image or shape for a background.").font(.caption).foregroundStyle(muted)
      }
      Divider()
      ScrollView {
        VStack(alignment:.leading,spacing:18) {
          OutputProfileControls(model:model)
          Divider()
          OutputGeometryControls(model:model)
          Divider()
          OutputEncodingControls(model:model)
          Divider()
      HStack {
        VStack(alignment: .leading) {
          Text("Start (seconds)")
          TextField("Start", value: $model.exportStart, format: .number)
        }
        VStack(alignment: .leading) {
          Text("Duration (seconds)")
          TextField("Duration", value: $model.exportDuration, format: .number)
        }
      }.textFieldStyle(.roundedBorder)
      HStack {
        Button("Marked range") { model.useExportRange(model.project.defaultExportRange) }
          .disabled(model.project.rangeStart == nil && model.project.rangeEnd == nil)
        Button("Entire project") {
          model.exportStart = 0
          model.exportDuration = model.project.duration
        }
        Button("Current lap") {
          if let l = model.activeData?.lap(at: model.dataTime) {
            if let index = model.dataIndex, let range = model.project.lapRange([l], inputIndex: index, first: l.number, last: l.number) { model.useExportRange(range) }
          }
        }
      }
      if let data = model.activeData, !data.laps.isEmpty {
        HStack {
          Picker("First lap", selection: $firstLap) { Text("Select").tag(-1); ForEach(data.laps) { Text("Lap \($0.number)").tag($0.number) } }
          Picker("Last lap", selection: $lastLap) { Text("Select").tag(-1); ForEach(data.laps) { Text("Lap \($0.number)").tag($0.number) } }
          Button("Use laps") {
            if let index = model.dataIndex, let range = model.project.lapRange(data.laps, inputIndex: index, first: firstLap, last: lastLap) { model.useExportRange(range) }
          }.disabled(firstLap < 0 || lastLap < firstLap)
        }
      }
      if let message = model.exportRangeError {
        Text(message).font(.caption).foregroundStyle(.orange)
        if !model.missingInputs.isEmpty {
          Button("Relink missing files…") { model.showExport = false; model.reviewMissingInput() }
        }
      }
      else { Text("End: " + clockText(model.exportStart + model.exportDuration)).font(.caption).foregroundStyle(mint) }
      if let path = model.project.lastExport?.path {
        Text("Previous output: " + URL(fileURLWithPath: path).lastPathComponent + ". A new filename is suggested for repeat exports.").font(.caption).foregroundStyle(muted)
      }
      Toggle("Include 360° spherical metadata",isOn:Binding(get:{model.project.exportSettings?.sphericalMetadata ?? (model.project.sphericalWorkspace == true)},set:{value in
        var settings = model.project.exportSettings ?? ExportSettings();settings.sphericalMetadata = value
        model.projectBinding(\.exportSettings).wrappedValue = settings
      }))
      Toggle("Review a YouTube upload after rendering",isOn:$model.reviewYouTubeAfterExport)
      Text("Export settings and output location are saved with the project when rendering begins. The editing canvas and preview preferences stay independent.").font(.caption).foregroundStyle(muted)
        }.padding(.trailing,8)
      }
      Divider()
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Choose output & export…", action: model.exportVideo).buttonStyle(.borderedProminent)
          .foregroundStyle(bg).disabled(model.exportRangeError != nil || model.exportProgress != nil)
      }
    }.padding(28).frame(width:560,height:820).background(bg).preferredColorScheme(.dark).tint(mint)
      .alert("Export could not start", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
        Button("OK") { model.error = nil }
      } message: { Text(model.error ?? "") }
  }
}
