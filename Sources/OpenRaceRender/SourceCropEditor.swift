import AppKit
import RaceCore
import SwiftUI

struct SourceCropEditor: View {
  @ObservedObject var model:EditorModel
  @Binding var input:MediaInput
  @Environment(\.dismiss) var dismiss
  @State private var metadata:SourceMetadata?
  @State private var selection:CropSelection?
  @State private var time:Double = 0
  @State private var moveSelection = false
  @State private var nudge:Double = 1
  @State private var error:String?
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Crop source · \(input.name)").font(.title2)
      Text("Crop in source pixels. Picture color, rotation and synchronization settings are preserved; project export marks are unchanged.").font(.caption).foregroundStyle(.secondary)
      if let meta = metadata, let crop = selection {
        HStack(alignment:.top,spacing:16) {
          VStack(spacing:8) {
            ZStack {
              SourceThumbnail(input:input,time:time,data:nil)
              CropCanvas(selection:Binding(get:{selection ?? crop},set:{selection = $0}),move:moveSelection)
            }.frame(width:600,height:340)
            Toggle("Drag to move selection (off: draw a new crop)",isOn:$moveSelection)
            if input.kind == "video" {
              Slider(value:$time,in:0...max(0.001,meta.duration-1/meta.fps)).accessibilityLabel("Crop source preview time")
              HStack {
                Button("−1 frame") { time = max(0,time-1/meta.fps) }
                Button("+1 frame") { time = min(max(0,meta.duration-1/meta.fps),time+1/meta.fps) }
                Button("Use playhead") {
                  if let source = model.sourceTimeAtPlayhead(input) { time = max(0,min(meta.duration-1/meta.fps,source)) }
                  else { error = "This physical input is inactive at the playhead. Choose a source time or move the playhead." }
                }
                Text(clockText(time)).font(.system(.caption,design:.monospaced))
              }.controlSize(.small)
            }
          }
          VStack(alignment:.leading,spacing:10) {
            Text("Cropped result").font(.headline)
            SourceThumbnail(input:input,time:time,data:nil,picture:crop.picture(from:input.picture)).frame(width:240,height:135)
            Text("Source: \(Int(meta.size.width)) × \(Int(meta.size.height))\nSelection: \(Int(crop.rect.width)) × \(Int(crop.rect.height)) pixels")
              .font(.system(size:11,design:.monospaced))
            pixel("Left",value:crop.left) { selection?.edges(left:$0) }
            pixel("Right",value:crop.right) { selection?.edges(right:$0) }
            pixel("Top",value:crop.top) { selection?.edges(top:$0) }
            pixel("Bottom",value:crop.bottom) { selection?.edges(bottom:$0) }
            NumberSetting("Nudge pixels",value:$nudge)
            HStack {
              Button("←") { selection?.nudge(x:-abs(nudge),y:0) }
              Button("→") { selection?.nudge(x:abs(nudge),y:0) }
              Button("↑") { selection?.nudge(x:0,y:-abs(nudge)) }
              Button("↓") { selection?.nudge(x:0,y:abs(nudge)) }
            }
            HStack {
              Button("Zoom in") { selection?.zoom(1.1) }
              Button("Zoom out") { selection?.zoom(1/1.1) }
            }
            Button("Reset full frame") { selection = CropSelection(size:meta.size) }
          }.frame(width:240).controlSize(.small)
        }
      } else { ProgressView("Reading source dimensions…").frame(height:340) }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") { apply() }.disabled(selection == nil).keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width:900).textFieldStyle(.roundedBorder).task {
      do {
        let meta = try await SourceMetadata.load(input,data:nil,fps:model.project.fps)
        guard !Task.isCancelled else { return }
        metadata = meta; selection = CropSelection(size:meta.size,picture:input.picture)
        time = max(0,min(max(0,meta.duration-1/meta.fps),model.sourceTimeAtPlayhead(input) ?? 0))
      } catch { self.error = error.localizedDescription }
    }
  }
  func pixel(_ title:String,value:Double,set:@escaping(Double)->Void) -> some View {
    NumberSetting(title+" pixels",value:Binding(get:{value},set:set))
  }
  func apply() {
    guard let selection else { return }
    var updated = input
    let picture = selection.picture(from:input.picture)
    updated.picture = input.picture == nil && picture == PictureSettings() ? nil : picture
    input = updated; dismiss()
  }
}

struct CropCanvas: View {
  @Binding var selection:CropSelection
  var move:Bool
  @State private var original:CropSelection?
  @State private var corner:Int?
  var body:some View {
    GeometryReader { g in
      let fit = CropSelection.fit(selection.sourceSize,in:g.size)
      let r = CGRect(x:fit.minX+selection.rect.minX/selection.sourceSize.width*fit.width,
        y:fit.minY+selection.rect.minY/selection.sourceSize.height*fit.height,
        width:selection.rect.width/selection.sourceSize.width*fit.width,
        height:selection.rect.height/selection.sourceSize.height*fit.height)
      ZStack {
        Path { p in p.addRect(fit); p.addRect(r) }.fill(.black.opacity(0.5),style:FillStyle(eoFill:true))
        Path(r).stroke(mint,lineWidth:2)
        ForEach(0..<4,id:\.self) { i in
          Rectangle().fill(mint).frame(width:6,height:6)
            .position(x:i%2 == 0 ? r.minX : r.maxX,y:i<2 ? r.minY : r.maxY)
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { v in
        if original == nil {
          original = selection
          let corners = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.maxY)]
          corner = corners.indices.min(by:{hypot(corners[$0].x-v.startLocation.x,corners[$0].y-v.startLocation.y)<hypot(corners[$1].x-v.startLocation.x,corners[$1].y-v.startLocation.y)})
          if let index = corner, hypot(corners[index].x-v.startLocation.x,corners[index].y-v.startLocation.y) > 10 { corner = nil }
        }
        if let corner, let initial = original {
          let x = corner%2 == 0 ? initial.rect.maxX : initial.rect.minX
          let y = corner<2 ? initial.rect.maxY : initial.rect.minY
          let anchor = CGPoint(x:fit.minX+x/initial.sourceSize.width*fit.width,y:fit.minY+y/initial.sourceSize.height*fit.height)
          selection.drag(from:anchor,to:v.location,imageRect:fit)
        } else if move, var initial = original {
          initial.nudge(x:v.translation.width/max(1,fit.width)*initial.sourceSize.width,
            y:v.translation.height/max(1,fit.height)*initial.sourceSize.height)
          selection = initial
        } else { selection.drag(from:v.startLocation,to:v.location,imageRect:fit) }
      }.onEnded { _ in original = nil; corner = nil })
    }.accessibilityLabel("Source crop rectangle; drag to draw or move")
  }
}
