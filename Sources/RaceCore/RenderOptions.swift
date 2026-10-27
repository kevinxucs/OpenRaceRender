import CoreGraphics
import Foundation

/// Per-preparation controls. The scene keeps its original canvas and script clock.
public struct RenderOptions:Equatable,Sendable {
  public enum Scaling:String,Codable,CaseIterable,Sendable { case high,linear,nearest }
  public enum Audio:String,Codable,CaseIterable,Sendable { case stereo,mono,disabled }
  public var size:CGSize?
  public var fps:Double?
  public var scaling:Scaling = .high
  public var audio:Audio = .stereo
  public var audioSampleRate:Int = 0
  public var audioBits:Int = 0
  public var fitCanvas = false
  public var border:Double = 0
  public init() {}
  public func validate() throws {
    if let size { guard size.width.isFinite,size.height.isFinite,size.width >= 2,size.height >= 2,size.width <= 7680,size.height <= 4320 else { throw RaceError.invalid("Invalid render dimensions.") } }
    if let fps { guard fps.isFinite,fps > 0,fps <= 120 else { throw RaceError.invalid("Invalid render frame rate.") } }
    guard [0,22050,44100,48000].contains(audioSampleRate),[0,8,16].contains(audioBits) else { throw RaceError.invalid("Invalid preview audio quality.") }
    guard border.isFinite,(0...0.2).contains(border) else { throw RaceError.invalid("Invalid output border.") }
  }
  public func viewport(project:RaceProject,size:CGSize) -> CGRect {
    let inset = CGRect(origin:.zero,size:size).insetBy(dx:size.width*border,dy:size.height*border)
    guard fitCanvas else { return inset }
    let scale = min(inset.width/Double(max(1,project.width)),inset.height/Double(max(1,project.height)))
    let width = Double(project.width)*scale,height = Double(project.height)*scale
    return CGRect(x:inset.midX-width/2,y:inset.midY-height/2,width:width,height:height)
  }
}

public struct PreviewSettings:Codable,Equatable,Sendable {
  /// Zero follows the original project size/rate; defaults favor interactive playback.
  public var height:Int = 720
  public var fps:Int = 30
  public var scaling:RenderOptions.Scaling = .high
  public var reduceWhileSeeking = true
  public var audio:RenderOptions.Audio = .stereo
  public var audioSampleRate:Int = 0
  public var audioBits:Int = 0
  public init() {}
  public func validate() throws {
    guard [0,180,360,540,720,1080,1440,2160].contains(height),[0,15,24,30,60].contains(fps) else { throw RaceError.invalid("Invalid preview size/frame rate.") }
    var value = RenderOptions(); value.audioSampleRate = audioSampleRate; value.audioBits = audioBits; try value.validate()
  }
  public func options(for project:RaceProject,seeking:Bool = false) -> RenderOptions {
    var settings = self
    if (try? validate()) == nil { settings = PreviewSettings() }
    let reduced = seeking && settings.reduceWhileSeeking
    let cap = reduced ? min(360,settings.height == 0 ? project.height : settings.height) : settings.height
    let scale = cap > 0 ? min(1,Double(cap)/Double(max(1,project.height))) : 1
    func even(_ value:Double) -> Double { max(2,(value/2).rounded()*2) }
    var value = RenderOptions()
    value.size = CGSize(width:even(Double(project.width)*scale),height:even(Double(project.height)*scale))
    value.fps = min(project.fps,Double(reduced ? min(15,settings.fps == 0 ? 15 : settings.fps) : settings.fps == 0 ? 120 : settings.fps))
    value.scaling = reduced ? .nearest : settings.scaling
    value.audio = settings.audio; value.audioSampleRate = settings.audioSampleRate; value.audioBits = settings.audioBits
    return value
  }
}
