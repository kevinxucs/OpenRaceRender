# Telemetry and gauge smoothing (F18)

Data inputs expose **Data channels & lap timing → Data smoothness**, also available in the column/profile configuration sheet. Source controls save in `.orrp` and `.orrd` profiles; reusable overlay templates omit them.

- **Boost sample rate** interpolates continuous readings at the requested video time without expanding every column into a high-rate table. It is on by default, preserving existing behavior. Turn it off for recorded sample holds. Heading interpolation crosses north by the shortest arc; gear and lap roles remain discrete. Missing-data pauses longer than the adaptive sampling gap are not interpolated.
- **Detect slower GPS updates** is opt-in. Repeated coordinate pairs, and repeated non-OBD speed, are reconstructed between observed update timestamps when at least three updates and predominantly held samples establish a slower cadence. The reconstruction skips nonfinite samples, time gaps and holds longer than 1.75 times the observed median update interval (also capped by the adaptive gap). It does not change recorded clocks or every non-GPS channel. Turn it off when repeated positions represent real stops rather than held GPS updates.
- **Smooth map curves** uses bounded monotone cubic interpolation for the position columns. Both map trace and moving marker read the same curves. The trace adds intermediate points, capped at approximately 4000, so a low-rate corner actually becomes curved. This changes visual interpolation, not recorded lap boundaries. Curve and GPS reconstruction controls are inactive when boosting is off.

The source's original table is restored before each configuration, so toggling modes or reloading does not accumulate smoothing. GPS reconstruction happens before motion estimation. Map curve interpolation is visual; it does not recalculate speed, G or lap crossings from the displayed curve. Map traces continue to connect available track points across a missing section; an absent position does not produce a moving marker during the gap.

## Gauge averaging

**Expanded gauge design → Average over seconds (0–10)** averages a centered interval in source time. Zero disables it. This replaces the earlier fixed nine-point approximation with a time-weighted integral, so irregularly spaced samples receive the correct duration weight. Heading channels use circular means; gear/lap channels bypass averaging. Windows clip at session ends. A window crossing missing data falls back to its current valid reading instead of blending across the gap; a missing current reading remains missing.

A cached prefix integral makes repeated gauge queries logarithmic in sample count after a single linear preparation. The cache is bounded to eight series/128 MB and invalidates on source reconfiguration. Results depend on source time rather than prior rendered frames, so seeking backwards and exporting a chunk use the same readings. Original imported traditional gauge needle-smoothing flags use the shared 0.2-second average; exact numerical equivalence to RaceRender's unspecified averaging algorithm is unverified.

The known native Boost flag continues to roundtrip. Native GPS-update/curve flags are not verified, so newly configured options require `.orrp` and rewritten native export refuses them. Native checkbox semantics come from the local InputFileEdit and DispObjGaugeDesign guide pages; no undocumented flag offsets or native algorithm parity are asserted.

## Validation

Six core tests and one editor test cover time-weighted irregular data, end clipping, arbitrary query order, reconfiguration, circular/discrete values, pauses, opt-in GPS cadence, long stops, OBD protection, curve bounds/trace-marker alignment, profiles, native refusal, undo and template isolation. Full suite: 270 tests, no failures. `scripts/validate-smoothing.py` compares a noisy signal's known mean, held GPS reconstruction and an independently authored cubic path against snapshots, encoded frames and a nonzero-start chunk. Native/editor live operation remains limited by the computer-use service's `cgWindowNotFound` condition.
