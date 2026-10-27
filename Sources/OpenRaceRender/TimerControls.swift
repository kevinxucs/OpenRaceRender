import RaceCore
import SwiftUI

struct TimerControls:View {
  @Binding var object:DisplayObject
  @ObservedObject var model:EditorModel
  var settings:Binding<TimerSettings> { Binding(get:{object.timerSettings ?? TimerSettings()},set:{object.timerSettings = $0}) }
  var body:some View {
    DisclosureGroup("Timer / clock") {
      VStack(alignment:.leading,spacing:10) {
        Picker("Mode",selection:settings.mode) {
          Text("Lap elapsed time").tag(TimerSettings.Mode.lap)
          Text("Manual project timer").tag(TimerSettings.Mode.manual)
          Text("Time of day").tag(TimerSettings.Mode.timeOfDay)
        }
        if settings.wrappedValue.mode == .manual {
          NumberSetting("Start delay (s)",value:settings.startDelay)
          NumberSetting("Initial displayed seconds",value:settings.startOffset)
          NumberSetting("Project anchor (s)",value:Binding(get:{settings.wrappedValue.anchorTime ?? object.start},set:{settings.wrappedValue.anchorTime = $0}))
          Button("Anchor at playhead") { settings.wrappedValue.anchorTime = model.time }
          Toggle("Stop and hold",isOn:Binding(get:{settings.wrappedValue.stopValue != nil},set:{settings.wrappedValue.stopValue = $0 ? settings.wrappedValue.startOffset+60 : nil}))
          if settings.wrappedValue.stopValue != nil { NumberSetting("Stop at displayed seconds",value:Binding(get:{settings.wrappedValue.stopValue ?? 60},set:{settings.wrappedValue.stopValue = $0})) }
          Text("Counts from the widget's Start unless anchored explicitly. Delay holds the initial value. Stop is a displayed value, not elapsed duration. Project time is independent of data synchronization.").font(.caption2).foregroundStyle(muted)
        }
        if settings.wrappedValue.mode == .timeOfDay {
          Picker("Clock",selection:settings.clock) { Text("Source recorded time").tag(TimerSettings.Clock.source); Text("Project time").tag(TimerSettings.Clock.project) }
          Toggle("Override UTC clock anchor",isOn:Binding(get:{settings.wrappedValue.epoch != nil},set:{settings.wrappedValue.epoch = $0 ? model.telemetry[object.inputIndex]?.firstSampleUnixTime ?? Date().timeIntervalSince1970 : nil}))
          if settings.wrappedValue.epoch != nil {
            DatePicker("UTC at clock zero",selection:Binding(get:{Date(timeIntervalSince1970:settings.wrappedValue.epoch ?? 0)},set:{settings.wrappedValue.epoch = $0.timeIntervalSince1970}),displayedComponents:[.date,.hourAndMinute])
              .environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
            Text("Exact UTC Unix seconds (fraction allowed)").font(.caption2)
            TextField("UTC Unix seconds",value:Binding(get:{settings.wrappedValue.epoch ?? 0},set:{settings.wrappedValue.epoch = $0}),format:.number.precision(.fractionLength(0...6)))
          }
          Text("Display timezone (IANA identifier)").font(.caption2)
          TextField("e.g. America/Los_Angeles",text:settings.timeZone)
          HStack { Button("UTC") { settings.wrappedValue.timeZone = "UTC" }; Button("System timezone") { settings.wrappedValue.timeZone = TimeZone.current.identifier } }
          if settings.wrappedValue.clock == .source,settings.wrappedValue.epoch == nil,model.telemetry[object.inputIndex]?.firstSampleUnixTime == nil {
            Text("This source has no recorded UTC epoch. Enable the clock-anchor override.").font(.caption).foregroundStyle(.orange)
          }
          Toggle("12-hour clock",isOn:settings.twelveHour)
          Toggle("Show timezone suffix",isOn:settings.showTimeZone)
          if settings.wrappedValue.clock == .source,!model.project.inputs.contains(where:{$0.legacyIndex == object.inputIndex}) {
            Text("Choose a source input, or use Project time for a clock without telemetry.").font(.caption).foregroundStyle(.orange)
          }
          Text("RCZ supplies its recorded UTC epoch automatically for the source clock. For other formats, set an explicit clock anchor; relative timestamps are never guessed to be wall time. Project clocks require an explicit anchor.").font(.caption2).foregroundStyle(muted)
        }
        Picker("Format",selection:settings.format) {
          Text("Automatic").tag(TimerSettings.Format.automatic); Text("Seconds").tag(TimerSettings.Format.seconds)
          Text("Minutes : seconds").tag(TimerSettings.Format.minutesSeconds); Text("Hours : minutes : seconds").tag(TimerSettings.Format.hoursMinutesSeconds)
        }
        Stepper("Decimal places: \(settings.wrappedValue.decimals)",value:settings.decimals,in:0...3)
        Toggle("Compact leading component",isOn:settings.compact)
        TextField("Label (automatic when empty)",text:settings.label)
        Toggle("Draw panel",isOn:settings.panel)
        Text("Preview: " + settings.wrappedValue.string(projectTime:model.time,sourceTime:model.project.sourceTime(for:object.inputIndex,at:model.time) ?? -1,displayStart:object.start,data:model.telemetry[object.inputIndex]))
          .font(.caption.monospacedDigit()).textSelection(.enabled)
        if let issue = validationIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
        Text("Edits use the native timer renderer. Reset restores the original imported style or default lap timer.").font(.caption2).foregroundStyle(muted)
        Button("Reset timer settings") { object.timerSettings = nil }
      }.padding(.top,8)
    }
  }
  var validationIssue:String? {
    do { try settings.wrappedValue.validate(); return nil } catch { return error.localizedDescription }
  }
}
