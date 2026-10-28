import Foundation

public enum DiagnosticKind:String,Codable,Sendable {
  case launch,cleanExit,projectOpened,projectSaved,projectFailed,telemetryReady,telemetryFailed,previewPreparing,previewReady,previewFailed,exportStarted,exportCompleted,exportFailed,recoverySaved,recoveryRestored,recoveryFailed
}
public enum DiagnosticMetric:String,Codable,Sendable {case inputs,displays,samples,width,height,fps,duration,elapsed}
public struct DiagnosticEntry:Codable,Equatable,Sendable {
  public var time:Date
  public var kind:DiagnosticKind
  public var metrics:[String:Double]
  public var errorDomain:String?
  public var errorCode:Int?
}
/// Only typed event names, numeric metrics and error domain/code are accepted.
/// Paths, project names/content, telemetry rows, raw errors and credentials never enter the journal.
public final class DiagnosticLog:@unchecked Sendable {
  public let file:URL?
  public let capacity:Int
  private let lock = NSLock()
  private let queue = DispatchQueue(label:"org.openracerender.diagnostics",qos:.utility)
  private var items:[DiagnosticEntry] = []
  private var pending:DispatchWorkItem?
  public init(file:URL? = nil,capacity:Int = 1000) {
    self.file = file;self.capacity = max(1,min(10000,capacity))
    if let file,let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 4*1024*1024,
      let data = try? Data(contentsOf:file),let old = try? JSONDecoder().decode([DiagnosticEntry].self,from:data) {items = Array(old.suffix(self.capacity)).map {entry in
        var entry = entry;entry.metrics = entry.metrics.filter{DiagnosticMetric(rawValue:$0.key) != nil && $0.value.isFinite}
        if let domain = entry.errorDomain,!Self.allowedDomains.contains(domain) {entry.errorDomain = "OtherError"};return entry
      }}
  }
  private static let allowedDomains = [NSCocoaErrorDomain,NSURLErrorDomain,NSPOSIXErrorDomain,NSOSStatusErrorDomain,"AVFoundationErrorDomain","kCFErrorDomainCFNetwork","RaceCore.RaceError"]
  public static var defaultFile:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenRaceRender/Diagnostics/events.json")}
  public func record(_ kind:DiagnosticKind,metrics:[DiagnosticMetric:Double] = [:],error:Error? = nil) {
    var domain:String?,code:Int?
    if let error {let value = error as NSError;code = value.code
      domain = Self.allowedDomains.contains(value.domain) ? value.domain : "OtherError"
    }
    let entry = DiagnosticEntry(time:Date(),kind:kind,metrics:Dictionary(uniqueKeysWithValues:metrics.filter{$0.value.isFinite}.map{($0.key.rawValue,$0.value)}),errorDomain:domain,errorCode:code)
    lock.lock();items.append(entry);if items.count > capacity {items.removeFirst(items.count-capacity)}
    pending?.cancel()
    let work = DispatchWorkItem{[weak self] in self?.persist()};pending = work;lock.unlock()
    queue.asyncAfter(deadline:.now()+0.5,execute:work)
  }
  public func entries() -> [DiagnosticEntry] {lock.lock();defer {lock.unlock()};return items}
  private func persist() {
    guard let file else {return}
    do {
      let folder = file.deletingLastPathComponent()
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
      try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:folder.path)
      let data = try JSONEncoder().encode(entries());try data.write(to:file,options:.atomic)
      try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    } catch {} // Diagnostic I/O must never interrupt editing or trigger an error loop.
  }
  public func flush() {lock.lock();pending?.cancel();pending = nil;lock.unlock();queue.sync {self.persist()}}
  public func report() -> String {
    let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
    let data = (try? encoder.encode(entries())) ?? Data("[]".utf8)
    let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
    return "OpenRaceRender diagnostics\nVersion: \(version)\nSystem: \(ProcessInfo.processInfo.operatingSystemVersionString)\nNo source paths, project contents, telemetry samples or credentials are included.\n\n"+(String(data:data,encoding:.utf8) ?? "[]")
  }
}
