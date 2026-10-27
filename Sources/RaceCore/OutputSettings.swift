import Foundation
import CoreGraphics

public struct OutputSettings:Codable,Equatable,Sendable {
  public enum Workspace:String,Codable,CaseIterable,Sendable { case fitCanvas,output }
  public var width:Int?
  public var height:Int?
  public var fps:Double?
  public var workspace:Workspace = .fitCanvas
  /// Fraction of the output width/height reserved on each side.
  public var border:Double = 0
  public var scaling:RenderOptions.Scaling = .high
  public var audioChannels:Int = 2
  public var audioSampleRate:Int = 48000
  public init() {}
  public func size(for project:RaceProject) -> CGSize { CGSize(width:width ?? project.width,height:height ?? project.height) }
  public func validate(project:RaceProject) throws {
    let w = width ?? project.width,h = height ?? project.height,rate = fps ?? project.fps
    guard (2...7680).contains(w),(2...4320).contains(h),w%2 == 0,h%2 == 0,rate.isFinite,rate > 0,rate <= 120,
      border.isFinite,(0...0.2).contains(border),[0,1,2].contains(audioChannels),[44100,48000].contains(audioSampleRate) else {
      throw RaceError.invalid("Output needs even dimensions up to 7680×4320, 0–20% border, 1–120 fps, mono/stereo/disabled audio and 44100/48000 Hz.")
    }
  }
  public func renderOptions(project:RaceProject) throws -> RenderOptions {
    try validate(project:project)
    var result = RenderOptions(); result.size = size(for:project); result.fps = fps ?? project.fps; result.scaling = scaling
    result.fitCanvas = workspace == .fitCanvas; result.border = border
    result.audio = audioChannels == 0 ? .disabled : .stereo
    return result
  }
}

/// Independent distribution presets, not proprietary RaceRender preference files.
public struct OutputProfile:Codable,Equatable,Identifiable,Sendable {
  public var id:String
  public var name:String
  public var settings:ExportSettings
  public init(id:String = UUID().uuidString,name:String,settings:ExportSettings) {self.id = id;self.name = name;self.settings = settings}
  public static let builtins:[OutputProfile] = {
    func make(_ id:String,_ name:String,_ width:Int,_ height:Int,_ bitrate:Int,_ border:Double = 0) -> OutputProfile {
      var output = OutputSettings(); output.width = width; output.height = height; output.fps = 30; output.border = border
      var settings = ExportSettings(videoBitRate:bitrate); settings.output = output
      return OutputProfile(id:id,name:name,settings:settings)
    }
    return [make("local-4k","Local file · 4K30",3840,2160,50_000_000),
      make("local-1080","Local file · 1080p30",1920,1080,20_000_000),
      make("internet-1080","Internet · 1080p30",1920,1080,8_000_000),
      make("internet-720","Internet · 720p30",1280,720,5_000_000),
      make("television-1080","Television · 1080p30 / 5% border",1920,1080,20_000_000,0.05)]
  }()
}
