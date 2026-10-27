import RaceCore
import SwiftUI

extension EditorModel {
  @discardableResult func duplicateData(_ id:UUID,forMap objectID:UUID? = nil) -> UUID? {
    do {
      var updated = project; let copyID = try updated.duplicateDataInput(id)
      let source = updated.inputs.first{$0.id == id}!,copy = updated.inputs.first{$0.id == copyID}!
      if let objectID {
        guard var object = updated.displayForEditing(objectID,at:editingSegment),object.kind == .map else { throw RaceError.invalid("The map changed before duplication. Choose the map again.") }
        if object.mapComparison == nil { object.mapComparison = MapComparisonSettings() }
        object.mapComparison?.referenceInputIndex = copy.legacyIndex; object.mapComparison?.mode = .timeline
        updated.updateDisplay(object,at:editingSegment)
      }
      checkpoint(); project = updated; telemetry[copy.legacyIndex] = telemetry[source.legacyIndex]
      if objectID == nil { selected = nil; selectedInput = copyID }
      status = "Duplicated data source · independent synchronization"; return copyID
    } catch { self.error = error.localizedDescription; return nil }
  }
  func alignMapLaps(_ object:DisplayObject) {
    guard let settings = object.mapComparison,
      let primary = project.inputs.first(where:{$0.legacyIndex == object.inputIndex}),
      let reference = project.inputs.first(where:{$0.legacyIndex == settings.referenceInputIndex}),
      let a = telemetry[primary.legacyIndex],let b = telemetry[reference.legacyIndex] else { error = "Choose loaded data inputs first."; return }
    let time = project.sourceTime(for:primary.legacyIndex,at:self.time) ?? -1
    let current = settings.primaryLapStart ?? a.lap(at:time)?.start ?? a.laps.first?.start
    let other = settings.referenceLapStart ?? b.laps.first?.start
    guard let current,let other else { error = "Choose lap starts or configure GPS lap timing first."; return }
    do {
      var updated = project
      let aligned = try updated.alignDataLaps(primary:SourceSyncAnchor(primary.id,at:current),reference:SourceSyncAnchor(reference.id,at:other))
      if updated != project { checkpoint(); project = updated }
      seek(aligned); status = "Aligned comparison lap starts at " + clockText(aligned)
    } catch { self.error = error.localizedDescription }
  }
}

struct MapComparisonControls:View {
  @ObservedObject var model:EditorModel
  @Binding var object:DisplayObject
  var dataInputs:[MediaInput] { model.project.inputs.filter{$0.kind == "data" && $0.joinedTo == nil && $0.isJoinRoot != true} }
  var primary:MediaInput? { dataInputs.first{$0.legacyIndex == object.inputIndex} }
  var reference:MediaInput? { dataInputs.first{$0.legacyIndex == object.mapComparison?.referenceInputIndex} }
  var settings:Binding<MapComparisonSettings> { Binding(get:{object.mapComparison ?? MapComparisonSettings()},set:{object.mapComparison = $0}) }
  var body:some View {
    DisclosureGroup("Two-run map / lap ghost") {
      VStack(alignment:.leading,spacing:10) {
        Toggle("Show comparison",isOn:Binding(get:{object.mapComparison != nil},set:{enabled in
          if enabled {
            var value = MapComparisonSettings()
            value.referenceInputIndex = dataInputs.first{$0.legacyIndex != object.inputIndex}?.legacyIndex ?? object.inputIndex
            value.mode = value.referenceInputIndex == object.inputIndex ? .lapGhost : .timeline
            object.mapComparison = value
          } else { object.mapComparison = nil }
        }))
        if object.mapComparison != nil {
          Text("Both markers use one GPS projection and shared bounds. The filled marker is primary; the hollow marker is the comparison.").font(.caption2).foregroundStyle(muted)
          Picker("Comparison",selection:settings.referenceInputIndex) {
            Text("Choose data input").tag(-1)
            ForEach(dataInputs){Text($0.name).tag($0.legacyIndex)}
          }
          Picker("Clock",selection:settings.mode) {
            Text("Each input's synchronized time").tag(MapComparisonSettings.Mode.timeline)
            Text("Lap ghost: match elapsed lap time").tag(MapComparisonSettings.Mode.lapGhost)
          }
          lapPicker("Primary lap",index:object.inputIndex,value:settings.primaryLapStart,
            automatic:settings.wrappedValue.mode == .lapGhost ? "Current lap" : "Whole source / active lap for alignment")
          lapPicker("Comparison lap",index:settings.wrappedValue.referenceInputIndex,value:settings.referenceLapStart,
            automatic:settings.wrappedValue.mode == .lapGhost ? "Best complete lap (whole source)" : "Whole source / first lap for alignment")
          if settings.wrappedValue.mode == .timeline {
            if reference?.id == primary?.id { Text("Duplicate the data input for an independent lap offset.").font(.caption).foregroundStyle(.orange) }
            Button("Align selected lap starts") { model.alignMapLaps(object) }.disabled(primary == nil || reference == nil || primary?.id == reference?.id)
            if let reference {
              NumberSetting("Comparison offset (s)",value:model.inputBinding(reference.id).offset).disabled(primary?.id == reference.id)
            }
            Text("Alignment changes the comparison input's clock for every widget using it. Duplicate it first if it also drives other overlays.").font(.caption2).foregroundStyle(muted)
          } else {
            Text("The ghost starts with the primary lap, keeps its actual pace and waits at the finish. It uses the recorded reference lap independently of synchronization, trim and playback rate. Explicit lap selections hide markers outside that interval.").font(.caption2).foregroundStyle(muted)
            if model.telemetry[settings.wrappedValue.referenceInputIndex]?.bestLap == nil && settings.wrappedValue.referenceLapStart == nil {
              Text("No complete reference lap. Choose a partial run explicitly or configure start/finish timing.").font(.caption).foregroundStyle(.orange)
            }
          }
          if let primary { Button("Duplicate primary as comparison") { model.duplicateData(primary.id,forMap:object.id) } }
          Toggle("Draw comparison course",isOn:settings.showReferenceTrace)
          HexColorControl("Comparison color",value:settings.referenceColor)
          Toggle("Show source labels",isOn:settings.showLabels)
        }
      }.padding(.top,8)
    }
  }
  func lapPicker(_ title:String,index:Int,value:Binding<Double?>,automatic:String) -> some View {
    let laps = model.telemetry[index]?.laps ?? []
    return Picker(title,selection:value) {
      Text(automatic).tag(nil as Double?)
      if let start = value.wrappedValue,!laps.contains(where:{abs($0.start-start) < 1e-6}) { Text("Unavailable saved lap").tag(Optional(start)) }
      ForEach(laps,id:\.start) { lap in
        Text("\(lap.complete ? "Lap" : "Partial") \(lap.number) · \(clockText(lap.start)) · \(String(format:"%.3f s",lap.duration))").tag(Optional(lap.start))
      }
    }
  }
}
