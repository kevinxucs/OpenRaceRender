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

    let user = home.appendingPathComponent("Documents/OpenRaceRender")
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
}
