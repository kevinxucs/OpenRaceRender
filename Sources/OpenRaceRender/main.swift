import AVFoundation
import AppKit
import Foundation
import RaceCore
import SwiftUI

enum CLI {
  static let help = """
    OpenRaceRender — native open source telemetry video editor

      OpenRaceRender [--open] PROJECT
      OpenRaceRender inspect PROJECT
      OpenRaceRender inspect-data DATAFILE
      OpenRaceRender validate-library DIRECTORY
      OpenRaceRender snapshot PROJECT --time 120 --out frame.png [--width 1280]
      OpenRaceRender export PROJECT --start 120 --duration 5 --out clip.mp4 [--width 1920] [--fps 30]
      OpenRaceRender convert PROJECT --out converted.orrp

    Projects: .rrp (RRP3), .rrt, .rro, .orrp, .orrt
    Telemetry: CSV/TSV, RaceChrono CSV, GPX, TCX, NMEA, VBO and FIT. GUI: add via Add input.
    """
  static func run(_ a: [String]) async -> Int32 {
    do {
      guard a.count > 1 else {
        print(help)
        return 0
      }
      if ["--help", "-h", "help"].contains(a[1]) {
        print(help)
        return 0
      }
      guard a.count > 2 else { throw RaceError.invalid("Missing input path.\n" + help) }
      let url = URL(fileURLWithPath: a[2])
      func option(_ s: String) -> String? {
        guard let i = a.firstIndex(of: s), i + 1 < a.count else { return nil }
        return a[i + 1]
      }
      func output() throws -> URL {
        guard let path = option("--out") else { throw RaceError.invalid("Specify --out PATH.") }
        let u = URL(fileURLWithPath: path)
        guard u.standardizedFileURL != url.standardizedFileURL else {
          throw RaceError.invalid("Input and output must differ.")
        }
        return u
      }
      if a[1] == "validate-library" {
        let fm = FileManager.default
        let files =
          (fm.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
          .filter { ["rrt", "rro", "rrp"].contains($0.pathExtension.lowercased()) }
        var failures = 0
        var total = 0
        for f in files.sorted(by: { $0.path < $1.path }) {
          do {
            let p = try RaceProject.read(f)
            total += p.objects.count
            print("OK \(p.objects.count) displays  \(f.lastPathComponent)")
          } catch {
            failures += 1
            print("FAIL \(f.lastPathComponent): \(error.localizedDescription)")
          }
        }
        print(
          "\(files.count-failures)/\(files.count) files readable; \(total) display objects; \(failures) failures"
        )
        return failures == 0 && !files.isEmpty ? 0 : 1
      }
      if a[1] == "inspect-data" {
        let d = try Telemetry(url: url)
        let out: [String: Any] = ["samples": d.count, "duration": d.duration, "channels": d.headers,
          "laps": d.laps.count, "mapPoints": d.mapPoints.count,
          "events": d.syncEvents.map { ["name": $0.name, "time": $0.time] as [String: Any] }]
        print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        return 0
      }
      var p = try RaceProject.read(url)
      if let width = option("--width").flatMap(Int.init) {
        p.height = Int((Double(width) * Double(p.height) / Double(p.width) / 2).rounded()) * 2
        p.width = width
      }
      if let fps = option("--fps").flatMap(Double.init) { p.fps = fps }
      var telemetry: [Int: Telemetry] = [:]
      for input in p.inputs where input.kind == "data" && input.exists {
        let data = try Telemetry(url: URL(fileURLWithPath: input.path))
        if let settings = input.dataSettings { data.configure(settings) }
        telemetry[input.legacyIndex] = data
        if let i = p.inputs.firstIndex(where: { $0.id == input.id }) { p.inputs[i].duration = data.duration }
      }
      switch a[1] {
      case "inspect":
        var out: [String: Any] = [
          "name": p.name, "format": "OpenRaceRender 1", "width": p.width, "height": p.height,
          "objects": p.objects.map {
            [
              "name": $0.name, "kind": $0.kind.rawValue, "style": $0.style, "x": $0.x, "y": $0.y,
              "width": $0.width, "height": $0.height, "visible": $0.visible, "input": $0.inputIndex,
            ] as [String: Any]
          }, "warnings": p.warnings,
        ]
        out["inputs"] = p.inputs.map {
          [
            "name": $0.name, "path": $0.path, "kind": $0.kind, "exists": $0.exists,
            "offset": $0.offset, "duration": $0.duration,
          ] as [String: Any]
        }
        out["telemetry"] = telemetry.map {
          [
            "input": $0.key, "title": $0.value.title, "samples": $0.value.count,
            "duration": $0.value.duration, "channels": $0.value.headers,
            "laps": $0.value.laps.map {
              [
                "number": $0.number, "start": $0.start, "duration": $0.duration,
                "complete": $0.complete,
              ] as [String: Any]
            },
          ] as [String: Any]
        }
        print(
          String(
            data: try JSONSerialization.data(
              withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
      case "convert":
        try p.save(output())
        print("Saved native project.")
      case "snapshot":
        let dest = try output()
        try VideoExporter.snapshot(
          scene: RenderScene(project: p, telemetry: telemetry),
          time: Double(option("--time") ?? "0") ?? 0, to: dest)
        print(dest.path)
      case "export":
        let dest = try output()
        let start = Double(option("--start") ?? "0") ?? 0
        let duration = Double(option("--duration") ?? "10") ?? 10
        let exporter = VideoExporter()
        try await exporter.export(
          scene: RenderScene(project: p, telemetry: telemetry), to: dest, start: start,
          duration: duration)
        print(dest.path)
      default: throw RaceError.invalid("Unknown command: \(a[1])")
      }
      return 0
    } catch {
      FileHandle.standardError.write(Data(("Error: " + error.localizedDescription + "\n").utf8))
      return 1
    }
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: EditorModel?
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    (model?.confirmDiscard() ?? true) ? .terminateNow : .terminateCancel
  }
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if let s = filenames.first { model?.open(URL(fileURLWithPath: s)) }
    sender.reply(toOpenOrPrint: .success)
  }
}

struct RaceRenderApp: App {
  @StateObject var model = EditorModel()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    WindowGroup("OpenRaceRender") {
      EditorView(model: model).onAppear {
        delegate.model = model
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        let path =
          args.firstIndex(of: "--open").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
          ?? args.dropFirst().first { !$0.hasPrefix("-") }
        if let path = path, model.project.inputs.isEmpty { model.open(URL(fileURLWithPath: path)) }
      }
    }.defaultSize(width: 1460, height: 920).windowStyle(.hiddenTitleBar)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button("New session", action: model.newProject).keyboardShortcut("n")
          Button("Open project…", action: model.chooseOpen).keyboardShortcut("o")
          Button("Add inputs…", action: model.chooseInputs).keyboardShortcut("i")
          Divider()
          Button("Templates & styles…") { model.showTemplates = true }.keyboardShortcut(
            "t", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
          Button("Save", action: { model.save() }).keyboardShortcut("s")
          Button("Save As…", action: { model.save(as: true) }).keyboardShortcut(
            "s", modifiers: [.command, .shift])
          Button("Save layout as template…", action: model.saveTemplate)
          Button("Export RaceRender copy…", action: model.exportRRP)
          Divider()
          Button("Export video…") { model.showExport = true }.keyboardShortcut("e")
          Button("Save snapshot…", action: model.snapshot)
        }
        CommandGroup(replacing: .undoRedo) {
          Button("Undo", action: model.undo).keyboardShortcut("z")
          Button("Redo", action: model.redo).keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Display") {
          ForEach(ObjectKind.allCases.filter { $0 != .group }, id: \.self) { kind in
            Button("Add \(kind.title)") { model.addObject(kind) }
          }
          Divider()
          Button("Duplicate", action: model.duplicate).keyboardShortcut("d")
          Button("Delete display", action: model.deleteSelected)
        }
      }
  }
}

let cliCommands = [
  "inspect", "inspect-data", "validate-library", "snapshot", "export", "convert", "--help", "-h", "help",
]
if CommandLine.arguments.count > 1 && cliCommands.contains(CommandLine.arguments[1]) {
  Task {
    let code = await CLI.run(CommandLine.arguments)
    exit(code)
  }
  dispatchMain()
} else {
  RaceRenderApp.main()
}
