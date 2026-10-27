# Enhanced language semantics

F29 completes the specifically identified DrawTime, Print, LocName and record-query gaps, with focused tests against the supplied Enhanced language guide. These are independent implementations, with native edge cases still unverified while the UI connection is unavailable.

`DrawTime(Value, Decimals, X, Y, Color, Size, Alignment, Compact)` now applies all arguments. Decimal precision is clamped to 0–8, rounds to the nearest tick with carries, and preserves negative signs except rounded negative zero. Compact chooses the minimum component: 0 keeps hours, 1 keeps minutes, 2 permits seconds only; larger nonzero components remain visible. Hours/minutes use two-digit leading components, while seconds-only output is unpadded. Examples: value 1.234 yields `00:00:01.234` with precision3/compact0, `00:01.23` with precision2/compact1, and `1.2` with precision1/compact2. Nonfinite/unreasonably large durations draw an em dash. The guide does not specify every rounding/padding/large-value detail; these explicit rules are tested, rather than claiming exact native edge-case equivalence.

`Print` uses the bounded current-frame message sink added by F28. Background/current foreground messages appear in Compile & Test/CLI diagnostics. Historical replay does not spam the log, and ordinary preview/export has no external message destination.

`GetBestLap*` reads the overall recorded complete-lap best, including later laps in the file. `GetCurBestLap*` reads only completed laps at the current source time. `GetPrevBestLap*` reads the best before the most recently completed lap began; it therefore differs when that latest lap improved the record. Exact finish times include the newly completed lap in current-best. `GetLapTime` returns zero for incomplete laps and can query a recorded complete lap elsewhere in the file. Missing records return zero. The existing general best-lap validity filter (complete and longer than five seconds) remains; no new native timing algorithm is claimed.

## Location and input names

LocName now resolves from an explicit data-source location override, recorded RCZ `trackName` or CSV preamble `Track name`/`Location name`/`Location`, then a nearby user-saved track within 5 km of the first valid GPS sample. Missing/unknown names stay empty. There is no online geocoding or proprietary worldwide location catalogue. Resolution happens when loading/configuring data, never as filesystem/network work during a frame.

In **Configure data source**, Location for scripts offers an override; an empty explicit override clears the name, while disabling the override restores automatic metadata/track lookup. Loading/naming a track in the GPS gate editor can apply its name. An unchanged inferred name is not silently turned into an override. Profiles carry location overrides only when track settings are explicitly included; portable templates strip source configuration. Explicit overrides require `.orrp`; native encoding is unverified and the legacy writer refuses them. Recorded file metadata remains in the source file as usual.

InputName now uses the project's current input label (including a renamed/join-root label), falling back to the telemetry title only when no project label is provided. Location/input context participates in persistent background cache identity, preventing stale text after renaming. Script editor/CLI tests receive the same context and source-rate clock.

Documented numeric/string restrictions are enforced at runtime: mixed arithmetic/concatenation needs explicit FormatNumber conversion, numeric conditions/unary operators require numbers, and function parameters distinguish text from numeric values. Syntax and current-frame testing remain separate; valid but unexecuted value-dependent branches still need testing with representative inputs.

## Validation

Six new core cases plus one editor workflow case and RCZ metadata assertions extend the suite to 343 passing tests locally, with no skips using the authorized library/graphics services. Coverage includes exact DrawTime-versus-literal-text pixels, precision/carry/sign/components, overall/current/previous records at boundaries, partial laps, location metadata/override/reset/nearby-track/profile scope, renamed-input/location persistent cache invalidation, type errors and transactional location Apply/Undo preserving timing/marks. Installed Enhanced styles render at early/later sample times under the stricter type rules; this checks supported execution, not universal visual parity.

`python3 scripts/validate-script-semantics.py` authors original code and telemetry. It verifies numeric diagnostic results at lap boundaries, compares actual encoded time/name/record text with independent literal references, tests an override, and compares a low-resolution full 60-second session with a nonzero chunk. Logs/artifacts remain under ignored build/validation/script-semantics. Existing script authoring acceptance is rerun after these changes.

Live native formatting/padding/previous-record and location-database behavior remain unverified; the explicit rules above describe OpenRaceRender's tested behavior. The guide says LocName behavior may change; this implementation uses portable source metadata and the user's own saved tracks.
