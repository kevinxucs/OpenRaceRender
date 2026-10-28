import Darwin
import Foundation

public struct RecoverySnapshot:Codable,Sendable {
  public var version = 1
  public var id:UUID
  public var savedAt:Date
  public var originalURL:URL?
  public var playhead:Double
  public var project:RaceProject
}
public struct RecoveryCandidate:Identifiable,Equatable,Sendable {
  public let id:UUID
  public let name:String
  public let savedAt:Date
  public let originalURL:URL?
  public let archived:Bool
}
public struct RecoveryListing:Sendable {
  public var candidates:[RecoveryCandidate] = []
  public var unreadableCount = 0
}

/// Private, atomic project copies. A live session's advisory lock prevents a
/// second app instance from offering or archiving work that is still active.
public final class RecoveryStore:@unchecked Sendable {
  public let directory:URL
  public let maximumBytes:Int
  public init(directory:URL,maximumBytes:Int = 256*1024*1024) {self.directory = directory;self.maximumBytes = maximumBytes}
  public static var defaultDirectory:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenRaceRender/Recovery",isDirectory:true)}
  func prepare() throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    guard try directory.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else {throw RaceError.invalid("Recovery directory cannot be a symbolic link.")}
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
  }
  func file(_ id:UUID,archived:Bool = false) -> URL {
    (archived ? directory.appendingPathComponent("Archived",isDirectory:true) : directory).appendingPathComponent(id.uuidString+".json")
  }
  func acquire(_ id:UUID) throws -> Int32 {
    try prepare()
    let path = directory.appendingPathComponent(id.uuidString+".lock").path
    let fd = Darwin.open(path,O_RDWR|O_CREAT|O_NOFOLLOW,mode_t(0o600))
    guard fd >= 0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
    guard flock(fd,LOCK_EX|LOCK_NB) == 0 else {Darwin.close(fd);throw RaceError.invalid("This recovery copy belongs to a running editor.")}
    return fd
  }
  func decode(_ id:UUID,archived:Bool) throws -> RecoverySnapshot {
    let url = file(id,archived:archived)
    let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
    guard values.isRegularFile == true,values.isSymbolicLink != true,(values.fileSize ?? maximumBytes+1) <= maximumBytes else {throw RaceError.invalid("Invalid or oversized recovery copy.")}
    let data = try Data(contentsOf:url)
    guard data.count <= maximumBytes else {throw RaceError.invalid("Recovery copy is too large.")}
    let value = try JSONDecoder().decode(RecoverySnapshot.self,from:data),p = value.project
    guard value.version == 1,value.id == id,p.formatVersion == 1,p.width > 0,p.height > 0,p.width <= 16384,p.height <= 16384,p.fps.isFinite,p.fps > 0,p.fps <= 240 else {throw RaceError.invalid("Unsupported recovery copy.")}
    return value
  }
  public func newSession() throws -> RecoverySession {try RecoverySession(store:self,id:UUID())}
  /// Recovery is also available when the editor window cannot start. Reads a
  /// standalone copy without changing its directory's permissions or removing it.
  public static func exportCopy(from source:URL,to destination:URL) throws {
    guard source.pathExtension.lowercased() == "json",let id = UUID(uuidString:source.deletingPathExtension().lastPathComponent),destination.pathExtension.lowercased() == "orrp",
      !FileManager.default.fileExists(atPath:destination.path) else {throw RaceError.invalid("Choose a recovery UUID.json and a new .orrp output; existing files are never overwritten.")}
    let folder = source.deletingLastPathComponent(),archived = folder.lastPathComponent == "Archived"
    let store = RecoveryStore(directory:archived ? folder.deletingLastPathComponent() : folder)
    let lockPath = store.directory.appendingPathComponent(id.uuidString+".lock").path
    var fd:Int32 = -1
    if FileManager.default.fileExists(atPath:lockPath) {
      fd = Darwin.open(lockPath,O_RDONLY|O_NOFOLLOW)
      guard fd >= 0 else {throw RaceError.invalid("Cannot check this recovery copy's session lock.")}
      guard flock(fd,LOCK_EX|LOCK_NB) == 0 else {Darwin.close(fd);throw RaceError.invalid("This recovery copy belongs to a running editor.")}
    }
    defer {if fd >= 0 {flock(fd,LOCK_UN);Darwin.close(fd)}}
    let value = try store.decode(id,archived:archived)
    try value.project.save(destination)
  }
  public func listing(includeArchived:Bool = false) throws -> RecoveryListing {
    guard FileManager.default.fileExists(atPath:directory.path) else {return RecoveryListing()}
    var result = RecoveryListing()
    let folders = includeArchived ? [directory,directory.appendingPathComponent("Archived")] : [directory]
    for folder in folders where FileManager.default.fileExists(atPath:folder.path) {
      for url in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) where url.pathExtension == "json" {
        guard let id = UUID(uuidString:url.deletingPathExtension().lastPathComponent) else {continue}
        guard let fd = try? acquire(id) else {continue}
        defer {flock(fd,LOCK_UN);Darwin.close(fd)}
        do {
          let archived = folder != directory,value = try decode(id,archived:archived)
          result.candidates.append(RecoveryCandidate(id:id,name:value.project.name,savedAt:value.savedAt,originalURL:value.originalURL,archived:archived))
        } catch {result.unreadableCount += 1}
      }
    }
    result.candidates.sort{$0.savedAt > $1.savedAt};return result
  }
  public func read(_ candidate:RecoveryCandidate) throws -> RecoverySnapshot {
    let fd = try acquire(candidate.id);defer {flock(fd,LOCK_UN);Darwin.close(fd)}
    return try decode(candidate.id,archived:candidate.archived)
  }
  /// Kept in a recoverable archive rather than permanently deleted from the UI.
  public func archive(_ candidate:RecoveryCandidate) throws {
    guard !candidate.archived else {return}
    let fd = try acquire(candidate.id);defer {flock(fd,LOCK_UN);Darwin.close(fd)}
    let archive = directory.appendingPathComponent("Archived",isDirectory:true)
    try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try FileManager.default.moveItem(at:file(candidate.id),to:file(candidate.id,archived:true))
  }
}

public final class RecoverySession:@unchecked Sendable {
  public let id:UUID
  let store:RecoveryStore
  private let lock = NSLock()
  private var descriptor:Int32
  private var closed = false
  private var revision:UInt64 = 0
  init(store:RecoveryStore,id:UUID) throws {self.store = store;self.id = id;descriptor = try store.acquire(id)}
  public func persist(project:RaceProject,originalURL:URL?,playhead:Double,revision:UInt64) throws {
    let value = RecoverySnapshot(id:id,savedAt:Date(),originalURL:originalURL,playhead:playhead.isFinite ? max(0,playhead) : 0,project:project)
    let bytes = try JSONEncoder().encode(value)
    guard bytes.count <= store.maximumBytes else {throw RaceError.invalid("Recovery copy exceeds the storage limit; save the project manually.")}
    lock.lock();defer {lock.unlock()}
    guard !closed,revision >= self.revision else {return}
    let destination = store.file(id)
    try bytes.write(to:destination,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
    self.revision = revision
  }
  public func close(removeSnapshot:Bool) {
    lock.lock();defer {lock.unlock()}
    guard !closed else {return};closed = true
    if removeSnapshot {try? FileManager.default.removeItem(at:store.file(id))}
    flock(descriptor,LOCK_UN);Darwin.close(descriptor);descriptor = -1
    if removeSnapshot {try? FileManager.default.removeItem(at:store.directory.appendingPathComponent(id.uuidString+".lock"))}
  }
  deinit {close(removeSnapshot:false)}
}
