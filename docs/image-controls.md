# Data-controlled images (F08)

Select an Image display and use **Choose embedded image…** in **IMAGE CONTROL** to add artwork. The project and portable styles retain the image bytes. Existing file-backed images continue working.

Choose **Static image**, **Proportional data**, **At or above threshold**, or **At or below threshold**. A data mode selects the first available logger when needed; use the existing input/channel selectors to choose another stream. Proportional mappings clamp at the input endpoints, and either range can be reversed. Threshold comparisons include equality.

Outputs are visibility (values below 50 hide the image), opacity (0–100%), rotation (degrees), brightness (100% is normal), or hue (degrees). Rotation keeps the image center fixed. Color effects combine with existing picture adjustments and preserve transparent pixels. Unavailable data hides a controlled image rather than displaying a misleading first-sample value. Export checks both its artwork and telemetry dependencies.

**Flash image** alternates on/off phases of the selected duration. It uses project time, so seeking or rendering a chunk retains the session's phase. Data effects independently use the synchronized, trimmed, rate-adjusted telemetry clock. Static artwork can flash without a data input.

Settings participate in undo, inherited timeline events, reusable styles/templates, source-role mapping and group opacity. Switching to a data mode and assigning its logger is one undoable edit. Mapped images retain their telemetry role during template export; unused artwork-file inputs are omitted. Decoded artwork is cached with bounded memory; changed file-backed artwork is refreshed using modification metadata.

## Native file support and validation limits

RaceRender 3.7.3's actual E Image inspector was operated using a disposable native project. It exposes simple/proportional/greater-or-equal/less-or-equal modes, rotation/transparency/brightness/hue outputs, mapping endpoints and pulse interval. Saved proportional rotation and threshold transparency/pulse changes were inspected. The pulse byte stores tenths of a second. OpenRaceRender exposes opacity rather than transparency and converts the endpoint convention.

Native E Image records use a separate length-prefixed bitmap container. This caused earlier authored images to fail in RaceRender with `ProjectOpen2 -81` and native embedded images to fail OpenRaceRender's strict reader. The reader now accepts the independently bounded wrapper and the writer emits it with a 168-byte control record. A native-saved compass fixture now imports with decoded artwork and controls; private vendor imagery is not part of the public repository.

RRP/RRT/RRO roundtrip tests cover the stored image settings/artwork. Legacy writing supports tenths-of-a-second pulse intervals from 0 to 25.5. The native-only Visibility output must be expressed as opacity endpoints for legacy writing; unsupported values are refused before writing. Native pixel parity for color, rotation clipping and pulse phase is not established. A follow-up reopen of the corrected authored RRP and live updated-editor checks could not run because CUA reported `cgWindowNotFound` for both applications; a user request to restore the window is pending. Do not treat the automated roundtrip as that native reopen check.

## Automated checks

188 tests pass with local-library and macOS graphics services available. New tests cover mapping boundaries/reversed ranges, all outputs, missing data, flashing, pixel changes, group alpha applied once, bounded artwork, every verified mapping across project/style containers, template roles, timeline persistence, editor source assignment and atomic undo.

`scripts/validate-image-controls.py` generates original transparent artwork and telemetry for six configurations. It checks exact OpenRaceRender snapshots before/after legacy roundtrip, including flashing transitions, then compares nonzero-start encoded video frames with matching session-time snapshots. This also checks synchronized data offsets and prevents chunk-local flashing resets. Logs and generated fixtures are ignored under `build/validation/image-controls/`.
