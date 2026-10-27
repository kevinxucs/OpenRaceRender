# Timeline editing (F10)

The **Timeline** and **Objects** tabs share a zoomable time window. Use **+ / −**, **Fit**, **Playhead**, and the window-position slider to navigate. Object event markers select their display/segment; hover for the time and changed fields. The speed trace, lap lines, export marks and playhead use the same visible window. Missing/inactive telemetry no longer holds the first speed sample across a gap.

Select a non-base segment in the inspector to edit its starting time. **Move** can reorder it across other events; frame buttons move by the project frame interval. **Shift this and following events** applies the supplied offset to that display's selected event and later events. It does not shift other displays, video inputs or export marks. Moves are atomic and reject collisions, negative/nonfinite times and times outside the model's supported 0–1,000,000-second range. An event beyond the project length is identified; extend the project length to render it.

**Fields changed in this segment** exposes inheritance controls for source, visibility, geometry, opacity, channel/text/color/range, picture, styles/artwork and the widget's specialized parameters. Uncheck a field to inherit it; check one to freeze its current value. **Inherit all fields** retains an empty marker. Changes made through the regular inspector automatically create the corresponding overrides. Active start/end bounds remain base settings and their controls are disabled while editing a segment.

Specialized settings already had segment support from earlier features. F10 completes explicit clearing: optional gauge/HUD/graph/image/picture/text/shape/audio settings and legacy renderer metadata can now be cleared rather than accidentally inherited. This permits a style to return to a native renderer during a session. Native saves retain the difference between clear and inherit. Legacy writing refuses a change of display renderer type during a segment rather than dropping it.

Undo/redo follows a retimed event's stable identity. Group retiming restores saved child records at the old time and captures new restoration history at the destination. Imported group geometry records without native ownership history retain independent child text/source/appearance changes when geometry is removed. Removing a pure group opacity event also preserves independent member events. A later nested-group edit at the same instant can make parent ownership ambiguous; move/remove that later event first. The inspector refuses the unsafe parent operation transactionally.

## Interchange correction found during validation

An intermittent template test exposed an encrypted input identifier equal to the raw `0xFF` end-of-input delimiter. Seed 195 reproduces it. RRT writing now deterministically advances the supplied seed until no input identifier collides with the delimiter. Valid supplied seeds and RRP/RRO behavior remain unchanged. A deterministic regression covers this instead of relying on random test runs.

## Validation

204 tests pass with local-library and graphics services available (173 core, 31 editor). Eight segment tests cover reorder/shift, transactional failures, inherited/frozen fields, optional-parameter/style clears, native persistence, group restoration, imported child preservation and nested conflict protection. Editor tests check undo/redo selection and zoom without dirtying the project. The template delimiter test covers the intermittent seed case.

`scripts/validate-timeline.py` compares original HUD appearance, an explicit parameter clear, and restoration in seek-independent snapshots and encoded frames. `scripts/validate-grouping.py` also passes exact legacy roundtrip snapshots and grouped audio/video hide/resume checks. All fixtures are original synthetic media/artwork/data under ignored `build/validation/`.

The mirrored [timeline guide](https://racerender.com/RR3/docs/TimelineView.html) and [segment editor guide](https://racerender.com/RR3/docs/TimelineEdit.html) were read for these workflows. Live updated-editor/native timeline operation remains unverified because the UI connection reports `cgWindowNotFound`; the earlier request to restore a window is still pending. Automated view-model/media checks are not described as a live usability or native pixel-parity result.
