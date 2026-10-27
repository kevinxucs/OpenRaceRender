import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundControls: View {
  @ObservedObject var model: EditorModel
  @Binding var object: DisplayObject
  @State private var showing = false
  var body: some View {
    Button("Edit widget background…") { model.pause(); showing = true }
      .sheet(isPresented:$showing) { BackgroundEditor(model:model,object:$object) }
  }
}

struct BackgroundEditor: View {
  @ObservedObject var model: EditorModel
  @Binding var object: DisplayObject
  @Environment(\.dismiss) var dismiss
  @State var draft: BackgroundDraft
  @State var entireObject = true
  @State var error: String?
  @State var externalURL: URL?
  @State var externalRevision: Date?
  init(model: EditorModel, object: Binding<DisplayObject>) {
    self.model = model; _object = object
    _draft = State(initialValue:BackgroundDraft(image:WidgetBackground.data(for:object.wrappedValue)))
  }
  var outputSize: CGSize { WidgetBackground.canvasSize(for:object,project:model.project) }
  func rendered(width: Int? = nil) throws -> Data? {
    let size = WidgetBackground.canvasSize(for:object,project:model.project,width:width ?? Int(outputSize.width))
    return try draft.png(width:Int(size.width),height:Int(size.height))
  }
  var preview: NSImage? {
    do {
      let size = WidgetBackground.canvasSize(for:object,project:model.project,width:700)
      let data = try rendered(width:700)
      if !entireObject { return data.flatMap { NSImage(data:$0) } }
      var p = model.project
      var o = WidgetBackground.replacing(data,in:object)
      o.parentID = nil; o.parentIndex = -1; o.segments = nil
      o.x = 0; o.y = 0; o.width = 100; o.height = 100; o.visible = true
      p.objects = [o]
      guard let c = CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:Int(size.width)*4,
        space:OverlayRenderer.colorSpace,bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
      OverlayRenderer.draw(c,scene:RenderScene(project:p,telemetry:model.designScene.telemetry),time:model.time,size:size)
      return c.makeImage().map { NSImage(cgImage:$0,size:size) }
    } catch { return nil }
  }
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Widget background · \(object.name)").font(.title2)
      HStack {
        Button("Import…",action:chooseImage)
        Button("Clear") { draft.image = nil; draft.resetTransform(); externalURL = nil; externalRevision = nil }
        Button("Export PNG…",action:exportImage).disabled(draft.image == nil)
        Button("Edit externally…",action:editExternally).disabled(draft.image == nil)
        if externalURL != nil { Button("Reload external edits") { reloadExternal() } }
        Spacer()
      }
      HStack(alignment:.top,spacing:20) {
        VStack(spacing:10) {
          ZStack {
            Canvas { c,size in
              for y in stride(from:0.0,to:size.height,by:16) {
                for x in stride(from:0.0,to:size.width,by:16) {
                  c.fill(Path(CGRect(x:x,y:y,width:16,height:16)),with:.color((Int(x/16)+Int(y/16))%2 == 0 ? .gray.opacity(0.2) : .gray.opacity(0.4)))
                }
              }
            }
            if let preview { Image(nsImage:preview).resizable().scaledToFit() }
            else { Text("Drop an image here, or choose Import").foregroundStyle(.secondary) }
          }.frame(width:600,height:360).clipped().dropDestination(for:URL.self) { urls,_ in
            guard let url = urls.first else { return false }; load(url); return true
          }
          Toggle("Preview entire widget",isOn:$entireObject)
          Text("Drag an image onto the preview. Transforms are baked into the embedded PNG when you apply. Use the widget’s face/background controls if its drawing covers the image.")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth:600,alignment:.leading)
        }
        VStack(alignment:.leading,spacing:12) {
          NumberSetting("Zoom",value:$draft.zoom)
          HStack { Button("−") { draft.zoom = max(0.01,draft.zoom/1.1) }; Button("+") { draft.zoom = min(100,draft.zoom*1.1) }; Button("Reset") { draft.resetTransform() } }
          NumberSetting("Pan X (%)",value:$draft.offsetX)
          Slider(value:$draft.offsetX,in:-100...100)
          NumberSetting("Pan Y (%)",value:$draft.offsetY)
          Slider(value:$draft.offsetY,in:-100...100)
          NumberSetting("Rotate (degrees)",value:$draft.rotation)
          Slider(value:$draft.rotation,in:-180...180)
          Toggle("Maintain aspect ratio",isOn:$draft.maintainAspect)
          Toggle("Chroma key",isOn:Binding(get:{draft.keyColor != nil},set:{draft.keyColor = $0 ? "#00FF00" : nil}))
          if draft.keyColor != nil {
            HexColorControl("Key color",value:Binding(get:{draft.keyColor ?? "#00FF00"},set:{draft.keyColor = $0}))
            NumberSetting("Tolerance (0–1)",value:$draft.keyTolerance)
            NumberSetting("Soft edge (0–1)",value:$draft.keySoftness)
          }
          Text("Embedded output: \(Int(outputSize.width)) × \(Int(outputSize.height)) PNG").font(.caption).foregroundStyle(.secondary)
        }.frame(width:245).controlSize(.small).textFieldStyle(.roundedBorder)
      }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") { apply() }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width:900)
      .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in if externalURL != nil { reloadExternal(ifChanged:true) } }
  }
  func load(_ url: URL, preserveExternal: Bool = false) {
    do {
      let bytes = try Data(contentsOf:url)
      guard NSImage(data:bytes) != nil else { throw RaceError.invalid("Choose a readable image file.") }
      draft = BackgroundDraft(image:bytes); error = nil
      if !preserveExternal { externalURL = nil; externalRevision = nil }
    } catch { self.error = error.localizedDescription }
  }
  func chooseImage() { let p = NSOpenPanel(); p.allowedContentTypes = [.image]; if p.runModal() == .OK, let url = p.url { load(url) } }
  func exportImage() {
    do {
      guard let bytes = try rendered() else { return }
      let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "Widget background.png"
      if p.runModal() == .OK, let url = p.url { try bytes.write(to:url,options:.atomic) }
    } catch { self.error = error.localizedDescription }
  }
  func editExternally() {
    do {
      guard let bytes = try rendered() else { return }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenRaceRender-background-\(UUID().uuidString).png")
      try bytes.write(to:url,options:.atomic); externalURL = url
      externalRevision = (try? FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate]) as? Date
      if !NSWorkspace.shared.open(url) { throw RaceError.invalid("No application could open the PNG. Export it and edit it in your image editor.") }
    } catch { self.error = error.localizedDescription }
  }
  func reloadExternal(ifChanged: Bool = false) {
    guard let externalURL else { return }
    let revision = (try? FileManager.default.attributesOfItem(atPath:externalURL.path)[.modificationDate]) as? Date
    if ifChanged && revision == externalRevision { return }
    load(externalURL,preserveExternal:true); externalRevision = revision
  }
  func apply() {
    do { object = WidgetBackground.replacing(try rendered(),in:object); dismiss() }
    catch { self.error = error.localizedDescription }
  }
}
