import RaceCore
import SwiftUI

extension EditorModel {
  func restoreEditingSegment(_ event: UUID?) {
    guard let editingSegment else { return }
    if let selected, let event {
      self.editingSegment = project.objects.first { $0.id == selected }?.segments?.first { $0.id == event }?.time
    } else if !project.objects.contains(where:{ $0.id == selected && ($0.segments ?? []).contains(where:{abs($0.time-editingSegment)<1e-6}) }) {
      self.editingSegment = nil
    }
  }
  var timelineExtent: Double {
    var extent = project.duration
    for object in project.objects {
      for segment in object.segments ?? [] {
        let time = segment.time
        if time.isFinite && time >= 0 && time < 1_000_000 { extent = max(extent,time) }
      }
    }
    return extent
  }
  var timelineSpan: Double { max(1/max(1,project.fps),timelineExtent/max(1,timelineZoom)) }
  var timelineLower: Double { max(0,min(timelineStart,max(0,timelineExtent-timelineSpan))) }
  var timelineUpper: Double { min(timelineExtent,timelineLower+timelineSpan) }
  func zoomTimeline(_ factor: Double) {
    let center = max(timelineLower,min(timelineUpper,time))
    timelineZoom = max(1,min(4096,timelineZoom*factor)); timelineStart = max(0,center-timelineSpan/2)
  }
  func resetTimelineZoom() { timelineZoom = 1; timelineStart = 0 }
  func selectSegment(_ object: UUID, at time: Double?) { selected = object; selectedInput = nil; editingSegment = time; if let time { seek(time) } }
  func moveSelectedSegment(to destination: Double, following: Bool = false) {
    guard let selected, let time = editingSegment else { return }
    do {
      var updated = project
      try updated.retimeSegment(selected,at:time,to:destination,following:following)
      guard updated != project else { return }
      checkpoint(); project = updated; editingSegment = destination; seek(destination)
    } catch { self.error = error.localizedDescription }
  }
  func setSelectedSegmentField(_ field: SegmentField, enabled: Bool) {
    guard let selected, let time = editingSegment else { return }
    do {
      var updated = project; try updated.setSegmentOverride(selected,at:time,field:field,enabled:enabled)
      guard updated != project else { return }; checkpoint(); project = updated
    } catch { self.error = error.localizedDescription }
  }
  func inheritSelectedSegment() {
    guard let selected, let time = editingSegment else { return }
    do { var updated = project; try updated.inheritSegment(selected,at:time); guard updated != project else { return }; checkpoint(); project = updated }
    catch { self.error = error.localizedDescription }
  }
}

struct TimelineZoomControls: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    HStack {
      Button("−") { model.zoomTimeline(0.5) }.help("Zoom out")
      Button("+") { model.zoomTimeline(2) }.help("Zoom in")
      Button("Fit") { model.resetTimelineZoom() }
      Button("Playhead") { model.timelineStart = max(0,model.time-model.timelineSpan/2) }
      Text("\(clockText(model.timelineLower)) → \(clockText(model.timelineUpper))").font(.system(size:10,design:.monospaced)).foregroundStyle(muted)
      if model.timelineZoom > 1 {
        Slider(value:Binding(get:{model.timelineLower},set:{model.timelineStart = $0}),in:0...max(0.001,model.timelineExtent-model.timelineSpan)).accessibilityLabel("Timeline window start")
      }
      Spacer()
    }.controlSize(.small)
  }
}

struct SegmentEditingControls: View {
  @ObservedObject var model: EditorModel
  var object: DisplayObject
  var segment: ObjectSegment
  @State var destination: Double
  @State var shift: Double = 0
  init(model:EditorModel,object:DisplayObject,segment:ObjectSegment) {
    self.model = model; self.object = object; self.segment = segment
    _destination = State(initialValue:segment.time)
  }
  var body: some View {
    VStack(alignment:.leading,spacing:8) {
      NumberSetting("Starting time (s)",value:$destination)
      HStack {
        Button("Move") { model.moveSelectedSegment(to:destination) }
        Button("−1 frame") { model.moveSelectedSegment(to:segment.time-1/model.project.fps) }.disabled(segment.time < 1/model.project.fps)
        Button("+1 frame") { model.moveSelectedSegment(to:segment.time+1/model.project.fps) }
      }
      NumberSetting("Shift by seconds",value:$shift)
      Button("Shift this and following events") { model.moveSelectedSegment(to:segment.time+shift,following:true) }
      if segment.time > model.project.duration { Text("This event is beyond the project length.").foregroundStyle(.orange) }
      DisclosureGroup("Fields changed in this segment") {
        VStack(alignment:.leading,spacing:6) {
          ForEach(SegmentField.available(for:object)) { field in
            Toggle(field.title,isOn:Binding(get:{segment.overrides(field)},set:{model.setSelectedSegmentField(field,enabled:$0)}))
          }
        }.padding(.top,8)
      }
      Text("Unchecked fields inherit from the preceding segment. Checking a field freezes its current value.").font(.caption2).foregroundStyle(muted)
      Button("Inherit all fields",action:model.inheritSelectedSegment)
    }.onChange(of:segment.time) { _,time in destination = time }
  }
}
