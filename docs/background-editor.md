# Widget background editor (F09)

Choose **Edit widget background…** in a data widget, gauge, map, text or shape inspector. This shared tool replaces the gauge-only background import controls. A private draft allows experimentation; **Apply** makes one undoable change and **Cancel** leaves the session untouched. It can edit base settings or the currently selected timeline segment.

- Import an image or drop its file onto the preview. **Clear** removes the draft background.
- Zoom, pan in X/Y, rotate and preserve or stretch the original aspect. **Reset** restores the transform.
- Chroma-key a selected color with tolerance and soft-edge controls; the resulting PNG retains transparent pixels.
- Toggle **Preview entire widget** to align the image with the actual overlay and current telemetry. Face/background drawing may cover the artwork; applying a background automatically disables the gauge face or graph's solid background.
- **Export PNG…** saves the transformed background. **Edit externally…** opens a temporary PNG in the associated application. Return to OpenRaceRender to reload a changed file, or press **Reload external edits** explicitly. Returning from an unchanged file preserves subsequent draft adjustments. Import/Clear ends that external-edit association.

Applying bakes the transform/key into an embedded PNG; the draft's individual transforms are not retained after Apply. Reopen the editor to adjust the resulting bitmap, use Undo to restore the previous background, or import the original again. Temporary external-edit files may remain in the system temporary directory. Their paths are not written into projects or templates.

Backgrounds use the existing portable artwork layer. Gauges retain their settings/source/identity and maps can align an embedded image with the plotted trace. Map-specific follow/rotation/coordinate controls remain F21. Output is capped at 4096 pixels per dimension; the current editor uses a 1200-pixel-wide design canvas. Preview and encoded video use the embedded result through the same overlay renderer.

Timeline background clearing is represented explicitly rather than inherited from an earlier segment. Native projects retain it. Legacy writing supports base artwork removal, but refuses an artwork-clear timeline event because that native representation is not verified; it does not silently keep the earlier background.

## Evidence and limits

The local [background-image guide](https://racerender.com/RR3/docs/DispObjBackground.html) and [map background workflow](https://racerender.com/RR3/docs/HowTo-MapBackground.html) describe import/drop, clear, external edit, export, zoom/rotate, keying, aspect and whole-object preview. Those workflows guided the implementation. Native RaceRender's background button was observed during earlier inspector work. This feature's live background dialog and external-editor roundtrip have not been exercised: the UI connection currently reports `cgWindowNotFound` for both applications, and the request to restore a window remains pending.

193 automated tests pass with the local library and macOS graphics services. Four new core tests check pixel geometry/key transparency, malformed images/bounds, gauge/graph behavior, native persistence, portable artwork and legacy clear refusal. An editor test checks draft isolation, one-step undo and timeline changes. `scripts/validate-backgrounds.py` uses original checkerboard artwork, synthetic map data and a camera to verify clear/resume events and encoded frames against snapshots. This is automated composition validation, not native RaceRender pixel parity or a claim of live external-editor validation.
