# Timers and time of day (F22)

Select a Timer widget and expand **Timer / clock**. Changing a setting opts into the native timer renderer; **Reset timer settings** restores the original imported style or default lap timer. Edits are undoable and support timeline overrides/explicit reset.

**Lap elapsed time** follows the selected source's detected/recorded lap and synchronization clock. **Manual project timer** runs without telemetry or a dummy CSV. Its default anchor is the widget's Start time; **Anchor at playhead** or the explicit project-anchor field sets another origin. Delay holds the initial displayed value. After that, it counts upwards from the initial offset. **Stop and hold** caps the displayed value, so an offset of 5 and stop of 8 runs for three seconds after the delay. Hiding a group or creating a visibility segment does not implicitly reset the anchor; set one explicitly when needed.

Duration formats offer total seconds, total minutes plus seconds, hours/minutes/seconds, or automatic hours when needed. Choose 0–3 decimals and compact/noncompact leading components. Duration fractions are truncated to avoid displaying an elapsed tick early. Negative initial values are supported; this is an increasing timer rather than a countdown-rate mode.

## Wall clocks

**Time of day** supports two independent clocks:

- **Source recorded time** uses `UTC epoch at source zero + configured source time`. RCZ recording metadata supplies that epoch automatically. Synchronization, source trim and rate affect the source time normally. Other supported data formats currently require an explicit UTC anchor; relative CSV counters and clock-like headers are never guessed to be absolute timestamps.
- **Project time** uses `UTC epoch at project zero + project time`. It requires an explicit anchor and does not depend on a data input.

Use the UTC date/time picker and exact Unix-seconds field (fractions allowed) to override an anchor. The picker uses UTC; the **Display timezone** is a separate IANA identifier such as `America/Los_Angeles`. UTC/system-timezone shortcuts, 12-hour AM/PM and a timezone suffix are available. Calendar formatting handles midnight and daylight-saving transitions. Clock format components refer to local hours/minutes/seconds, whereas elapsed duration formats use totals.

An unavailable source clock displays a dash with an inline configuration message. Snapshot/export preflight rejects a wall clock without a recorded/explicit epoch instead of producing a misleading time. Invalid timezones, decimal counts and manual stop/delay settings are rejected. Formatters are cached with a lock for concurrent rendering; readings depend on clocks, never on previous frames.

## Templates and compatibility

Project files retain timer settings. Reusable templates retain mode/format/delay/offset/stop preferences, but clear project anchors and recording epochs so a new session cannot inherit an old wall time. A project-clock template needs a fresh UTC anchor. A manual timer alone creates no telemetry role; a timeline reset to a lap timer restores that dependency. Native RaceRender writing refuses these new timer settings until their encoding is verified.

Six core/one editor tests cover manual delay/offset/hold, seek order, duration formats/signs/precision, source epoch binding, midnight/DST/AM-PM/timezones, source-free imported timer rendering, preflight, template/timeline behavior and Undo. Full suite: 299 tests. `scripts/validate-timers.py` renders video without telemetry, compares running/held timers and clocks against independent constant references, checks encoded/full-vs-chunk frames and missing-anchor refusal. Native/editor live UI remains limited by `cgWindowNotFound`; no exact imported-style or native timing-algorithm parity is asserted.
