# GPS start/finish and saved tracks (F19)

Select a data input, expand **Data channels & lap timing**, then open **GPS start / finish editor…**. The original source and project remain unchanged while editing. The map shows the GPS route, a cyan source cursor, a green finish gate and its forward direction.

Drag/click the map with **Snap map clicks to recorded track** enabled to select a recorded route sample. The source slider, exact seconds field, second nudges and **Use playhead** let you choose a representative driving line from any lap. **Source cursor** follows that point; **Coordinates** lets you enter decimal latitude/longitude or place a gate off the sampled line by turning snapping off. Coordinate fields retain up to eight decimal places. Map projection and inverse selection handle longitude wrap near the dateline.

**Infer heading from GPS motion** follows local motion in cursor mode or the nearest route sample in coordinate mode. At a stationary/invalid position, move to a sample with motion or enter heading manually. Heading is clockwise from geographic north; only forward crossings count. **Gate width** measures across the finish line. An optional heading tolerance rejects crossings in another direction. Optional east/west and north/south tolerances further limit where a crossing may occur, in meters.

Choose a **Minimum lap time** to reject repeated/nearby triggers. **Ignore first lap triggers** merges the initial ignored boundaries into a partial warmup interval, then counts from the next trigger. It also works with recorded lap boundaries when the GPS override is off, retaining their precise timestamps. Raw recorded lap-number columns remain available unchanged for custom gauges.

## Precision and preview

- **Interpolate GPS crossing** estimates the time/position at the forward crossing between samples. It is the default and preserves previous finish-line behavior.
- **Recorded sample crossing** uses the first sample after a forward crossing and tests tolerances at that sample. With sparse GPS, a tight coordinate tolerance can miss the gate entirely; adjust tolerances or return to interpolation.

Both modes skip missing/long-gap segments and implausible position jumps. The adaptive gap is the greater of two seconds and five median source intervals; jumps larger than the greater of 1 km and 300 m/s × interval are rejected. This is an independent general GPS algorithm, not a claim to match a logger's lap timing or RaceRender's proprietary algorithm.

**Preview laps** reparses the complete source with the draft. It lists full/partial intervals, start/end and duration. Selecting an interval moves the cursor while keeping the gate fixed. Changing gate settings invalidates the preview. **Apply** installs the previewed settings as one undoable edit, preserving source identity/timing, file path and project In/Out marks. A source or document changed while the sheet was open rejects Apply. **Cancel** leaves the project untouched. Turn off **Override recorded laps with this gate**, preview and Apply to restore recorded timing.

## Saved track recognition

Save a named gate as a new track/layout. The independent library lives at `~/Library/Application Support/OpenRaceRender/Tracks.json`, outside Documents, and starts empty. The loader searches saved track/layout names and offers gates within 50 km of the first GPS sample; **Show all saved tracks** includes the rest. Selecting a saved track explicitly loads its coordinates, heading, tolerances and precision into the draft. It does not automatically change a project merely because the location matches.

**Import… / Export…** share version-1 `.orrtracks` JSON libraries. Imports merge, skip identical entries and assign new IDs for conflicting imported IDs; existing entries are preserved. Invalid versions, coordinates, names, duplicate IDs and oversized libraries are rejected. An unreadable managed library is left intact with writes disabled and an inline error. Saving/removing/importing library entries is separate from the project's Apply/Cancel and Undo. Track files contain named finish gates, not media paths or telemetry. They do not store a session-specific ignored-trigger count; track-scoped `.orrd` profiles can include that separately.

No RaceRender track catalogue, native track-file encoding or online track feed is bundled or claimed. Custom gate settings save in `.orrp`; native project rewriting continues to refuse unverified finish-line export. Existing imported native settings retain the compatibility limits documented in the import audit.

## Validation

Six core/two editor tests cover fractional vs sampled times, axis and heading tolerances, forward-only crossings, ignored calculated/recorded triggers, gaps/teleports/stationary heading, profile/old-project compatibility, track JSON/nearby matching/collision-safe merge, map coordinate roundtrips, draft isolation, preserved marks/timing, reload and undo. Full suite: 278 tests. `scripts/validate-finish-line.py` compares both precision modes and an ignored warmup trigger with independent recorded lap boundaries, using snapshots and encoded frames. Live editor/native operation remains unverified while the computer-use service reports `cgWindowNotFound`.
