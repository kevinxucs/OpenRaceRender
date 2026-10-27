import RaceCore
import SwiftUI
import UniformTypeIdentifiers

struct ScriptEditRequest:Identifiable {
  let id = UUID()
  let object:DisplayObject
  let segment:Double?
  let revision:UUID
}
extension EditorModel {
  func beginScriptEditor(_ id:UUID) {
    guard let object = project.displayForEditing(id,at:editingSegment),object.canEditScripts else {return}
    pause(); scriptEditorRequest = ScriptEditRequest(object:object,segment:editingSegment,revision:documentRevision)
  }
  func applyScript(_ draft:EnhancedScriptDraft,request:ScriptEditRequest) throws {
    guard documentRevision == request.revision,editingSegment == request.segment,
      project.displayForEditing(request.object.id,at:request.segment) == request.object else {throw RaceError.invalid("The project or selected segment changed. Reopen the script editor before applying.")}
    let edited = try draft.applying(to:request.object)
    objectBinding(request.object.id).wrappedValue = edited
  }
}

@MainActor struct ScriptEditor:View {
  @ObservedObject var model:EditorModel
  let request:ScriptEditRequest
  @Environment(\.dismiss) var dismiss
  @State var draft:EnhancedScriptDraft
  @State var stage = 0
  @State var result:EnhancedScriptTest?
  @State var messages = "Edit, compile, then test at a representative time."
  @State var time:Double = 0
  @State var samples = false
  @State var running = false
  @State var testTask:Task<Void,Never>?
  @State var worker:Task<EnhancedScriptTest,Error>?
  @State var generation = UUID()
  init(model:EditorModel,request:ScriptEditRequest) {
    self.model = model; self.request = request
    _draft = State(initialValue:EnhancedScriptDraft(object:request.object))
    _time = State(initialValue:model.time)
    _samples = State(initialValue:model.telemetry[request.object.inputIndex] == nil)
  }
  var source:Binding<String> {stage == 0 ? $draft.background : $draft.foreground}
  var issue:String? {do {try draft.validate();return nil} catch {return error.localizedDescription}}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Enhanced scripts — "+request.object.name).font(.title2.bold())
      ScriptCanvasControls(draft:$draft)
      HStack(alignment:.top,spacing:18) {
        VStack(alignment:.leading,spacing:8) {
          Picker("Script",selection:$stage) {Text("Background").tag(0);Text("Foreground").tag(1)}.pickerStyle(.segmented)
          Text(stage == 0 ? "Static drawing and initial variables." : "Per-frame drawing. Persistent variables replay from the display start.").font(.caption).foregroundStyle(muted)
          TextEditor(text:source).font(.system(size:12,design:.monospaced)).scrollContentBackground(.hidden).background(Color.black.opacity(0.35)).frame(minWidth:560,minHeight:240)
          HStack {Button("Import source…",action:importSource);Button("Save source…",action:saveSource);Spacer();Text("\(source.wrappedValue.utf8.count) / 32767 bytes").font(.caption).foregroundStyle(muted)}
        }
        VStack(alignment:.leading,spacing:8) {
          ZStack {
            Canvas {context,size in
              for y in stride(from:0.0,to:size.height,by:16) {for x in stride(from:0.0,to:size.width,by:16) {
                let shade:Color = (Int(x/16)+Int(y/16))%2 == 0 ? .gray.opacity(0.2) : .gray.opacity(0.4)
                context.fill(Path(CGRect(x:x,y:y,width:16,height:16)),with:.color(shade))
              }}
            }
            if let result {Image(nsImage:NSImage(cgImage:result.image,size:.zero)).resizable().scaledToFit()}
            else {Text("Compile & Test").foregroundStyle(muted)}
          }.frame(width:310,height:150).clipped()
          HStack {
            Text("Seconds").font(.caption)
            TextField("Project test time",value:$time,format:.number.precision(.fractionLength(0...4)))
            Button("Playhead") {time = model.time}.help("Use composition playhead")
          }
          Toggle("Use design sample data",isOn:$samples)
          Text(samples ? "Sample values are used only for this test." : "Uses the input's recorded clock, trim and rate; unavailable outside its placement.").font(.caption2).foregroundStyle(muted)
          Button(running ? "Testing…" : "Compile & Test",action:runTest).disabled(running)
          if running {Button("Cancel test") {cancelTest();messages = "Test canceled."}}
          Link("Language reference",destination:URL(string:"https://racerender.com/RR3/docs/DispObjEnhanced.html")!)
        }.frame(width:310)
      }
      Text("Output messages").font(.headline)
      ScrollView {Text(messages).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(height:80).padding(8).background(.black.opacity(0.3))
      if let issue {Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(3)}
      HStack {
        Text("Apply makes one undoable edit. Source/font/canvas edits are saved in .orrp projects and .orrt templates.").font(.caption).foregroundStyle(muted)
        Spacer();Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
        Button("Apply") {do {try model.applyScript(draft,request:request);dismiss()} catch {messages = error.localizedDescription}}.keyboardShortcut(.defaultAction).disabled(issue != nil || running)
      }
    }.padding(22).frame(width:970,height:790).background(bg).preferredColorScheme(.dark).tint(mint)
      .onChange(of:draft) { _ in invalidate() }
      .onChange(of:time) { _ in invalidate() }
      .onChange(of:samples) { _ in invalidate() }
      .onDisappear{cancelTest()}
  }
  func cancelTest() {generation = UUID();worker?.cancel();testTask?.cancel();worker = nil;testTask = nil;running = false}
  func invalidate() {cancelTest();result = nil;messages = "Edited. Compile & Test to refresh the preview."}
  func runTest() {
    cancelTest()
    guard time.isFinite,time >= 0,time <= model.project.duration else {messages = "Choose a test time within the project.";return}
    do {try draft.validate()} catch {messages = error.localizedDescription;return}
    let id = UUID();generation = id;running = true;messages = "Syntax accepted. Testing…"
    let placement = samples ? nil : model.project.media(for:request.object.inputIndex,at:time)
    let data = samples ? WidgetDesign.telemetry : placement.flatMap{model.telemetry[$0.input.legacyIndex]}
    let start = max(request.object.start,request.segment ?? 0,placement?.start ?? 0)
    let elapsed = max(0,time-start),sourceTime = samples ? time : placement?.sourceTime(at:time) ?? elapsed
    let sourceRate = placement?.rate ?? 1,unit = model.project.speedUnit,fps = model.project.fps
    let object = request.object,draft = draft
    let task = Task.detached {try draft.test(object:object,data:data,sourceTime:sourceTime,displayTime:elapsed,sourceRate:sourceRate,unit:unit,fps:fps)}
    worker = task
    testTask = Task {
      do {
        let tested = try await task.value
        guard !Task.isCancelled,generation == id else {return}
        result = tested;messages = (["Syntax accepted. Current-frame test passed."]+tested.messages).joined(separator:"\n")
        if !samples && placement == nil {messages += "\nNo active recorded source at this time; tested with unavailable values."}
      } catch {if !Task.isCancelled,generation == id {messages = error.localizedDescription}}
      if generation == id {running = false;worker = nil}
    }
  }
  func importSource() {
    let panel = NSOpenPanel();panel.allowedContentTypes = [.plainText,.sourceCode];panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK,let file = panel.url else {return}
    do {
      let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
      guard size < 32768 else {throw RaceError.invalid("Source exceeds 32767 bytes.")}
      source.wrappedValue = try String(contentsOf:file,encoding:.utf8)
    } catch {messages = error.localizedDescription}
  }
  func saveSource() {
    let panel = NSSavePanel();panel.allowedContentTypes = [.plainText];panel.nameFieldStringValue = stage == 0 ? "background.txt" : "foreground.txt"
    guard panel.runModal() == .OK,let file = panel.url else {return}
    do {try source.wrappedValue.write(to:file,atomically:true,encoding:.utf8)} catch {messages = error.localizedDescription}
  }
}

struct ScriptCanvasControls:View {
  @Binding var draft:EnhancedScriptDraft
  var body:some View {
    HStack {
      Text("Canvas");TextField("Width",value:$draft.width,format:.number).frame(width:70)
      Text("×");TextField("Height",value:$draft.height,format:.number).frame(width:70)
      Text("Font");TextField("Script font",text:$draft.font).frame(width:160)
      Toggle("Persistent variables",isOn:$draft.persistent)
      Toggle("Keep canvas aspect",isOn:$draft.maintainAspect)
    }
  }
}
