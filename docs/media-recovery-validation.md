# Missing-media recovery workflow

Checked on 2026-10-24 in RaceRender 3.7.3 Ultimate and the native OpenRaceRender app. The workflow is to reopen a session after its media folder has moved, repair its inputs, retain edits, save/reopen, and render its marked span. All destructive experiments used disposable projects under ignored `build/validation/recovery`.

## Reference behavior

RaceRender warns that unavailable inputs will be non-functional until their file names are updated. Input configuration identifies the path as `[OPEN FAILED]` and offers **Change File Selection**, described as retaining other settings. Selecting the synthetic 12-second camera updated its duration to 12 seconds while retaining brightness 90%, contrast 110%, saturation 125%, and the existing output flags. Saving to a new disposable RRP confirmed those fields on disk. The user's original RRP was not modified.

The vendor's [input configuration guide](https://racerender.com/RR3/docs/InputFileEdit.html) documents replacement through Change File Selection. OpenRaceRender follows that source-preserving workflow and adds persistent recovery feedback and export dependency checks.

## Gaps and changes

| Gap | Result |
| --- | --- |
| A missing input was indicated only in the small source list. | A persistent notice counts unavailable inputs; opening the project selects the first one, and Review missing files selects the next unresolved input. The inspector explains the failure and offers relinking. |
| Relink changed the project path before parsing/decoding the replacement. | Replacement telemetry, required video/audio tracks and image pixels are validated before a single undoable commit. Failure preserves the old input, settings, telemetry and dirty state. Requests that have become stale do not overwrite a changed source or another document. |
| Relinking an image input left the display reading its old path. | Matching file-backed image displays follow the replacement path; undo restores both references. |
| Missing sources were skipped during rendering, allowing incomplete output. | GUI export, CLI export and snapshots report required missing inputs and external artwork. Checks respect visible object spans, inherited source switches, joined-clip timing, hidden objects and embedded images/gauge faces. An unrelated unavailable input does not block the selected export. |
| An error raised from the export sheet could remain hidden until the sheet closed. | Dependency failures appear inside the sheet, disable rendering, and offer a relink shortcut. Other errors raised while the sheet is open have a sheet-owned alert. |

The dependency check detects absent files/source placeholders; it does not fully decode every asset in advance. Decoding failures still use the normal renderer error path. Preview remains usable for inspecting and repairing a partially available session.

## Acceptance evidence

The UI fixture has two camera inputs and one CSV, four display objects, a +1-second data offset, and marks at 3–8 seconds. Both cameras were relinked through native file pickers. An invalid CSV produced a visible error and retained the old missing path. Export with the CSV still missing displayed its name inside the sheet and offered **Relink missing files…**. Following that shortcut and choosing the valid CSV restored all 141 telemetry samples and cleared the missing-input notice.

The recovered project was saved, exported, and reopened. It retained the synchronization offset, all display geometry/settings, the 3–8-second marks, and the remembered output path. Comparing saved JSON found only replacement input paths and the new export destination changed. Its 640×360 snapshot at project time 3 was byte-identical to the original available-media session's snapshot. The UI export produced 1920×1080 H.264 with AAC, 150 video frames at 30 fps, and a duration of exactly 5 seconds. Its first frame, downscaled to the snapshot size, had a mean absolute RGB error of 3.0484/255 against the snapshot; the compression/scaling paths differ.

Automated verification:

- 84 tests passed with the local library and graphics services available: 80 core tests and 4 editor tests. Six new tests cover failed/valid relinks, settings retention, save/read, undo, image paths, range-dependent missing sources, joined clips and embedded artwork.
- `scripts/validate-media.py` passed actual rendered-pixel/audio checks and missing-camera/CSV rejection. Rejected exports created no output. An available span before a missing-camera switch still exported correctly; a snapshot immediately before that switch also succeeded.
- The app bundle was rebuilt with the existing local library. Proprietary layouts, private session files and validation media remain excluded from Git.

This validates recovery behavior and preservation of the tested session's output. It does not establish general RaceRender feature or pixel parity; see the [feature audit](racerender-feature-audit.md).
