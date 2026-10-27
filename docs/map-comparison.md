# Two-run maps and lap ghosts (F20)

Select a map widget and expand **Two-run map / lap ghost**. Enable **Show comparison**, choose another data input, and select the clock mode. Both sources must provide decimal GPS latitude/longitude. A single shared projection and bounds place both markers correctly even when their source origins or recorded extents differ. The primary marker is filled; the comparison marker is a larger hollow ring so coincident positions remain distinguishable.

The primary course is drawn once. **Draw comparison course** optionally adds the second trace; leaving it off provides a position-only comparison. Choose the second color and source-name legends independently. Bounds include both entire recorded sources and stay fixed while markers move. Unrelated courses or GPS outliers can therefore make the useful part of the map small; this feature assumes recordings from the same course. It does not attempt to align unrelated relative X/Y origins.

## Synchronized runs

**Each input's synchronized time** uses each input's own offset, trim, delay and playback rate. Select primary/comparison laps to restrict their displayed intervals and enable lap-start alignment. **Align selected lap starts** aligns the comparison source to the selected primary lap (or the lap at the playhead), using the existing source timing rules. With no comparison lap selected, alignment uses its first recorded interval. For recordings that start with a partial warmup, choose the intended full lap explicitly.

Alignment and **Comparison offset** change that input for every widget using it. To keep existing overlays on their original clock, choose **Duplicate primary as comparison** or right-click a data input and choose **Duplicate data input**. Duplication creates an independent source identity/clock with the same file and settings and no extra displays. Duplicating from a map also assigns the copy as its comparison in one undoable change. The original input, marks and overlays retain their timing. Offset changes can extend automatic project length; use video-bound length or export marks when needed.

Inputs with the same normalized path and identical data settings share one parsed telemetry table in both editor and CLI. Their placement clocks remain independent. A settings change causes a separate configured table; no extra full-table copy or file parse is needed just to compare another lap from the same recording.

## Lap ghost

**Lap ghost: match elapsed lap time** places the reference at `reference lap start + elapsed time in the primary lap`. It keeps the recorded pace; it does not scale faster and slower laps to equal duration. A faster ghost waits at its finish until the primary lap ends. Selecting no primary lap follows the current lap; selecting no comparison lap uses the best complete lap from the whole source. A partial run can be selected explicitly when no full lap exists.

Ghost mode uses recorded source lap timing independently of the reference input's synchronization, trim and playback rate. The primary source's project placement still determines the active lap clock. An unavailable saved lap or missing lap timing hides the ghost and marks it unavailable; it does not substitute an arbitrary lap. Configure a GPS finish line or recorded lap assignment first if needed.

## Persistence and validation

Comparisons save in `.orrp`, support timeline overrides and explicit clearing, and use both data roles in `.orrt` templates. Template export strips fixed session lap selections along with paths and source clocks, while retaining the comparison role and appearance. Map styles applied to an existing instance preserve its comparison/source configuration. Native RaceRender rewriting refuses shared-map/ghost settings rather than dropping them; the guide's two-stacked-map workflow is represented here as one coordinated map widget.

Removing a comparison input marks its base/timeline references missing; Undo restores them. Export preflight requires both recorded source files even when no other widget uses the reference. Trace geometry is cached with source identity/revision/settings, and both full renders and chunks evaluate marker positions from source clocks.

Six core/two editor tests cover independent duplication/alignment, ghost pace/finish/invalid laps, shared projection, telemetry reuse, template roles/remapping/session cleanup, timeline clearing, export dependencies, source removal and Undo. Full suite: 286 tests. `scripts/validate-map-comparison.py` checks both marker colors' pixel positions against independently calculated circular runs and checks encoded frames/nonzero chunks. Live editor/native UI operation remains limited by `cgWindowNotFound`; these checks establish OpenRaceRender behavior rather than native algorithm/pixel parity.
