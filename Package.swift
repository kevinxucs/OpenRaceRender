// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "OpenRaceRender", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "OpenRaceRender", targets: ["OpenRaceRender"]),
    .library(name: "RaceCore", targets: ["RaceCore"]),
  ],
  targets: [
    .target(name: "RaceCore"),
    .executableTarget(name: "OpenRaceRender", dependencies: ["RaceCore"]),
    .testTarget(name: "RaceCoreTests", dependencies: ["RaceCore"]),
    .testTarget(name: "EditorTests", dependencies: ["OpenRaceRender"]),
  ])
