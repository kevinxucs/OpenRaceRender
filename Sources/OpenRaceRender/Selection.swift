import AppKit
import RaceCore
import SwiftUI

extension EditorModel {
  func setSelection(_ ids: Set<UUID>, primary: UUID? = nil) {
    changingSelection = true
    selectedIDs = ids.intersection(Set(project.objects.map(\.id)))
    selected = primary.flatMap { selectedIDs.contains($0) ? $0 : nil }
      ?? project.objects.reversed().first { selectedIDs.contains($0.id) }?.id
    changingSelection = false
    if selectedIDs.count != 1 { editingSegment = nil }
    selectedInput = nil
  }
  func selectDisplay(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
    if modifiers.contains(.command) {
      var ids = selectedIDs
      if !ids.insert(id).inserted { ids.remove(id) }
      setSelection(ids, primary: id)
    } else if modifiers.contains(.shift), let anchor = selected,
      let a = project.objects.firstIndex(where: { $0.id == anchor }),
      let b = project.objects.firstIndex(where: { $0.id == id }) {
      setSelection(selectedIDs.union(project.objects[min(a,b)...max(a,b)].map(\.id)), primary: anchor)
    } else { selected = id; selectedInput = nil }
  }
  func selectAllDisplays() { setSelection(Set(project.objects.map(\.id))) }
  /// The Display menu's Command-A must preserve normal field-editor selection in sheets.
  func selectAllInFocusedEditor() {
    selectAll(focusedResponder: NSApp.keyWindow?.firstResponder)
  }
  func selectAll(focusedResponder: NSResponder?) {
    if let text = focusedResponder as? NSTextView, text.isSelectable {
      text.selectAll(nil)
    } else { selectAllDisplays() }
  }
  func groupSelection() {
    do {
      var changed = project
      let id = try changed.groupDisplays(selectedIDs)
      checkpoint(); project = changed; selected = id
      status = "Grouped displays · existing timeline events preserved"
    } catch { self.error = error.localizedDescription }
  }
  func ungroupSelection() {
    guard project.objects.contains(where: { selectedIDs.contains($0.id) && $0.kind == .group }) else { return }
    checkpoint(); setSelection(project.ungroupDisplays(selectedIDs)); status = "Ungrouped displays"
  }
  /// Click a member as a group; Option-click allows editing that individual member.
  func canvasSelectionID(_ id: UUID, individual: Bool) -> UUID {
    individual ? id : project.ancestors(of: id).last ?? id
  }
  func selectionGeometry(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> Binding<Double> {
    Binding(get: { Double(self.project.selectionBounds(self.selectedIDs, at: self.editingSegment)?[keyPath: keyPath] ?? 0) },
      set: { value in
        guard value.isFinite, let from = self.project.selectionBounds(self.selectedIDs, at: self.editingSegment) else { return }
        var to = from; to[keyPath: keyPath] = value
        guard to.width > 0, to.height > 0, to != from else { return }
        self.checkpoint(); self.project.transformDisplays(self.selectedIDs, from: from, to: to, at: self.editingSegment)
      })
  }
}

struct MultipleSelectionInspector: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("\(model.selectedIDs.count) displays selected").font(.headline)
      Text("Move or resize the selection together. Command-click toggles selection; Shift-click selects a range. Option-click in the preview selects an individual group member.")
        .font(.caption).foregroundStyle(.secondary)
      HStack { field("X", model.selectionGeometry(\.origin.x)); field("Y", model.selectionGeometry(\.origin.y)) }
      HStack { field("Width", model.selectionGeometry(\.size.width)); field("Height", model.selectionGeometry(\.size.height)) }
      Toggle("Keep aspect ratio when resizing", isOn: $model.lockWidgetAspect)
      Button("Group selected displays", action: model.groupSelection)
      Button("Ungroup selected groups", action: model.ungroupSelection)
      Button("Duplicate selection", action: model.duplicate)
      Button("Delete selection", role: .destructive, action: model.deleteSelected)
    }.padding(16)
  }
  func field(_ label: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
    }
  }
}
