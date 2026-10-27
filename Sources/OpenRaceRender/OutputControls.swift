import RaceCore
import SwiftUI

extension EditorModel {
  var outputProfiles:[OutputProfile] { OutputProfile.builtins+customOutputProfiles }
  func applyOutputProfile(_ profile:OutputProfile) {
    do {
      try profile.settings.validate(project:project)
      var settings = profile.settings; settings.profileID = profile.id
      guard project.exportSettings != settings else { return }
      checkpoint(); project.exportSettings = settings
    } catch { self.error = error.localizedDescription }
  }
  func outputBinding<Value:Equatable>(_ key:WritableKeyPath<OutputSettings,Value>) -> Binding<Value> {
    Binding(get:{(self.project.exportSettings?.output ?? OutputSettings())[keyPath:key]},set:{value in
      var settings = self.project.exportSettings ?? ExportSettings(),output = self.project.exportSettings?.output ?? OutputSettings()
      guard output[keyPath:key] != value else { return }
      output[keyPath:key] = value; settings.output = output; settings.profileID = nil
      self.checkpoint(); self.project.exportSettings = settings
    })
  }
  func setOutputSize(width:Int?,height:Int?) {
    guard width.map({(2...7680).contains($0)}) ?? true,height.map({(2...4320).contains($0)}) ?? true else { error = "Output dimensions must be 2–7680 × 2–4320 pixels."; return }
    var settings = project.exportSettings ?? ExportSettings(),output = project.exportSettings?.output ?? OutputSettings()
    guard output.width != width || output.height != height else { return }
    output.width = width; output.height = height; settings.output = output; settings.profileID = nil
    checkpoint(); project.exportSettings = settings
  }
  func saveOutputProfile(name:String) {
    let name = name.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !name.isEmpty,name.count <= 100 else { error = "Name the profile with 1–100 characters."; return }
    var settings = project.exportSettings ?? ExportSettings(); settings.profileID = nil
    do {try settings.validate(project:project)} catch {self.error = error.localizedDescription; return}
    var profiles = customOutputProfiles
    let existing = profiles.firstIndex{$0.name.caseInsensitiveCompare(name) == .orderedSame}
    let profile = OutputProfile(id:existing.map{profiles[$0].id} ?? UUID().uuidString,name:name,settings:settings)
    if let existing {profiles[existing] = profile} else {profiles.append(profile)}
    customOutputProfiles = profiles; storeOutputProfiles(); applyOutputProfile(profile)
  }
  func removeOutputProfile(_ id:String) {
    customOutputProfiles.removeAll{$0.id == id}; storeOutputProfiles()
  }
  private func storeOutputProfiles() { if let data = try? JSONEncoder().encode(customOutputProfiles) {preferences.set(data,forKey:"outputProfiles")} }
}

struct OutputProfileControls:View {
  @ObservedObject var model:EditorModel
  @State var name = ""
  var selectedID:String { model.outputProfiles.contains{$0.id == model.project.exportSettings?.profileID} ? model.project.exportSettings?.profileID ?? "" : "" }
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      Picker("Output profile",selection:Binding(get:{selectedID},set:{id in if let profile = model.outputProfiles.first(where:{$0.id == id}) {model.applyOutputProfile(profile)}})) {
        Text("Custom / current settings").tag("")
        ForEach(model.outputProfiles) { Text($0.name).tag($0.id) }
      }
      HStack {
        TextField("Name this configuration",text:$name)
        Button("Save / update profile") { model.saveOutputProfile(name:name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        if model.customOutputProfiles.contains(where:{$0.id == selectedID}) {Button("Remove") {model.removeOutputProfile(selectedID)}}
      }
      Text("Profiles set output size/FPS, compression, border, scaling and audio. Custom profiles are saved on this Mac; applied settings travel with the project.").font(.caption).foregroundStyle(muted)
    }
  }
}

enum OutputAspect:String,CaseIterable {
  case wide = "16:9",classic = "4:3",square = "1:1",portrait = "9:16",cinema = "21:9"
  var ratio:Double {switch self {case .wide:return 16.0/9;case .classic:return 4.0/3;case .square:return 1;case .portrait:return 9.0/16;case .cinema:return 21.0/9}}
}
struct OutputGeometryControls:View {
  @ObservedObject var model:EditorModel
  var output:OutputSettings {model.project.exportSettings?.output ?? OutputSettings()}
  var size:CGSize {CGSize(width:min(7680,max(2,output.width ?? model.project.width)),height:min(4320,max(2,output.height ?? model.project.height)))}
  var aspect:Double {size.width/max(1,size.height)}
  func setHeight(_ height:Int) {model.setOutputSize(width:max(2,Int((Double(height)*aspect/2).rounded())*2),height:height)}
  func setAspect(_ aspect:OutputAspect) {
    let height = Int(size.height),width = max(2,Int((Double(height)*aspect.ratio/2).rounded())*2)
    model.setOutputSize(width:width,height:height)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      HStack {
        Menu("Aspect / workspace") {
          Button("Match project canvas") {model.setOutputSize(width:nil,height:nil)}
          ForEach(OutputAspect.allCases,id:\.self) { value in
            Button(value.rawValue) {setAspect(value)}
          }
        }
        Menu("Picture height") {
          ForEach([360,480,720,1080,1440,2160],id:\.self) {height in Button("\(height) px") {setHeight(height)}}
        }
      }
      HStack {
        Text("Width"); TextField("Width",value:Binding(get:{Int(size.width)},set:{model.setOutputSize(width:$0,height:Int(size.height))}),format:.number)
        Text("Height"); TextField("Height",value:Binding(get:{Int(size.height)},set:{model.setOutputSize(width:Int(size.width),height:$0)}),format:.number)
      }
      Picker("Layout",selection:model.outputBinding(\.workspace)) {
        Text("Fit original canvas (letterbox)").tag(OutputSettings.Workspace.fitCanvas)
        Text("Use output proportions (reshape layout)").tag(OutputSettings.Workspace.output)
      }
      if abs(aspect-Double(model.project.width)/Double(max(1,model.project.height))) > 0.005 {
        Text(output.workspace == .fitCanvas ? "The entire original composition fits inside the output with black bars." : "The layout uses the output aspect. Widget proportions/positions can differ from the main preview.").font(.caption).foregroundStyle(.orange)
      }
      Picker("Frame rate",selection:Binding(get:{output.fps ?? model.project.fps},set:{model.outputBinding(\.fps).wrappedValue = $0})) {
        ForEach(Array(Set([5.0,10,15,24,25,30000.0/1001,30,50,60000.0/1001,60,120,output.fps ?? model.project.fps])).sorted(),id:\.self) {Text("\($0.formatted()) fps").tag($0)}
      }
      HStack {Text("Outer border (%) per side"); TextField("Border",value:Binding(get:{output.border*100},set:{model.outputBinding(\.border).wrappedValue = $0/100}),format:.number)}
      Picker("Scaling",selection:model.outputBinding(\.scaling)) {
        Text("High (Lanczos)").tag(RenderOptions.Scaling.high); Text("Linear").tag(RenderOptions.Scaling.linear); Text("Minimal (nearest)").tag(RenderOptions.Scaling.nearest)
      }
    }
  }
}

struct OutputEncodingControls:View {
  @ObservedObject var model:EditorModel
  var settings:ExportSettings {model.project.exportSettings ?? ExportSettings()}
  func rate(_ audio:Bool) -> Binding<Int> {
    Binding(get:{audio ? settings.audioBitRate/1000 : (settings.videoBitRate ?? 0)/1000},set:{value in
      // Bound before multiplication so arbitrary numeric entry cannot overflow.
      guard (0...240000).contains(value) else {model.error = "Use 0–240000 kbps."; return}
      var edited = settings
      if audio {edited.audioBitRate = value*1000} else {edited.videoBitRate = value == 0 ? nil : value*1000}
      guard edited != settings else {return}; edited.profileID = nil; model.checkpoint(); model.project.exportSettings = edited
    })
  }
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      HStack {Text("Video bitrate (kbps)"); TextField("Automatic",value:rate(false),format:.number)}
      Text("0 selects an automatic quality-oriented rate for the output size/FPS. H.264 High Profile / Rec.709.").font(.caption).foregroundStyle(muted)
      Picker("Audio channels",selection:model.outputBinding(\.audioChannels)) {Text("Stereo / 16-bit PCM to AAC").tag(2);Text("Mono / 16-bit PCM to AAC").tag(1);Text("No audio").tag(0)}
      Picker("Audio sample rate",selection:model.outputBinding(\.audioSampleRate)) {Text("48000 Hz").tag(48000);Text("44100 Hz").tag(44100)}
      HStack {Text("AAC bitrate (kbps)"); TextField("Audio bitrate",value:rate(true),format:.number)}
    }
  }
}
