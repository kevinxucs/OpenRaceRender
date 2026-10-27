# Data assignments and reusable profiles (F17)

Select a data input and open **Data channels & lap timing → Configure columns / data profiles…**. The sheet edits a private draft. Map recorded headers to session time, longitude/latitude, altitude, GPS accuracy, lap, speed, heading, RPM, gear, longitudinal/lateral G, throttle, brake, distance and temperatures. Automatic retains the importer's detected role. Missing profile headers remain visible until you remap them or choose Automatic.

**Time units per second** is 1 for seconds or formatted clocks, 1000 for millisecond counters. The first timestamp becomes zero. An explicit clock must have at least two distinct finite increasing timestamps; an absent or backwards clock fails rather than falling back to another field. Duplicate timestamps retain the last sample. CSV/TSV/TXT files whose clock header is unrecognized open this sheet during import, with recorded header/sample rows. Cancel adds nothing and creates no undo step.

Speed normally follows recorded header units. **Override recorded speed units** applies `raw × multiplier`, interprets that result in the chosen units, and then converts to the unit used by each widget. GPS accuracy can be multiplied into meters. Heading adjustment/reversal, gear calibration, calculated fields and finish-line controls remain in the input inspector and are included in profiles.

Choose **Preview configuration** to parse the entire source with the draft, see sample count/duration and scrub role values. Changing a draft invalidates its preview. Apply installs the exact previewed configuration in one undo step. It retains the source ID, path, name, synchronization offset, source timing and project video marks. Requests cannot apply to a replaced document or a source edited since opening the sheet. Source duration updates to the configured clock; export marks are not automatically rewritten if they extend beyond the new duration.

## Sharing settings

**Export profile…** saves a version-1 UTF-8 JSON `.orrd` file. It contains a name, `settings` in the same format used by `.orrp`, and `includesTrackSettings`. It stores no media path, project marks, camera settings or synchronization offset. **Include track / finish-line settings** defaults off; otherwise importing a logger profile preserves the destination's finish line and ignored-trigger count. Importing a track-specific profile replaces those values explicitly.

**Import profile…** replaces the draft's data settings. Review all mappings and preview before Apply. Named headers, not positions, prevent silently choosing the wrong column in another logger file. A profile can be exported with unresolved names for later remapping; Apply requires available columns and valid settings. `.orrd` is imported from the data sheet rather than opened as a project in Finder.

Native RaceRender data-profile file interoperability is unverified. Do not rename such files to `.orrd`. The guide documents profile import/export but does not specify its file encoding. Explicit speed-unit overrides and accuracy conversions are retained in `.orrp`; rewritten native `.rrp` export conservatively refuses these options until their representation is verified. Existing native speed-conversion behavior remains compatible.

## Validation

Five core and three editor tests cover header inspection, custom/clock-formatted/millisecond time, bad and missing clocks, speed/accuracy conversions, lap remapping, idempotence, profile scope/roundtrip/calibration, invalid settings, safe import, source identity, marks/timing, project reload, undo and stale requests. Full suite: 263 tests, no failures. `scripts/validate-data-profiles.py` compares mapped custom-clock data against independently authored canonical data in snapshots and encoded video chunks. No private or vendor fixtures are committed. Live native/editor UI operation remains unverified while the computer-use service reports `cgWindowNotFound`.
