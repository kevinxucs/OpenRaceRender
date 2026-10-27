# Map display options (F21)

Select a map and expand **Map display**. Controls are shared by normal maps and two-run/ghost maps:

- Show/hide the course and vehicle positions independently, or mark the trace start/finish.
- Choose the whole source, best complete lap, current lap, or a selected lap/run for the course trace. A missing selection is reported. With the course hidden, positions can still use whole-source bounds even without lap metadata.
- Use a dot, ring, directional arrow or original vector car icon. Set size and color independently of the course/edge colors and widths.
- Set zoom from 0.1–20×, clockwise rotation, heading up and centering on the vehicle. Heading up uses the source's configured heading; unavailable headings fall back to north up. There is no stateful frame-history dependency.
- Set normal/high/extreme trace detail (approximately 1000/4000/16000 points). These limit vector path sampling rather than creating a new bitmap for every frame. Source curve smoothing adds intermediate points within the chosen budget; increasing detail cannot recover unrecorded GPS accuracy.

Map geometry is cached by source/revision, selected interval and sampling budget. Exact interval endpoints are included. Icons and line widths stay readable while the course zooms. Shared comparison maps retain shared full-source bounds and move both markers together; comparison clocks, selected marker intervals and reference-course visibility still come from **Two-run map / lap ghost**. The map trace selector changes the primary course; it does not change either source's clock. Comparison legends remain fixed in the widget while the map moves.

## Background alignment

Use **Edit widget background…** to import and align embedded artwork against the whole widget. It is easiest to align at 1× zoom, north up and with final comparison labels/layout selected. Existing image rotate/zoom/position/keying and whole-widget preview controls remain available.

**Keep background aligned with map** applies exactly the same viewport transform to that embedded image and the plotted course. Zoom, rotation, heading-up and following therefore preserve their alignment. Turn it off to keep the artwork fixed in the widget. Separately added image widgets retain their own independent positions, as in the guide's basic layering workflow.

## Imported maps, templates and validation

Unedited imported maps keep their original renderer/payload. The editor reads the known best-lap, visibility, color, width, icon and zoom values without modifying the project. Changing an option opts into the vector map renderer; unsupported original effects and exact native raster appearance are not inferred. **Reset to original map** clears those edits and restores the imported renderer or native defaults.

Options persist in `.orrp`/`.orrt`, support timeline overrides/explicit reset, and are undoable. Template export resets fixed session-specific lap selections to Whole source. Rewritten native RaceRender files refuse edited map options until their encoding is verified; resetting restores the original payload path.

Five core/one editor tests cover coordinate/heading-up/follow/background transforms, trace choices/endpoints/detail, distinct icons, visibility/flags, missing-position status, imported option reads, persistence, timeline clears, template cleanup, reset and undo. Full suite: 292 tests. `scripts/validate-map-display.py` checks marker and colored artwork positions against independent transform math, fixed-vs-aligned artwork, follow mode and encoded output. It also reruns two-run/ghost marker and chunk checks. Live editor/native operation remains limited by the computer-use service's `cgWindowNotFound` condition, so no native UI/pixel-parity claim is made.
