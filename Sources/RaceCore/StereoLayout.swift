import Foundation

public enum StereoLayout:String,CaseIterable,Identifiable,Sendable {
  case redCyan,greenMagenta,amberBlue,parallel,cross
  public var id:String {rawValue}
  public var title:String {
    switch self {case .redCyan:return "Red / cyan anaglyph";case .greenMagenta:return "Green / magenta anaglyph";case .amberBlue:return "Amber / blue anaglyph";case .parallel:return "Side by side · parallel";case .cross:return "Side by side · cross-eye"}
  }
}
extension RaceProject {
  /// Adds an independent pair above current cameras, below ordinary overlays.
  /// Does not alter source trim/sync, existing displays, export marks or output settings.
  @discardableResult public mutating func addStereoPair(left:Int,right:Int,layout:StereoLayout,convergence:Double = 0) throws -> [UUID] {
    let videos = inputs.filter{$0.kind == "video" && $0.joinedTo == nil && $0.isTimeFiller != true}
    guard left != right,videos.contains(where:{$0.legacyIndex == left}),videos.contains(where:{$0.legacyIndex == right}),
      convergence.isFinite,(-10...10).contains(convergence),sphericalWorkspace != true else {
      throw RaceError.invalid("Choose two distinct independent video streams in a flat workspace and convergence from −10% to 10%.")
    }
    func camera(_ name:String,_ input:Int) -> DisplayObject {
      var o = DisplayObject(name:name,kind:.video);o.inputIndex = input;o.x = 0;o.y = 0;o.width = 100;o.height = 100
      o.picture = PictureSettings();o.picture?.maintainAspect = false;return o
    }
    var l = camera("Stereo · left eye",left),r = camera("Stereo · right eye",right)
    switch layout {
    case .redCyan:l.colorChannels = RGBWriteMask(bits:1);r.colorChannels = RGBWriteMask(bits:6)
    case .greenMagenta:l.colorChannels = RGBWriteMask(bits:2);r.colorChannels = RGBWriteMask(bits:5)
    case .amberBlue:l.colorChannels = RGBWriteMask(bits:3);r.colorChannels = RGBWriteMask(bits:4)
    case .parallel,.cross:
      l.width = 50;r.width = 50;l.x = layout == .parallel ? 0 : 50;r.x = layout == .parallel ? 50 : 0
      l.picture?.maintainAspect = true;r.picture?.maintainAspect = true
    }
    l.x -= convergence/2;r.x += convergence/2
    r.audio = AudioSettings();r.audio?.volume = 0
    let at = objects.firstIndex{![ObjectKind.video,.audio].contains($0.kind)} ?? objects.count
    objects.insert(contentsOf:[r,l],at:at)
    return [l.id,r.id]
  }
}
