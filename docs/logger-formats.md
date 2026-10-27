# Logger formats and data sessions (F31)

Add MegaSquirt/TunerStudio **text `.msl` logs** through Add input, Finder Open With, or file drop. Both comma and tab delimiters are accepted, with an optional firmware/date preamble and units row. Time in seconds or milliseconds is normalized to seconds; unsupported time units produce an error. Standard RPM, TPS, gear, GPS latitude/longitude and supported VSS units are recognized. CLT/ECT and MAT/IAT with explicit Fahrenheit units convert to Celsius; other named channels remain available for manual assignment. Mark lines are skipped. Firmware-specific channels/units are not inferred from controller binaries or INI files. Binary MS3/MLG/FRD require conversion to text MSL in the logger software.

**GUTMA flight-logging JSON** is supported, including the format emitted by Parrot's documented `liblog2gutma` exporter. It must declare Metric units, a timezone-qualified `logging_start_dtg`, unique `flight_logging_keys`, and numeric timestamped rows. GPS, altitude, ground speed, drone velocity and battery voltage receive explicit units; other numeric channels remain available by name. Missing values remain missing. Drone velocity axes are not assigned to vehicle longitudinal/lateral G. This does not claim support for every Anafi/FreeFlight JSON dialect or encrypted `log.bin` files.

## Choosing a session

When a new file contains multiple recognized sessions, data configuration opens with a **Data session** picker. Choose the session, preview its channels/clock and Apply. Existing sources have the same picker under **Configure data…**. Every session begins at its first sample's time zero. Check synchronization after switching. The choice is saved in `.orrp`, isolated in Undo, and retained when duplicating a source. Reusable templates and generic data profiles do not carry file-specific selections. Camera data uses its separate physical-camera clock.

Recognized boundaries are:

- Repeated identical headers in CSV/TSV/text, or a clock restarting at/before the session's first timestamp. A small isolated out-of-order row retains the existing skip-and-warn behavior. Blank lines do not split a session. The header and units must remain consistent within an MSL file. Vendor-specific Alfano layouts have not been verified against a sample.
- Separate GPX `<trk>` elements, retaining segments and gaps within one track; separate TCX `<Activity>` elements. Track names/activity IDs appear in the picker. Recorded UTC is retained.
- Separate complete FIT files concatenated in one file. Multiple session messages inside a single FIT container are not yet independently selectable.
- Separate `session.json` entries in an RCZ archive, with nested channel folders isolated per session. Each session retains its own recorded UTC clock.

The CLI supports `inspect-data FILE --session 2 --time 10` and lists available session numbers/names. Source loading caches by path, settings **and selected session**, so two runs from the same file keep distinct tables. Invalid selections fail explicitly. Legacy RRP track numbers are honored when this reader can identify that session; new selections and GUTMA sources are refused by native RRP export because compatibility is unverified.

## Formats still requiring work

GTech GTR/GTS, PZRacing PRR, SpeedAngle SA, Sony MOFF and Olympus SNS/SNSLOG lack a verified layout and fixture in this implementation. The mirrored RaceRender acquisition guide names these formats but does not specify their binary structures. Sony's public support article describes MOFF as a management file rather than documenting a decoder. These formats are detected and receive a concrete CSV/GPX conversion message instead of being added as broken videos. Olympus GPS-only NMEA `.log` files continue to work through the existing NMEA reader; automatic sensor companion merging is not implemented. Do not interpret these diagnostics as native format support. Real files/documentation are still needed to finish these parts of F31.

## Validation and sources

Original fixtures cover MSL time/speed/temperature units, restarted clocks, unknown time-unit refusal, GUTMA null/invalid GPS and UTC, GPX track/segment distinctions, TCX activities, concatenated FIT, multi-session RCZ, source-cache separation, legacy selection, duplication, template stripping and malformed-format diagnostics. Editor tests cover automatic configuration offers, private preview/Apply, saved selection, unchanged sync/marks and Undo. `scripts/validate-logger-formats.py` compares second-session MSL widgets to independent CSV snapshots and marked full/chunk video. No private logger fixtures are committed. Native GUI/format parity remains unverified while CUA reports `cgWindowNotFound`.

Primary references: [MegaSquirt datalogging](https://www.megamanual.com/ms2/tune.htm), [MS3 conversion instructions](https://www.msextra.com/doc/pdf/html/Megasquirt3_TunerStudio_MS_Lite_Reference-1.3.pdf/Megasquirt3_TunerStudio_MS_Lite_Reference-1.3-47.html), [GUTMA specification](https://github.com/gutma-org/flight-logging-protocol/blob/master/Flight_logging_protocol.md), [Parrot's official exporter](https://github.com/Parrot-Developers/logger), [Sony MOFF description](https://www.sony.co.in/electronics/support/e-mount-body-ilce-7-series/ilce-7m4/articles/00007211), and the locally mirrored RaceRender data-acquisition/input-selection guide. The public GUTMA example was inspected locally as a reference; committed fixtures are original.
