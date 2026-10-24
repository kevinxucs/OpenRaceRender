import XCTest
@testable import RaceCore

final class LibraryTests: XCTestCase {
  func testPackagedLibraryWorksWithoutDocumentsAndUserOverridesAvoidDuplicates() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let resources = base.appendingPathComponent("OpenRaceRender.app/Contents/Resources")
    let home = base.appendingPathComponent("AbsentHome")
    let packaged = resources.appendingPathComponent("RaceRender 3")
    func write(_ relative: String, under root: URL) throws -> URL {
      let url = root.appendingPathComponent(relative)
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("synthetic".utf8).write(to: url)
      return url
    }
    for category in LayoutLibrary.Category.allCases {
      let ext = category == .templates ? "rrt" : "rro"
      _ = try write("\(category.rawValue)/Example.\(ext)", under: packaged)
    }
    _ = try write("Styles/.hidden.rro", under: packaged)
    _ = try write("Styles/notes.txt", under: packaged)
    let roots = LayoutLibrary.defaultRoots(resourceURL: resources, homeDirectory: home)
    let entries = LayoutLibrary.entries(in: roots)
    XCTAssertEqual(entries.count, 4)
    XCTAssertEqual(Set(entries.map(\.category)), Set(LayoutLibrary.Category.allCases))
    XCTAssertTrue(entries.allSatisfy { $0.url.path.hasPrefix(packaged.path + "/") })

    let user = LayoutLibrary.userRoot(homeDirectory: home)
    let override = try write("Styles/Example.rro", under: user)
    _ = try write("Styles/Extra.orrt", under: user)
    let merged = LayoutLibrary.entries(in: roots)
    XCTAssertEqual(merged.count, 5)
    XCTAssertEqual(merged.first { $0.category == .styles && $0.url.lastPathComponent == "Example.rro" }?.url, override)
    XCTAssertFalse(merged.contains { $0.url == packaged.appendingPathComponent("Styles/Example.rro") })

    let images = LayoutLibrary.entries(in: [packaged.appendingPathComponent("Images")])
    XCTAssertEqual(images.count, 1)
    XCTAssertEqual(images.first?.category, .images)
  }

  func testDefaultRootsExcludeOldDocumentsLibrariesEvenWhenPresent() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    for folder in ["Documents/OpenRaceRender/Templates", "Documents/RaceRender 3/Templates"] {
      let url = home.appendingPathComponent(folder)
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
      try Data("old".utf8).write(to: url.appendingPathComponent("ShouldNotBeScanned.orrt"))
    }
    let roots = LayoutLibrary.defaultRoots(resourceURL: nil, homeDirectory: home)
    XCTAssertEqual(roots, [home.appendingPathComponent("Library/Application Support/OpenRaceRender/Library", isDirectory: true)])
    XCTAssertTrue(LayoutLibrary.entries(in: roots).isEmpty)
    XCTAssertFalse(roots.contains { $0.path.hasPrefix(home.appendingPathComponent("Documents").path) })
  }

  func testExplicitLibraryImportPreservesAssetsSubfoldersAndCustomizations() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("Documents/RaceRender 3")
    let destination = LayoutLibrary.userRoot(homeDirectory: root)
    func write(_ path: String, under folder: URL, contents: String) throws {
      let url = folder.appendingPathComponent(path)
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: url)
    }
    try write("Templates/Dashboard.orrt", under: source, contents: "layout")
    try write("Styles/Nested/Speed.rro", under: source, contents: "original")
    try write("Images/Logo.png", under: source, contents: "artwork")
    try write("Video Positions/Full.rro", under: source, contents: "position")
    try write("Styles/.hidden.rro", under: source, contents: "hidden")
    try write("Styles/Nested/Speed.rro", under: destination, contents: "custom")
    let imported = try LayoutLibrary.importLibrary(from: source, to: destination)
    XCTAssertEqual(imported.imported, 3)
    XCTAssertEqual(imported.keptExisting, 1)
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Styles/Nested/Speed.rro")), "custom")
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Images/Logo.png")), "artwork")
    XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("Styles/Nested/Speed.rro")), "original")
    XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("Styles/.hidden.rro").path))
    let repeated = try LayoutLibrary.importLibrary(from: source, to: destination)
    XCTAssertEqual(repeated.imported, 0)
    XCTAssertEqual(repeated.keptExisting, 4)
    let styles = root.appendingPathComponent("CategoryImport")
    XCTAssertEqual(try LayoutLibrary.importLibrary(from: source.appendingPathComponent("Styles"), to: styles).imported, 1)
    XCTAssertTrue(fm.fileExists(atPath: styles.appendingPathComponent("Styles/Nested/Speed.rro").path))
    XCTAssertThrowsError(try LayoutLibrary.importLibrary(from: source, to: source.appendingPathComponent("NestedDestination")))
  }

  func testImportRejectsSymlinksWithoutCopyingFiles() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("Source/Styles")
    try fm.createDirectory(at: source, withIntermediateDirectories: true)
    let external = root.appendingPathComponent("Outside.rro")
    try Data("outside".utf8).write(to: external)
    try fm.createSymbolicLink(at: source.appendingPathComponent("Linked.rro"), withDestinationURL: external)
    let destination = root.appendingPathComponent("Destination")
    XCTAssertThrowsError(try LayoutLibrary.importLibrary(from: source, to: destination))
    XCTAssertFalse(fm.fileExists(atPath: destination.path))
  }
}
