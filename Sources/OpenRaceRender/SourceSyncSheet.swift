import RaceCore
import SwiftUI

extension EditorModel {
  func beginSourceSync() { pause(); showSourceSync = true }
  @discardableResult func alignSources(target:SourceSyncAnchor, reference:SourceSyncAnchor, rate:Double) -> Double? {
    do {
      var updated = project
      let time = try updated.alignSource(target,to:reference,rate:rate)
      if updated != project { checkpoint(); project = updated }
      status = "Aligned source events at " + clockText(time)
      return time
    } catch { self.error = error.localizedDescription; return nil }
  }
}

struct SourceSyncSheet: View {
  @ObservedObject var model:EditorModel
  var initialTargetIndex:Int?
  @Environment(\.dismiss) var dismiss
  @StateObject private var referencePlayer = SourceSyncPlayer()
  @StateObject private var targetPlayer = SourceSyncPlayer()
  @State private var referenceID:UUID?
  @State private var targetID:UUID?
  @State private var rate = 1.0
  @State private var alignedTime:Double?
  @State private var failure:String?
  var references:[MediaInput] { model.project.inputs.filter { $0.kind == "video" && $0.isJoinRoot != true && $0.isTimeFiller != true } }
  var targets:[MediaInput] {
    let root = reference.map { $0.joinedTo ?? $0.legacyIndex }
    return references.filter { $0.joinedTo == nil && $0.legacyIndex != root }
  }
  var reference:MediaInput? { references.first { $0.id == referenceID } }
  var target:MediaInput? { targets.first { $0.id == targetID } }
  var referenceRate:Double {
    model.project.placements.first(where:{$0.input.id == referenceID})?.rate ?? 1
  }
  var body:some View {
    VStack(alignment:.leading,spacing:15) {
      Text("Side-by-side camera synchronization").font(.title2)
      Text("Find the same visible event in each raw source, then align the target to the reference. The reference timing stays fixed.").font(.callout).foregroundStyle(muted)
      if references.count < 2 { Text("Add two camera files to use this tool.").foregroundStyle(.orange) }
      HStack(alignment:.top,spacing:20) {
        VStack(alignment:.leading,spacing:10) {
          Picker("Reference",selection:$referenceID) {
            Text("Choose reference").tag(nil as UUID?)
            ForEach(references) { Text($0.name).tag(Optional($0.id)) }
          }
          SourceSyncPanel(player:referencePlayer,title:"Reference source",rate:referenceRate)
        }
        VStack(alignment:.leading,spacing:10) {
          Picker("Adjust this camera",selection:$targetID) {
            Text("Choose target").tag(nil as UUID?)
            ForEach(targets) { Text($0.name).tag(Optional($0.id)) }
          }
          SourceSyncPanel(player:targetPlayer,title:"Target source",rate:rate)
        }
      }
      HStack {
        NumberSetting("Target playback rate",value:$rate).frame(width:220)
        Button("Align these events") { align() }.buttonStyle(.borderedProminent)
          .disabled(reference == nil || target == nil || referencePlayer.loading || targetPlayer.loading || referencePlayer.seeking || targetPlayer.seeking || referencePlayer.error != nil || targetPlayer.error != nil || referencePlayer.duration <= 0 || targetPlayer.duration <= 0)
        Button("Play together") { referencePlayer.play(rate:referenceRate); targetPlayer.play(rate:rate) }
          .disabled(referencePlayer.duration <= 0 || targetPlayer.duration <= 0)
        Button("Pause both") { pauseBoth() }
      }
      if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
      if let alignedTime {
        Label("Aligned at project " + clockText(alignedTime),systemImage:"checkmark.circle").foregroundStyle(mint)
      }
      Text("Unmute either side to compare audio. Use the composed preview after aligning to check other events. Joined targets use their stream timing in the input inspector.").font(.caption).foregroundStyle(muted)
      HStack {
        Spacer()
        Button("View in composition") {
          pauseBoth(); model.seek(min(alignedTime ?? model.time,max(0,model.project.duration-1/model.project.fps))); dismiss()
        }
        Button("Done") { pauseBoth(); dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width:910).background(bg).preferredColorScheme(.dark).tint(mint).textFieldStyle(.roundedBorder)
      .onAppear { model.pause(); chooseInputs() }
      .onDisappear { pauseBoth() }
      .onChange(of:referenceID) { _,_ in
        pauseBoth(); alignedTime = nil
        if targetID == referenceID || target == nil { targetID = targets.first?.id }
      }
      .onChange(of:targetID) { _,_ in pauseBoth(); alignedTime = nil; rate = target?.timing?.safeRate ?? 1 }
      .task(id:referenceID) {
        if let reference { await referencePlayer.load(reference,at:initialTime(reference),projectFPS:model.project.fps) }
        else { referencePlayer.clear() }
      }
      .task(id:targetID) {
        if let target { await targetPlayer.load(target,at:initialTime(target),projectFPS:model.project.fps) }
        else { targetPlayer.clear() }
      }
  }
  func initialTime(_ input:MediaInput) -> Double {
    model.sourceTimeAtPlayhead(input) ?? model.project.placements.first(where:{$0.input.id == input.id})?.sourceStart ?? input.timing?.trimStart ?? 0
  }
  func chooseInputs() {
    let preferred = initialTargetIndex ?? model.project.inputs.first(where:{$0.id == model.selectedInput})?.legacyIndex
    let candidate = references.first(where:{$0.legacyIndex == preferred && $0.joinedTo == nil})
    referenceID = references.first(where:{ input in
      guard let candidate else { return true }
      return (input.joinedTo ?? input.legacyIndex) != candidate.legacyIndex
    })?.id
    if referenceID == nil { referenceID = references.first?.id }
    targetID = targets.first(where:{$0.id == candidate?.id})?.id ?? targets.first?.id
    rate = target?.timing?.safeRate ?? 1
  }
  func pauseBoth() { referencePlayer.pause(); targetPlayer.pause() }
  func align() {
    guard let reference, let target else { return }
    pauseBoth(); failure = nil
    let time = model.alignSources(target:SourceSyncAnchor(target.id,at:targetPlayer.time),
      reference:SourceSyncAnchor(reference.id,at:referencePlayer.time),rate:rate)
    if let time { alignedTime = time }
    else { failure = model.error; model.error = nil }
  }
}
