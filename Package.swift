// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "OpenRaceRender", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "OpenRaceRender", targets: ["OpenRaceRender"]),
    .library(name: "RaceCore", targets: ["RaceCore"]),
  ],
  targets: [
    .target(name: "GoProGPMF", exclude: ["LICENSE.txt", "LICENSE-MIT", "LICENSE-APACHE", "UPSTREAM.md"], publicHeadersPath: "include"),
    .target(name: "RaceCore", dependencies: ["GoProGPMF"]),
    .executableTarget(name: "OpenRaceRender", dependencies: ["RaceCore"]),
    .testTarget(name: "RaceCoreTests", dependencies: ["RaceCore"]),
    .testTarget(name: "EditorTests", dependencies: ["OpenRaceRender"]),
  ])
