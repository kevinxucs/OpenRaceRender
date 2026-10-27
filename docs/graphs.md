# 2D graph controls (F06)

Select a Graph display and use **2D GRAPH** in the inspector. Choose the Y channel in the existing data-source picker. The horizontal axis can be source time, distance, or any recorded channel; distance and channel values retain the input's units.

- **Moving history** shows the selected span ending at the current data time. **Centered** shows half the span on either side, with a position marker.
- **Fixed**, **Fixed + position line/dot/both**, and **Progress** use the full source or explicit source start/end times. Progress reveals samples as the playhead advances. A specific recorded lap can replace the fixed source range. Missing channels/laps are identified in the preview.
- Y minimum/maximum can use the existing numeric fields or automatic source bounds. X bounds can be automatic or independently specified. A flat range is safely expanded.
- Connect samples or show points; optionally sort a nonmonotonic X channel, rotate the plot vertically, or reverse its X direction.
- Appearance controls cover line/fill colors and gradients, background, axes, intervals, numbering, border, position marker and label. Sizes scale from a saved design width. Axis interval zero chooses readable automatic steps.

Settings persist in projects, portable templates and styles, and inherited timeline events. Preview, snapshots and video export share the same renderer. The source clock comes from the existing synchronized/trimmed/rate-adjusted input placement. Data beyond the file is not held across a moving window. Fixed plots may intentionally show future samples; Progress shows only elapsed samples.

Extrema-preserving sampling retains narrow peaks and discontinuities. Fixed plot samples are cached (four entries per telemetry object); moving plots binary-search their time range. Cache keys include the data-transform revision. Seeking and rendering a chunk do not depend on previous rendered frames.

## RaceRender interoperation

The mirrored [display toolbox guide](https://racerender.com/RR3/docs/DispObjToolbox.html) describes time, distance and arbitrary-channel graphs. RaceRender 3.7.3 Ultimate's actual graph inspector was checked on an original synthetic project. It exposes seven plot modes, source-time ranges, X/Y bounds, line/point connection, sorting, orientation, colors, gradients, axes and number settings. Saved mode/range records and isolated reverse, fill and gradient changes were inspected to distinguish their fields.

Imported type-35 graphs now retain supported settings and use the graph renderer, including displays whose names contain Speed or RPM. Earlier `.orrp` imports recover graph settings from retained payloads without modifying the original. A four-byte empty RRO image container is no longer treated as actual artwork.

RRP/RRT/RRO export supports authored graphs and the verified graph fields. Legacy export requires a positive explicit interval when axes or numbers are enabled, because RaceRender stores one fixed interval for both axes. Distance uses RaceRender's built-in `(Distance)` identifier. Native lap selection and opposite-side axis numbers currently require `.orrp`/`.orrt`; legacy export refuses those overrides explicitly. Native RaceRender may normalize intrinsic graph dimensions. Imported label font metrics, automatic interval selection, manual label positioning, high-resolution rasterization, and vendor-specific layout details are not claimed to match pixel for pixel. Original unknown payload bytes remain available; native graph appearance uses the documented controls above.

## Validation

Eight core graph tests and one editor workflow test cover time windows, source limits, fixed/progress seek determinism, channel/distance axes, nonmonotonic sorting, ranges/missing channels, cache invalidation, peak/gap preservation, old imports, timeline/native/template persistence, all seven modes across RRP/RRT/RRO, and rendered appearance/cursor changes. `scripts/validate-graphs.py` creates original synthetic media and six configurations, checks exact OpenRaceRender snapshots before/after legacy roundtrip, and verifies advancing encoded video. The acceptance comparison is OpenRaceRender versus its reopened export; it is not a native RaceRender pixel-parity result.

The live OpenRaceRender inspector changed the first synthetic graph to a centered distance plot with a 1.25-second span and saved it as `live-graph-edits.orrp`; the actual saved settings were verified. Numeric AX clicks did not reliably focus/select the text field; AX value entry followed by Return/Tab committed successfully. The app quit after saving. Full validation passed 179 tests (153 core, 26 editor) without skips with the optional local library. Native RaceRender opened the authored synthetic graph RRP; no native pixel parity is claimed.
