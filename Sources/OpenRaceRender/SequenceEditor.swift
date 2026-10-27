import RaceCore
import SwiftUI

extension EditorModel {
  func editSequence(_ id:UUID) {
    guard let input = project.inputs.first(where:{$0.id == id}) else { return }
    pause(); sequenceInput = input
  }
  func moveInput(_ id:UUID,direction:Int) {
    do {
      var updated = project; try updated.moveInput(id,direction:direction)
      if updated != project { checkpoint(); project = updated }
    } catch { self.error = error.localizedDescription }
  }
  @discardableResult func applySequence(_ draft:SequenceDraft) -> Bool {
    do {
      let updated = try draft.applying(to:project)
      if updated != project { checkpoint(); project = updated }
      selected = nil; selectedInput = project.inputs.first(where:{$0.legacyIndex == draft.rootIndex})?.id
      status = "Updated joined sequence"; return true
    } catch { self.error = error.localizedDescription; return false }
  }
}

struct SourceListRow: View {
  @ObservedObject var model:EditorModel
  var input:MediaInput
  var generated:Bool { input.isJoinRoot == true || input.isTimeFiller == true }
  var detail:String {
    if input.isTimeFiller == true { return "GAP · "+clockText(input.duration) }
    if input.isJoinRoot == true { return "JOINED STREAM · "+clockText(input.duration) }
    if input.exists { return input.kind.uppercased()+" · "+clockText(input.duration) }
    return input.path.isEmpty ? "TEMPLATE SOURCE · Choose file" : "MISSING · Relink file"
  }
  var body:some View {
    HStack(spacing:10) {
      Image(systemName:input.isTimeFiller == true ? "rectangle.dashed" : input.isJoinRoot == true ? "film.stack" : input.kind == "data" ? "waveform.path.ecg" : input.kind == "audio" ? "speaker.wave.2" : "video")
        .foregroundStyle(input.kind == "data" ? mint : Color.blue)
      VStack(alignment:.leading,spacing:3) {
        Text(input.name).font(.system(size:11)).lineLimit(1)
        Text(detail).font(.system(size:9)).foregroundStyle(generated || input.exists ? muted : .orange)
      }
      Spacer(minLength:0)
    }.padding(10).padding(.leading,input.joinedTo == nil ? 0 : 12)
      .background(model.selectedInput == input.id ? mint.opacity(0.08) : .clear).contentShape(Rectangle())
      .onTapGesture { model.selectedInput = input.id; model.selected = nil }
      .contextMenu {
        Button(input.joinedTo == nil ? "Move stream up" : "Move clip up") { model.moveInput(input.id,direction:-1) }
        Button(input.joinedTo == nil ? "Move stream down" : "Move clip down") { model.moveInput(input.id,direction:1) }
        if input.kind == "data" { Button("Duplicate data input") { model.duplicateData(input.id) } }
        if ["video","audio"].contains(input.kind) { Button("Edit sequence / add time filler…") { model.editSequence(input.id) } }
        Button("Remove input and its displays",role:.destructive) { model.removeInput(input.id) }
      }
  }
}

struct TimeFillerInspector: View {
  @ObservedObject var model:EditorModel
  @Binding var input:MediaInput
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Time filler").font(.headline)
      TextField("Label",text:$input.name)
      NumberSetting("Duration (seconds)",value:Binding(get:{input.duration},set:{value in
        guard value.isFinite, value > 0 else { model.error = "Enter a positive filler duration."; return }
        input.duration = value
      }))
      Text("This stream contributes no picture or audio during the gap. Other layers and sources continue.").font(.caption).foregroundStyle(muted)
      Button("Edit sequence…") { model.editSequence(input.id) }
      Button("Remove time filler",role:.destructive) { model.removeInput(input.id) }
    }.textFieldStyle(.roundedBorder).padding(16)
  }
}

struct SequenceEditor: View {
  @ObservedObject var model:EditorModel
  var inputID:UUID
  @Environment(\.dismiss) var dismiss
  @State private var draft:SequenceDraft?
  @State private var selected:UUID?
  @State private var trimming:MediaInput?
  @State private var failure:String?
  var clip:MediaInput? { draft?.clips.first(where:{$0.id == selected}) }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Joined sequence").font(.title2)
      Text("Arrange physical clips and time fillers. Apply saves the sequence as one edit; Cancel keeps the current project.").font(.callout).foregroundStyle(muted)
      if let draft {
        HStack(alignment:.top,spacing:20) {
          VStack(alignment:.leading,spacing:10) {
            ScrollView {
              VStack(spacing:5) {
                ForEach(Array(draft.clips.enumerated()),id:\.element.id) { index,input in
                  HStack {
                    Button { selected = input.id } label: {
                      HStack {
                        Text("\(index+1)").monospacedDigit().foregroundStyle(muted)
                        Image(systemName:input.isTimeFiller == true ? "rectangle.dashed" : "film")
                        Text(input.name).lineLimit(1); Spacer()
                      }.padding(9).background(selected == input.id ? mint.opacity(0.15) : panelColor)
                    }.buttonStyle(.plain)
                    Button("↑") { edit { try $0.move(input.id,to:index-1) } }.disabled(index == 0)
                    Button("↓") { edit { try $0.move(input.id,to:index+1) } }.disabled(index == draft.clips.count-1)
                  }
                }
              }
            }
            Button("Add time filler after selection") { edit { selected = try $0.addFiller(after:selected) } }
            Text("Stream length: "+clockText(draft.project.placements.filter{$0.rootIndex == draft.rootIndex}.map(\.end).max() ?? 0)).font(.caption).foregroundStyle(mint)
          }.frame(width:400)
          if let clip { details(clip) } else { Text("Select a clip").frame(width:360,height:220) }
        }.frame(height:450)
      } else { ProgressView("Reading sequence…") }
      if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          if let draft, model.applySequence(draft) { dismiss() }
          else { failure = model.error; model.error = nil }
        }.disabled(draft == nil).keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width:840).textFieldStyle(.roundedBorder).background(bg).preferredColorScheme(.dark).tint(mint)
      .onAppear {
        do {
          let value = try SequenceDraft(project:model.project,inputID:inputID); draft = value
          selected = value.clips.first(where:{$0.id == inputID || value.originalIDs[$0.id] == inputID})?.id ?? value.clips.first?.id
        } catch { failure = error.localizedDescription }
      }
      .sheet(item:$trimming) { snapshot in
        SourceTrimEditor(model:model,input:Binding(get:{draft?.clips.first(where:{$0.id == snapshot.id}) ?? snapshot},set:{value in
          edit { try $0.update(value) }
        }),playheadInputID:draft?.originalIDs[snapshot.id])
      }
  }
  func details(_ input:MediaInput) -> some View {
    VStack(alignment:.leading,spacing:12) {
      TextField("Clip label",text:Binding(get:{clip?.name ?? input.name},set:{value in update(input) { $0.name = value } }))
      if input.isTimeFiller == true {
        Image(systemName:"rectangle.dashed").font(.system(size:56)).frame(width:360,height:200)
        NumberSetting("Gap seconds",value:Binding(get:{clip?.duration ?? input.duration},set:{value in update(input) { $0.duration = value } }))
        Text("No picture or audio from this stream; other layers continue.").font(.caption).foregroundStyle(muted)
        Button("Remove time filler",role:.destructive) { edit { $0.removeFiller(input.id); selected = $0.clips.first?.id } }
      } else {
        SourceThumbnail(input:input,time:max(0,input.timing?.trimStart ?? 0)+max(0,input.offset),data:nil,picture:input.picture).frame(width:360,height:202)
        Text("Source: "+clockText(input.duration)+" · Trim "+clockText(input.timing?.trimStart ?? 0)+" – "+clockText(input.timing?.trimEnd ?? input.duration)).font(.caption).foregroundStyle(muted)
        Button("Trim clip…") { trimming = input }
        NumberSetting("Playback rate",value:Binding(get:{clip?.timing?.rate ?? 1},set:{value in update(input) {
          var timing = $0.timing ?? InputTiming(); timing.rate = value; $0.timing = timing
        } }))
      }
    }.frame(width:360)
  }
  func edit(_ operation:(inout SequenceDraft)throws->Void) {
    do { if var value = draft { try operation(&value); draft = value; failure = nil } }
    catch { failure = error.localizedDescription }
  }
  func update(_ input:MediaInput,change:(inout MediaInput)->Void) {
    var value = draft?.clips.first(where:{$0.id == input.id}) ?? input
    change(&value); edit { try $0.update(value) }
  }
}
