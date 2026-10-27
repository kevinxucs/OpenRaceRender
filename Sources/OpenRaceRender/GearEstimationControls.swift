import RaceCore
import SwiftUI

struct GearEstimationControls:View {
  @Binding var settings:DataSettings
  var data:Telemetry?
  @ObservedObject var model:EditorModel
  var inputIndex:Int
  var options:Binding<GearEstimationSettings> {
    Binding(get:{settings.gearEstimation ?? GearEstimationSettings()},set:{settings.gearEstimation = $0 == GearEstimationSettings() ? nil : $0})
  }
  var body:some View {
    DisclosureGroup("Gear estimation & calibration") {
      VStack(alignment:.leading,spacing:10) {
        Picker("Gear source",selection:Binding(get:{settings.gearDerivation ?? .automatic},set:{settings.gearDerivation = $0 == .automatic ? nil : $0})) {
          ForEach(DataDerivationMode.allCases,id:\.self) { Text($0.title).tag($0) }
        }
        if let source = data?.provenance(for:"gear") { Text(source.details).font(.caption).foregroundStyle(muted) }
        if let message = data?.gearEstimateMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        NumberSetting("Gear number adjustment",value:Binding(get:{settings.gearAdjustment ?? 0},set:{settings.gearAdjustment = $0.isFinite ? max(-128,min(127,$0.rounded())) : 0}))
        Toggle("Learn ratios automatically",isOn:Binding(get:{options.wrappedValue.ratios == nil},set:{ value in
          var changed = options.wrappedValue; changed.ratios = value ? nil : data?.gearCalibration?.ratios ?? []; options.wrappedValue = changed
        }))
        if let report = data?.gearCalibration {
          Text("\(report.manual ? "Manual" : "Detected") · \(report.ratios.count) ratios · \(Int(report.matchedFraction*100))% of moving samples matched")
            .font(.caption).foregroundStyle(mint)
          if !report.manual {
            Text(report.ratios.enumerated().map { "\($0.offset+1): \($0.element.formatted(.number.precision(.fractionLength(1))))" }.joined(separator:" · ")).font(.system(.caption,design:.monospaced))
            Button("Use detected ratios as manual calibration") { var value = options.wrappedValue; value.ratios = report.ratios; options.wrappedValue = value }
          }
        }
        if let ratios = options.wrappedValue.ratios {
          Text("Ratios: RPM ÷ speed in m/s, highest first").font(.caption).foregroundStyle(muted)
          ForEach(ratios.indices,id:\.self) { index in ratioRow(index) }
          Button("Add gear ratio") {
            var value = options.wrappedValue; var rows = value.ratios ?? []
            rows.append((rows.last ?? (100/0.75))*0.75); value.ratios = rows; options.wrappedValue = value
          }.disabled(ratios.count >= 12)
        }
        limit("Minimum speed (m/s)",key:\.minimumSpeed,defaultValue:3,range:0.1...100)
        limit("Minimum RPM",key:\.minimumRPM,defaultValue:500,range:0...50000)
        NumberSetting("Ratio tolerance (%)",value:Binding(get:{options.wrappedValue.ratioTolerance*100},set:{number in
          guard number.isFinite else { return }; var value = options.wrappedValue; let tolerance = max(0.005,min(0.4,number/100)); value.tolerance = tolerance == 0.12 ? nil : tolerance; options.wrappedValue = value
        }))
        Stepper("Maximum detected gears: \(options.wrappedValue.gearLimit)",value:Binding(get:{options.wrappedValue.gearLimit},set:{var value = options.wrappedValue; value.maximumGears = $0 == 10 ? nil : $0; options.wrappedValue = value}),in:1...12).disabled(options.wrappedValue.ratios != nil)
        limit("Minimum ratio support (s)",key:\.minimumDwell,defaultValue:0.3,range:0.05...10).disabled(options.wrappedValue.ratios != nil)
        Text("Automatic numbers observed ratios from 1. Missing gears may need a number adjustment or complete manual ratios. Clutch slip, CVT and delayed speed/RPM can make estimates unreliable. Unmatched/stopped samples are unknown, not neutral.").font(.caption).foregroundStyle(muted)
        Button("Reset gear settings") { var value = settings; value.gearDerivation = nil; value.gearEstimation = nil; value.gearAdjustment = nil; settings = value }
      }.padding(.top,8)
    }
  }
  func ratioRow(_ index:Int) -> some View {
    HStack {
      NumberSetting("Gear \(index+1)",value:Binding(get:{options.wrappedValue.ratios.flatMap{$0.indices.contains(index) ? $0[index] : nil} ?? 0},set:{number in
        var value = options.wrappedValue; guard var rows = value.ratios,rows.indices.contains(index) else { return }
        rows[index] = number; value.ratios = rows; options.wrappedValue = value
      }))
      Button("Use playhead") {
        let time = model.project.sourceTime(for:inputIndex,at:model.time) ?? -1
        guard let ratio = data?.gearRatio(at:time,settings:options.wrappedValue) else { model.error = "Seek to a moving sample with valid speed and RPM before setting a ratio."; return }
        var value = options.wrappedValue; guard var rows = value.ratios,rows.indices.contains(index) else { return }
        rows[index] = ratio; value.ratios = rows; options.wrappedValue = value
      }
      Button("−") {
        var value = options.wrappedValue; guard var rows = value.ratios,rows.indices.contains(index) else { return }
        rows.remove(at:index); value.ratios = rows; options.wrappedValue = value
      }.help("Remove this ratio and renumber following gears")
    }.controlSize(.small)
  }
  func limit(_ label:String,key:WritableKeyPath<GearEstimationSettings,Double?>,defaultValue:Double,range:ClosedRange<Double>) -> some View {
    NumberSetting(label,value:Binding(get:{options.wrappedValue[keyPath:key] ?? defaultValue},set:{number in
      guard number.isFinite else { return }; var value = options.wrappedValue; let result = max(range.lowerBound,min(range.upperBound,number)); value[keyPath:key] = result == defaultValue ? nil : result; options.wrappedValue = value
    }))
  }
}
