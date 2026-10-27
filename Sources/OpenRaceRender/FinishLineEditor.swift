import AppKit
import RaceCore
import SwiftUI
import UniformTypeIdentifiers

extension EditorModel {
  func editFinishLine(_ input:MediaInput) {
    guard input.kind == "data",input.exists,telemetry[input.legacyIndex] != nil else { error = "Load or relink this data source first."; return }
    pause(); finishLineInput = input
  }
}

struct TrackPlotProjection {
  var origin:FinishLine
  var center:CGPoint
  var offset:CGPoint
  var scale:Double
  init(samples:[GPSTrackSample],size:CGSize) {
    let reference = FinishLine(latitude:samples.first?.latitude ?? 0,longitude:samples.first?.longitude ?? 0,heading:0)
    origin = reference
    let points = samples.map{reference.localPosition(latitude:$0.latitude,longitude:$0.longitude)}
    let minX = points.map(\.0).min() ?? 0,maxX = points.map(\.0).max() ?? 1
    let minY = points.map(\.1).min() ?? 0,maxY = points.map(\.1).max() ?? 1
    center = CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
    offset = CGPoint(x:size.width/2,y:size.height/2)
    scale = min(max(1,size.width-50)/max(40,maxX-minX),max(1,size.height-50)/max(40,maxY-minY))
  }
  func point(latitude:Double,longitude:Double) -> CGPoint {
    let p = origin.localPosition(latitude:latitude,longitude:longitude)
    return CGPoint(x:offset.x+(p.0-center.x)*scale,y:offset.y-(p.1-center.y)*scale)
  }
  func coordinate(_ point:CGPoint) -> (latitude:Double,longitude:Double) {
    origin.point(east:center.x+(point.x-offset.x)/scale,north:center.y-(point.y-offset.y)/scale)
  }
}

struct FinishLineMap:View {
  var samples:[GPSTrackSample]
  var line:FinishLine
  var current:GPSTrackSample?
  var active:Bool
  var pick:(Double,Double) -> Void
  var body:some View {
    GeometryReader { geometry in
      let projection = TrackPlotProjection(samples:samples,size:geometry.size)
      Canvas { context,size in
        var path = Path()
        for (i,sample) in samples.enumerated() {
          let point = projection.point(latitude:sample.latitude,longitude:sample.longitude)
          if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
        }
        context.stroke(path,with:.color(.white.opacity(0.8)),style:StrokeStyle(lineWidth:3,lineCap:.round,lineJoin:.round))
        if let current {
          let p = projection.point(latitude:current.latitude,longitude:current.longitude)
          context.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.cyan))
        }
        if active,line.latitude.isFinite,line.longitude.isFinite,line.heading.isFinite,line.width.isFinite,line.width > 0 {
          let theta = line.heading * .pi/180
          let a = line.point(east:cos(theta)*line.width/2,north:-sin(theta)*line.width/2)
          let b = line.point(east:-cos(theta)*line.width/2,north:sin(theta)*line.width/2)
          var gate = Path(); gate.move(to:projection.point(latitude:a.latitude,longitude:a.longitude)); gate.addLine(to:projection.point(latitude:b.latitude,longitude:b.longitude))
          context.stroke(gate,with:.color(.green),lineWidth:4)
          let p = projection.point(latitude:line.latitude,longitude:line.longitude)
          let head = CGPoint(x:p.x+sin(theta)*28,y:p.y-cos(theta)*28)
          var arrow = Path(); arrow.move(to:p); arrow.addLine(to:head)
          arrow.move(to:CGPoint(x:head.x-sin(theta+0.5)*10,y:head.y+cos(theta+0.5)*10)); arrow.addLine(to:head)
          arrow.addLine(to:CGPoint(x:head.x-sin(theta-0.5)*10,y:head.y+cos(theta-0.5)*10))
          context.stroke(arrow,with:.color(.green),lineWidth:2)
          context.draw(Text("⚑").font(.title2).foregroundStyle(.green),at:CGPoint(x:p.x,y:p.y-12))
        }
      }.background(Color.black.opacity(0.5)).clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:0).onEnded { value in
          let p = projection.coordinate(value.location); pick(p.latitude,p.longitude)
        })
    }
  }
}

struct FinishLineEditor:View {
  @ObservedObject var model:EditorModel
  var input:MediaInput
  let request:DataSetupRequest
  let data:Telemetry?
  let samples:[GPSTrackSample]
  @Environment(\.dismiss) private var dismiss
  @State private var line:FinishLine
  @State private var custom = true
  @State private var sourceTime:Double
  @State private var positionMode = "cursor"
  @State private var autoHeading:Bool
  @State private var snap = true
  @State private var ignore:Int
  @State private var preview:DataSetupPreview?
  @State private var loading = false
  @State private var failure:String?
  @State private var library = TrackLibrary()
  @State private var libraryError:String?
  @State private var libraryWritable = true
  @State private var trackName = ""
  @State private var selectedTrack:UUID?
  @State private var search = ""
  @State private var showAllTracks = false
  init(model:EditorModel,input:MediaInput) {
    self.model = model; self.input = input
    let source = model.telemetry[input.legacyIndex]; data = source; samples = source?.gpsTrackSamples() ?? []
    request = DataSetupRequest(url:URL(fileURLWithPath:input.path),headers:source?.recordedHeaders ?? [],revision:model.documentRevision,original:input)
    let time = max(0,min(source?.duration ?? 0,model.sourceTimeAtPlayhead(input) ?? 0))
    _sourceTime = State(initialValue:time)
    let first = samples.first
    _line = State(initialValue:input.dataSettings?.finishLine ?? source?.finishLine(at:time) ?? FinishLine(latitude:first?.latitude ?? 0,longitude:first?.longitude ?? 0,heading:0))
    _positionMode = State(initialValue:input.dataSettings?.finishLine == nil ? "cursor" : "coordinates")
    _autoHeading = State(initialValue:input.dataSettings?.finishLine == nil)
    _ignore = State(initialValue:input.dataSettings?.ignoreLapTriggers ?? 0)
    _trackName = State(initialValue:input.dataSettings?.locationName ?? source?.locationName ?? "")
  }
  var settings:DataSettings {
    var value = input.dataSettings ?? DataSettings(); value.finishLine = custom ? line : nil
    let original = input.dataSettings?.locationName ?? data?.locationName ?? ""
    if custom,(selectedTrack != nil || trackName != original),!trackName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {value.locationName = trackName.trimmingCharacters(in:.whitespacesAndNewlines)}
    value.ignoreLapTriggers = ignore == 0 ? nil : ignore; return value
  }
  var current:GPSTrackSample? {
    guard let lat = data?.value("lat",at:sourceTime),let lon = data?.value("lon",at:sourceTime) else { return nil }
    return GPSTrackSample(time:sourceTime,latitude:lat,longitude:lon)
  }
  var savedTracks:[SavedTrack] {
    let nearby = samples.first.map{library.nearby(latitude:$0.latitude,longitude:$0.longitude).map(\.track)} ?? []
    return (showAllTracks ? library.tracks.sorted{$0.name < $1.name} : nearby)
      .filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("GPS start / finish · " + input.name).font(.title2.bold())
      Text("Place the gate on an average driving line. Preview detected laps before applying.").foregroundStyle(.secondary)
      HStack(alignment:.top,spacing:18) {
        VStack(alignment:.leading,spacing:10) {
          FinishLineMap(samples:samples,line:line,current:current,active:custom,pick:pickPosition).frame(height:360)
          if samples.isEmpty { Text("No decimal GPS coordinates. Assign latitude/longitude columns first.").foregroundStyle(.orange) }
          Toggle("Snap map clicks to recorded track",isOn:$snap)
          Slider(value:$sourceTime,in:0...max(0.001,data?.duration ?? input.duration))
          HStack {
            TextField("Source seconds",value:$sourceTime,format:.number.precision(.fractionLength(0...6))).frame(width:100)
            Button("−1 s") { sourceTime = max(0,sourceTime-1) }
            Button("+1 s") { sourceTime = min(data?.duration ?? input.duration,sourceTime+1) }
            Button("Use playhead") { sourceTime = max(0,min(data?.duration ?? 0,model.sourceTimeAtPlayhead(input) ?? 0)); positionMode = "cursor"; useCursor() }
          }
          lapPreview
        }.frame(width:450)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          lineControls
          Divider()
          trackControls
        }.padding(.trailing,8) }.frame(width:340)
      }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled).lineLimit(3) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(loading ? "Calculating…" : "Preview laps") { Task { await loadPreview() } }.disabled(loading || (custom && samples.isEmpty))
        Spacer()
        Button("Apply") {
          if let preview,preview.settings == settings,model.applyDataSetup(request,preview:preview) { dismiss() }
          else { failure = "The source or document changed. Reopen this editor and preview again." }
        }.keyboardShortcut(.defaultAction).disabled(preview == nil || loading)
      }
    }.padding(20).frame(width:850,height:760)
      .onChange(of:settings) { _,_ in preview = nil; failure = nil }
      .onChange(of:sourceTime) { _,value in
        let valid = value.isFinite ? min(data?.duration ?? input.duration,max(0,value)) : 0
        if valid != value { sourceTime = valid }
        else if positionMode == "cursor" { useCursor() }
      }
      .onChange(of:line.latitude) { _,_ in if autoHeading && positionMode == "coordinates" { inferHeading() } }
      .onChange(of:line.longitude) { _,_ in if autoHeading && positionMode == "coordinates" { inferHeading() } }
      .onChange(of:positionMode) { _,mode in if mode == "cursor" { useCursor() } }
      .onChange(of:autoHeading) { _,enabled in if enabled { inferHeading() } }
      .task { loadLibrary(); await loadPreview() }
  }
  var lineControls:some View {
    VStack(alignment:.leading,spacing:10) {
      Toggle("Override recorded laps with this gate",isOn:$custom)
      Picker("Position",selection:$positionMode) { Text("Source cursor").tag("cursor"); Text("Coordinates").tag("coordinates") }
      coordinateField("Latitude (degrees)",$line.latitude).disabled(positionMode == "cursor")
      coordinateField("Longitude (degrees)",$line.longitude).disabled(positionMode == "cursor")
      NumberSetting("Gate width (m)",value:$line.width)
      Toggle("Infer heading from GPS motion",isOn:$autoHeading)
      NumberSetting("Forward heading (° from north)",value:$line.heading).disabled(autoHeading)
      Toggle("Restrict crossing heading",isOn:Binding(get:{line.headingTolerance != nil},set:{line.headingTolerance = $0 ? 60 : nil}))
      if line.headingTolerance != nil {
        NumberSetting("Heading tolerance (°)",value:Binding(get:{line.headingTolerance ?? 60},set:{line.headingTolerance = $0}))
      }
      Toggle("Additional coordinate tolerances",isOn:Binding(get:{line.eastTolerance != nil || line.northTolerance != nil},set:{
        line.eastTolerance = $0 ? line.width/2 : nil; line.northTolerance = $0 ? line.width/2 : nil
      }))
      if line.eastTolerance != nil || line.northTolerance != nil {
        NumberSetting("East / west tolerance (m)",value:Binding(get:{line.eastTolerance ?? line.width/2},set:{line.eastTolerance = $0}))
        NumberSetting("North / south tolerance (m)",value:Binding(get:{line.northTolerance ?? line.width/2},set:{line.northTolerance = $0}))
      }
      NumberSetting("Minimum lap time (s)",value:$line.minimumLap)
      HStack { Text("Ignore first lap triggers"); Spacer(); TextField("Triggers",value:$ignore,format:.number).frame(width:82) }
      Picker("Precision",selection:Binding(get:{line.precision ?? .interpolated},set:{line.precision = $0})) {
        ForEach(LapTimingPrecision.allCases,id:\.rawValue){Text($0.title).tag($0)}
      }
      Text("Interpolated mode estimates the crossing between GPS samples. Sample mode uses the next sample and applies tolerances there; it may miss a gate when samples jump past it. GPS timing is approximate.").font(.caption).foregroundStyle(.secondary)
    }
  }
  func coordinateField(_ title:String,_ value:Binding<Double>) -> some View {
    HStack { Text(title); Spacer(); TextField(title,value:value,format:.number.precision(.fractionLength(0...8))).frame(width:150).accessibilityLabel(title) }
  }
  var lapPreview:some View {
    VStack(alignment:.leading,spacing:5) {
      if let preview {
        Text("\(preview.data.laps.filter(\.complete).count) complete laps · \(preview.data.laps.count) intervals").font(.headline)
        ScrollView {
          LazyVStack(alignment:.leading,spacing:3) {
            ForEach(Array(preview.data.laps.enumerated()),id:\.offset) { _,lap in
              Button("\(lap.complete ? "Lap" : "Partial") \(lap.number): \(clockText(lap.start)) → \(clockText(lap.end)) · \(String(format:"%.3f s",lap.duration))") {
                positionMode = "coordinates"; sourceTime = lap.start
              }.buttonStyle(.plain).font(.caption.monospacedDigit())
            }
          }
        }.frame(height:95)
      } else { Text("Preview required after changing gate settings.").font(.caption).foregroundStyle(.secondary) }
    }
  }
  var trackControls:some View {
    VStack(alignment:.leading,spacing:8) {
      Text("Saved track library").font(.headline)
      TextField("Search saved tracks",text:$search)
      Toggle("Show all saved tracks (otherwise within 50 km)",isOn:$showAllTracks)
      Picker("Load track",selection:$selectedTrack) {
        Text("Choose a saved finish line").tag(nil as UUID?)
        ForEach(savedTracks) { Text($0.name).tag(Optional($0.id)) }
      }.onChange(of:selectedTrack) { _,id in
        guard let track = library.tracks.first(where:{$0.id == id}) else { return }
        line = track.finishLine; custom = true; autoHeading = false; positionMode = "coordinates"; trackName = track.name
      }
      if savedTracks.isEmpty { Text("No matching saved tracks. Save a gate or import a portable track library.").font(.caption).foregroundStyle(.secondary) }
      TextField("Track / layout name",text:$trackName)
      Button("Save gate as new track") { saveTrack() }.disabled(!custom || !libraryWritable)
      HStack {
        Button("Import…",action:importTracks).disabled(!libraryWritable)
        Button("Export…",action:exportTracks).disabled(library.tracks.isEmpty)
        Button("Remove",role:.destructive,action:removeTrack).disabled(selectedTrack == nil || !libraryWritable)
      }
      Text("Stored in ~/Library/Application Support/OpenRaceRender/Tracks.json. This independent library starts empty; import/export uses .orrtracks JSON. Saving the library is separate from applying project edits.").font(.caption).foregroundStyle(.secondary)
      if let libraryError { Text(libraryError).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
    }
  }
  func useCursor() {
    guard let current else { failure = "No GPS position at this source time."; return }
    line.latitude = current.latitude; line.longitude = current.longitude
    if autoHeading {
      if let heading = data?.finishLine(at:sourceTime)?.heading { line.heading = heading }
      else { failure = "Move to a GPS sample with motion or enter the heading manually." }
    }
  }
  func inferHeading() {
    guard let nearest = samples.min(by:{distance($0,line.latitude,line.longitude) < distance($1,line.latitude,line.longitude)}),
      let heading = data?.finishLine(at:nearest.time)?.heading else { failure = "Move to a GPS sample with motion or enter the heading manually."; return }
    line.heading = heading
  }
  func distance(_ sample:GPSTrackSample,_ latitude:Double,_ longitude:Double) -> Double {
    Telemetry.distance(lat1:latitude,lon1:longitude,lat2:sample.latitude,lon2:sample.longitude)
  }
  func pickPosition(_ latitude:Double,_ longitude:Double) {
    guard custom else { return }
    if snap,let nearest = samples.min(by:{distance($0,latitude,longitude) < distance($1,latitude,longitude)}) {
      sourceTime = nearest.time; positionMode = "cursor"; useCursor()
    } else {
      positionMode = "coordinates"; line.latitude = latitude; line.longitude = longitude
      if autoHeading { inferHeading() }
    }
  }
  func loadPreview() async {
    loading = true; preview = nil; failure = nil; let snapshot = settings
    defer { loading = false }
    do {
      guard !custom || !samples.isEmpty else { throw RaceError.invalid("Assign decimal latitude/longitude before setting a GPS gate.") }
      let value = try await DataSetupPreview.load(request.url,settings:snapshot)
      if !Task.isCancelled,snapshot == settings { preview = value }
    } catch { if snapshot == settings { failure = error.localizedDescription } }
  }
  func loadLibrary() {
    let url = TrackLibrary.userURL()
    guard FileManager.default.fileExists(atPath:url.path) else { return }
    do { library = try TrackLibrary.read(url) }
    catch { libraryWritable = false; libraryError = "The existing track library could not be read and will be preserved. " + error.localizedDescription }
  }
  func persist(_ value:TrackLibrary) {
    guard libraryWritable else { return }
    do { try value.save(TrackLibrary.userURL()); library = value; libraryError = nil }
    catch { libraryError = error.localizedDescription }
  }
  func saveTrack() {
    var value = library; value.tracks.append(SavedTrack(name:trackName,finishLine:line)); persist(value)
  }
  func removeTrack() {
    var value = library; value.tracks.removeAll{$0.id == selectedTrack}; persist(value); selectedTrack = nil
  }
  func importTracks() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.data]
    panel.message = "Choose an OpenRaceRender .orrtracks JSON library. Existing tracks are preserved."
    guard panel.runModal() == .OK,let url = panel.url else { return }
    do { persist(try library.merging(TrackLibrary.read(url))) } catch { libraryError = error.localizedDescription }
  }
  func exportTracks() {
    let panel = NSSavePanel(); panel.nameFieldStringValue = "Tracks.orrtracks"
    panel.allowedContentTypes = [UTType(exportedAs:"org.openracerender.tracks",conformingTo:.json)]
    guard panel.runModal() == .OK,let url = panel.url else { return }
    do { try library.save(url) } catch { libraryError = error.localizedDescription }
  }
}
