# RRP output markers and picture adjustments

The RRP3 reader previously skipped the project header's green/red output flags.
Imports now retain them as native In/Out marks, so the timeline, export dialog,
and CLI's default export range agree. Native saves retain those marks; compatible
RRP copies preserve unchanged markers byte for byte. Changing the marks still
requires saving a native `.orrp` project.

RaceRender stores brightness, contrast, color saturation and sharpness as
percentages with 100% neutral. Its [input-file documentation](https://racerender.com/RR3/docs/InputFileEdit.html)
describes the 0–200% scale and −180°…+180° hue range. OpenRaceRender exposes
brightness, contrast, saturation and sharpness as **−100…+100, with 0 neutral**.
For example, native 90% brightness becomes −10. Existing multiplier values in
native JSON files are retained without reinterpretation. Hue uses degrees.

All five controls have sliders and numeric entry with bounded values. Reset
returns them to neutral. Video displays offer a shortcut to the input's picture
settings: input adjustments affect every display using that source, while display
adjustments affect only the selected display.

Hue and sharpness are imported from the input settings record and survive native
save/reopen. Older native files without those fields remain readable; missing
input values are recovered from retained legacy data when available. Old native
files with no marks are not automatically assigned legacy marks, because a user
may have deliberately cleared them. Reimport the original `.rrp` in that case.

## Validation

The following checks use private local fixtures; their media, telemetry, project
files and native screenshots are excluded from the repository.

- Opened a disposable copy of the reported project in RaceRender 3.7.3. Its export
  dialog showed **03:03.783 → 23:21.375**. Independently clearing each flag and
  saving confirmed that zero represents an unset marker. The fields are float32
  seconds at header offsets 2128/2132, before the input table at 2152.
- Changed native sharpness to 150% and hue to −45°, saved, and compared the files.
  Sharpness is the byte at input-settings offset 30; hue is a signed little-endian
  Int16 at offset 28. Neither operation modified the original session.
- Opened the original RRP in OpenRaceRender. Both marks appeared in the timeline;
  the export dialog started at 183.782944 seconds for 1217.591812 seconds.
  Picture controls showed −10 brightness, +10 contrast, +25 saturation and neutral
  sharpness/hue. Edited sharpness to +50 and hue to −45, then saved a separate
  native project and checked its persisted values and marks.
- Compared native and OpenRaceRender snapshots at hue −45°/sharpness +50. A sky
  region had mean RGB error **2.21/255**. This checks color behavior for the sample;
  it does not establish general pixel parity. Sharpness uses an independent
  blur/sharpen implementation and can have a different edge response.
- All 78 tests passed with graphics access and local legacy fixtures, including
  absent/single/invalid markers, native roundtrips, old JSON compatibility,
  signed-value bounds, hue rotation and gray preservation, sharpening/blur edges,
  unchanged image dimensions, and neutral picture controls.
- `scripts/validate-media.py` passed the short video checks. Its synthetic RRP
  imports a marked 1.25–1.75 second span and hue/sharpness, saves to native JSON,
  exports a 0.5-second video with no CLI range override, and verifies green output
  pixels after rotating a red camera's hue by +120°.
