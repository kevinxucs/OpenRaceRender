import RaceCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class WidgetCatalog: ObservableObject {
  @Published var templates: [LayoutLibrary.Entry] = []
  @Published var styles: [WidgetStyle] = []
  @Published var loading = false
  @Published var message: String?
  private var entries: [LayoutLibrary.Entry] = []
  private var loaded = false
  private var generation = UUID()
  func discover(refresh: Bool = false) async {
    guard !loaded || refresh else { return }
    loaded = true
    let found = await Task.detached(priority: .utility) { LayoutLibrary.entries(in: LayoutLibrary.defaultRoots()) }.value
    guard !Task.isCancelled else { loaded = false; return }
    entries = found
    templates = found.filter { $0.category == .templates }
  }
  func load(_ source: String) async {
    guard !Task.isCancelled else { return }
    let revision = UUID(); generation = revision
    styles = []; message = nil; loading = !source.isEmpty
    guard !source.isEmpty else { loading = false; return }
    let files = source == "styles" ? entries.filter { $0.category == .styles }.map(\.url) : [URL(fileURLWithPath: source)]
    let result = await Task.detached(priority: .utility) {
      var styles: [WidgetStyle] = [], failures = 0
      for file in files {
        do { styles += try WidgetStyle.read(file) } catch { failures += 1 }
      }
      return (styles, failures)
    }.value
    guard revision == generation, !Task.isCancelled else { return }
    styles = result.0; loading = false
    if result.1 > 0 { message = "Could not read \(result.1) library file(s)." }
    else if styles.isEmpty { message = "No widget styles here. Import your library in Templates, or choose a saved template." }
  }
}

struct WidgetSourcePicker: View {
  @ObservedObject var catalog: WidgetCatalog
  @Binding var source: String
  var includeBasic = true
  var body: some View {
    Picker("Widget source", selection: $source) {
      if includeBasic { Text("Basic widgets").tag("") }
      Text("Library styles").tag("styles")
      ForEach(catalog.templates) { entry in
        Text("Template: " + entry.url.deletingPathExtension().lastPathComponent).tag(entry.url.path)
      }
      if !source.isEmpty && source != "styles" && !catalog.templates.contains(where: { $0.url.path == source }) {
        Text(URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent).tag(source)
      }
    }.labelsHidden().accessibilityLabel("Widget source")
  }
}

struct WidgetStyleBrowser: View {
  @ObservedObject var model: EditorModel
  @Environment(\.dismiss) var dismiss
  @StateObject var catalog = WidgetCatalog()
  @State var source = "styles"
  @State var search = ""
  @State var selected: WidgetStyle?
  var object: DisplayObject? { model.project.objects.first { $0.id == model.selected } }
  var filtered: [WidgetStyle] {
    catalog.styles.filter { $0.object.kind == object?.kind && (search.isEmpty || ($0.name + " " + $0.object.style).localizedCaseInsensitiveContains(search)) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Choose \(object?.kind.title ?? "widget") style").font(.title2)
      Text("Keeps this widget’s position, size, label, data source and timeline. The style changes its appearance and display range.")
        .font(.callout).foregroundStyle(muted)
      HStack {
        WidgetSourcePicker(catalog: catalog, source: $source, includeBasic: false)
        TextField("Search styles", text: $search)
        Button("Choose file…") {
          let panel = NSOpenPanel(); panel.directoryURL = LayoutLibrary.userRoot()
          panel.allowedContentTypes = [UTType(filenameExtension: "rro")!, UTType(filenameExtension: "rrt")!, UTType(filenameExtension: "orrt")!]
          if panel.runModal() == .OK, let url = panel.url { source = url.path }
        }
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 12) {
          if let object {
            let native = nativeStyle(object.kind)
            styleButton(WidgetStyle(id: "native", name: "Native style", object: native))
          }
          ForEach(filtered) { style in styleButton(style) }
        }
      }
      if catalog.loading { ProgressView("Reading styles…").controlSize(.small) }
      if let message = catalog.message { Text(message).font(.caption).foregroundStyle(.orange) }
      HStack {
        Text("\(filtered.count) compatible library styles").font(.caption).foregroundStyle(muted)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply style") {
          if let selected { var layout = RaceProject(); layout.objects = [selected.object]; model.applyStyle(layout); dismiss() }
        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(selected == nil)
      }
    }.padding(24).frame(width: 740, height: 560).background(bg).preferredColorScheme(.dark).tint(mint)
      .task { await catalog.discover(); await catalog.load(source) }
      .onChange(of: source) { _, value in selected = nil; Task { await catalog.load(value) } }
  }
  func nativeStyle(_ kind: ObjectKind) -> DisplayObject {
    var o = DisplayObject(name: "Native style", kind: kind)
    o.maximum = [.rpm, .lights].contains(kind) ? 8000 : kind == .speed ? 160 : 100
    if kind == .text { o.text = "Your text" }
    return o
  }
  func styleButton(_ style: WidgetStyle) -> some View {
    Button { selected = style } label: {
      VStack(spacing: 8) {
        WidgetThumbnail(object: style.object).frame(height: 86)
        Text(style.object.style.isEmpty ? style.name : style.object.style).font(.system(size: 11)).lineLimit(2).frame(height: 30)
      }.padding(8).frame(maxWidth: .infinity).background(selected?.id == style.id ? mint.opacity(0.15) : panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 6)).overlay {
          RoundedRectangle(cornerRadius: 6).stroke(selected?.id == style.id ? mint : .clear)
        }
    }.buttonStyle(.plain).accessibilityLabel(style.object.style.isEmpty ? style.name : style.object.style)
  }
}

struct WidgetThumbnail: View {
  var object: DisplayObject
  @State var image: NSImage?
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 4).fill(bg)
      if let image { Image(nsImage: image).resizable().scaledToFit() }
      else { Image(systemName: object.kind.symbol).foregroundStyle(mint) }
    }.task(id: object.id) {
      image = await Task.detached(priority: .utility) { WidgetDesign.thumbnail(object) }.value
    }
  }
}

struct WidgetRangeControls: View {
  @Binding var object: DisplayObject
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      bound("Minimum", \.styleMinimum, fallback: object.minimum)
      bound("Maximum", \.styleMaximum, fallback: object.maximum)
    }
  }
  func bound(_ title: String, _ key: WritableKeyPath<DisplayObject, Double?>, fallback: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle("Automatic " + title.lowercased(), isOn: Binding(get: { object[keyPath: key] == nil }, set: { object[keyPath: key] = $0 ? nil : fallback }))
      if object[keyPath: key] != nil {
        Text(title).foregroundStyle(muted)
        TextField(title, value: Binding(get: { object[keyPath: key] ?? fallback }, set: { object[keyPath: key] = $0 }), format: .number)
      }
    }.font(.system(size: 10))
  }
}

struct ScriptStyleControls: View {
  @Binding var object: DisplayObject
  var body: some View {
    DisclosureGroup("Style settings") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("Show style caption", isOn: $object.styleLabelVisible)
        TextField("Style caption", text: $object.styleLabel)
        Text("Caption font size").foregroundStyle(muted)
        TextField("Caption font size", value: $object.styleLabelSize, format: .number)
        Text("Trigger threshold").foregroundStyle(muted)
        TextField("Trigger threshold", value: $object.styleTrigger, format: .number)
        Text("These colors and the trigger are used where the style’s drawing script references them.").foregroundStyle(muted)
        ForEach(0..<8) { index in
          ColorPicker("Color " + String(UnicodeScalar(65+index)!), selection: Binding(
            get: { Color(cgColor: OverlayRenderer.color(object.styleColor(index))) },
            set: { color in
              if let rgb = NSColor(color).usingColorSpace(.deviceRGB) {
                object.setStyleColor(String(format: "#%02X%02X%02X", Int(rgb.redComponent*255), Int(rgb.greenComponent*255), Int(rgb.blueComponent*255)), index: index)
              }
            }), supportsOpacity: false)
        }
      }.padding(.top, 8)
    }.font(.system(size: 11))
  }
}
