import RaceCore
import SwiftUI

extension EditorModel {
  var templateIncludedIDs: Set<UUID> { project.layoutObjectIDs(templateObjectIDs) }
  var templateUsedInputs: Set<Int> { project.layoutInputIndices(templateObjectIDs) }
  var templateIsSingleStyle: Bool {
    templateSelectedOnly && templateIncludedIDs.count == 1 && project.objects.contains {
      templateIncludedIDs.contains($0.id) && $0.kind != .group
    }
  }
  func beginTemplateDraft(style: Bool) {
    templateSelectedOnly = style; templateLegacyFormat = false
    templateName = project.name + " Layout"
    templateObjectNames = Dictionary(uniqueKeysWithValues: project.objects.map { ($0.id, $0.name) })
    var counts: [String: Int] = [:]
    templateInputNames = Dictionary(uniqueKeysWithValues: project.inputs.map { input in
      counts[input.kind, default: 0] += 1
      return (input.legacyIndex, input.kind.capitalized + " \(counts[input.kind]!)")
    })
    templateObjectIDs = style ? project.descendants(of: selectedIDs)
      : Set(project.objects.filter { ![.video, .audio].contains($0.kind) }.map(\.id))
    showSaveTemplate = true
  }
  func templateDraft() throws -> RaceProject {
    var layout = try project.reusableLayout(objectIDs: templateObjectIDs,
      objectNames: templateObjectNames, inputNames: templateInputNames)
    layout.name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
    if layout.name.isEmpty { layout.name = "Custom Layout" }
    return layout
  }
  /// Group checkboxes select the entire branch; individual rows can then refine that subset.
  func templateChecked(_ id: UUID) -> Binding<Bool> {
    let branch: Set<UUID> = project.objects.contains { $0.id == id && $0.kind == .group }
      ? project.descendants(of: [id]) : [id]
    return Binding(get: { branch.isSubset(of: self.templateObjectIDs) }, set: { checked in
      if checked { self.templateObjectIDs.formUnion(branch) }
      else { self.templateObjectIDs.subtract(branch) }
    })
  }
  func templateObjectName(_ object: DisplayObject) -> Binding<String> {
    Binding(get: { self.templateObjectNames[object.id] ?? object.name },
      set: { self.templateObjectNames[object.id] = $0 })
  }
  func templateInputName(_ input: MediaInput) -> Binding<String> {
    Binding(get: { self.templateInputNames[input.legacyIndex] ?? input.name },
      set: { self.templateInputNames[input.legacyIndex] = $0 })
  }
}
