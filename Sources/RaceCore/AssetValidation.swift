import Foundation

extension RaceProject {
  /// Check dependencies of visible displays in the requested span, including source switches
  /// and joined clips. Preview can still show available sources while a project is repaired.
  public func validateExportAssets(start: Double, duration: Double, telemetry:[Int:Telemetry]? = nil) throws {
    guard start.isFinite, duration.isFinite, duration > 0 else { return }
    for input in inputs where input.cameraVideoID != nil {
      guard input.kind == "data",let camera = inputs.first(where:{$0.id == input.cameraVideoID && $0.kind == "video"}),camera.path == input.path else {
        throw RaceError.invalid("Embedded camera data has a missing or mismatched camera. Remove and add that data input again.")
      }
    }
    let end = start + duration
    var missing = Set<String>()
    func require(_ path: String, label: String) {
      var directory: ObjCBool = false
      if path.isEmpty || !FileManager.default.fileExists(atPath: path, isDirectory: &directory) || directory.boolValue {
        missing.insert(path.isEmpty ? "\(label): choose a source file" : "\(label): \((path as NSString).lastPathComponent)")
      }
    }
    let placements = placements
    for object in objects where object.kind != .group {
      let a = max(start, object.start), b = min(end, object.end)
      guard a < b else { continue }
      let boundaries = Set([a, b] + timelineBoundaries.filter { $0 > a && $0 < b }).sorted()
      for (lo, hi) in zip(boundaries, boundaries.dropFirst()) {
        guard let display = resolvedObjects(at: lo).first(where: { $0.id == object.id }),
          display.visible, lo >= display.start, lo < display.end, display.opacity > 0 else { continue }
        try display.picture?.validateEffects()
        if let timer = display.timerSettings {
          try timer.validate()
          if timer.mode == .timeOfDay,timer.clock == .source,timer.epoch == nil,let telemetry,telemetry[display.inputIndex]?.firstSampleUnixTime == nil {
            throw RaceError.invalid("‘\(display.name)’ has no recorded UTC epoch. Set an explicit clock anchor before rendering.")
          }
        }
        if display.kind == .image {
          if display.artwork == nil && display.embeddedImage == nil { require(display.text, label: display.name) }
        }
        if (display.timerSettings?.usesSourceClock ?? true) && (display.imageUsesData || ![.image, .shape, .text].contains(display.kind)) {
          let sources = inputs.filter { $0.legacyIndex == display.inputIndex || $0.joinedTo == display.inputIndex }
          if display.imageUsesData && sources.isEmpty { missing.insert(display.name + ": choose a telemetry input") }
          for input in sources {
            if input.isJoinRoot == true || input.isTimeFiller == true { continue }
            // Media can be deliberately inactive outside its trim/delay/join span.
            if ["video", "audio"].contains(input.kind), input.duration > 0 {
              let ranges = placements.filter { $0.input.id == input.id }
              if !ranges.isEmpty && !ranges.contains(where: { $0.end > lo && $0.start < hi }) { continue }
            }
            try input.picture?.validateEffects()
            require(input.path, label: input.name)
          }
        }
        if display.kind == .map,let comparison = display.mapComparison {
          for index in [display.inputIndex,comparison.referenceInputIndex] {
            if let input = inputs.first(where:{$0.legacyIndex == index && $0.kind == "data"}) { require(input.path,label:input.name) }
            else { missing.insert(display.name + ": choose both comparison data inputs") }
          }
        }
        if display.gauge?.backgroundImage == nil, let path = display.gauge?.backgroundPath {
          require(path, label: display.name + " background")
        }
      }
    }
    guard missing.isEmpty else {
      throw RaceError.invalid("Relink the missing assets used by this export before rendering:\n\n" + missing.sorted().joined(separator: "\n"))
    }
  }
}
