import Foundation

/// App-owned resources live outside privacy-protected user document folders.
public enum LayoutLibrary {
  public enum Category: String, CaseIterable, Codable, Sendable {
    case templates = "Templates"
    case styles = "Styles"
    case images = "Images"
    case videoPositions = "Video Positions"
  }

  public struct Entry: Identifiable, Equatable, Sendable {
    public var url: URL
    public var category: Category
    public var relativePath: String
    public var id: String { url.path }
  }

  public static func userRoot(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    homeDirectory.appendingPathComponent("Library/Application Support/OpenRaceRender/Library", isDirectory: true)
  }

  public static func defaultRoots(
    resourceURL: URL? = Bundle.main.resourceURL,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [URL] {
    // Never probe Documents here, including for migration. Reading an old
    // library is an explicit import operation, not a side effect of launch.
    var roots = [userRoot(homeDirectory: homeDirectory)]
    if let resourceURL { roots.append(resourceURL.appendingPathComponent("RaceRender 3")) }
    return roots
  }

  public struct ImportResult: Equatable, Sendable {
    public var imported: Int = 0
    public var keptExisting: Int = 0
  }

  /// Copy a selected library or category, preserving subfolders and existing
  /// user customizations. Originals remain usable by their original app.
  public static func importLibrary(from source: URL, to destination: URL = userRoot()) throws -> ImportResult {
    let fm = FileManager.default
    let source = source.standardizedFileURL.resolvingSymlinksInPath()
    let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
    guard destination != source, !destination.path.hasPrefix(source.path + "/") else {
      throw RaceError.invalid("Choose a source outside the destination library.")
    }
    let folders: [(Category, URL)]
    if let category = Category(rawValue: source.lastPathComponent) { folders = [(category, source)] }
    else { folders = Category.allCases.map { ($0, source.appendingPathComponent($0.rawValue)) } }
    var files: [(URL, URL)] = []
    for (category, folder) in folders {
      guard fm.fileExists(atPath: folder.path) else { continue }
      let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw RaceError.invalid("Library categories must be ordinary folders: " + category.rawValue)
      }
      var enumerationError: Error?
      guard let enumerator = fm.enumerator(at: folder,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) else { continue }
      for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
          throw RaceError.invalid("Library import does not follow symbolic links: " + url.lastPathComponent)
        }
        if values.isDirectory == true { continue }
        guard values.isRegularFile == true else { continue }
        let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
        files.append((url, destination.appendingPathComponent(category.rawValue).appendingPathComponent(relative)))
      }
      if let enumerationError { throw enumerationError }
    }
    guard !files.isEmpty else {
      throw RaceError.invalid("No files found. Select a library containing Templates, Styles, Images or Video Positions, or one of those category folders.")
    }
    var result = ImportResult()
    for (source, target) in files {
      if fm.fileExists(atPath: target.path) { result.keptExisting += 1; continue }
      try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      let temporary = target.deletingLastPathComponent().appendingPathComponent(".import-" + UUID().uuidString)
      do {
        try fm.copyItem(at: source, to: temporary)
        try fm.moveItem(at: temporary, to: target)
        result.imported += 1
      } catch {
        try? fm.removeItem(at: temporary)
        throw error
      }
    }
    return result
  }

  public static func entries(in roots: [URL]) -> [Entry] {
    var result: [Entry] = []
    var seen = Set<String>()
    let fm = FileManager.default
    for root in roots {
      let root = root.standardizedFileURL.resolvingSymlinksInPath()
      var directory: ObjCBool = false
      guard fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { continue }
      guard let enumerator = fm.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
      ) else { continue }
      for case let enumeratedURL as URL in enumerator {
        // Foundation may enumerate /var through its /private/var alias.
        let relative = enumeratedURL.pathComponents.suffix(enumerator.level).joined(separator: "/")
        let url = enumeratedURL.resolvingSymlinksInPath()
        let ext = url.pathExtension.lowercased()
        guard ["rrt", "rro", "orrt"].contains(ext),
          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { continue }
        var parts = relative.split(separator: "/").map(String.init)
        let category: Category
        if let first = parts.first, let found = Category(rawValue: first) {
          category = found
          parts.removeFirst()
        } else {
          category = Category(rawValue: root.lastPathComponent) ?? (ext == "rro" ? .styles : .templates)
        }
        let key = (category.rawValue + "/" + parts.joined(separator: "/")).lowercased()
        guard seen.insert(key).inserted else { continue }
        result.append(Entry(url: url, category: category, relativePath: relative))
      }
    }
    return result.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
  }
}
