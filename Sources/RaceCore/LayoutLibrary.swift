import Foundation

/// Discovers both app resources and user libraries without modifying either.
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

  public static func defaultRoots(
    resourceURL: URL? = Bundle.main.resourceURL,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [URL] {
    // Explicit user customizations override packaged defaults. The installed
    // RaceRender library also supplies any files absent from the package.
    var roots = [homeDirectory.appendingPathComponent("Documents/OpenRaceRender")]
    if let resourceURL { roots.append(resourceURL.appendingPathComponent("RaceRender 3")) }
    roots.append(homeDirectory.appendingPathComponent("Documents/RaceRender 3"))
    return roots
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
