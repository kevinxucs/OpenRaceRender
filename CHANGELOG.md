# Changelog

## Unreleased

Initial open-source development version, identified as `0.1.0` by the app bundle.

### Added

- Native SwiftUI editor and command-line tools for telemetry video projects.
- Independent RRP3 project, rrt1/2 template, and rro1/2/3 style readers, including compact video-position presets.
- Native JSON projects and reusable layouts/styles, with input remapping.
- Timeline segments, camera switching, trim/rate/delay controls, joined clips, event synchronization, and shared preview/export composition.
- Native gauges, graphs, maps, G-force, gear, lights, lap timing, and temperature displays.
- CSV/TSV, GPX, TCX, NMEA, VBO, and basic FIT activity import; channel assignments, calculated fields, and GPS finish-line lap detection.
- Native H.264/AAC export, time/lap ranges, PNG snapshots, and media acceptance checks.
- Project documentation, compatibility audit, contribution guidance, and macOS CI.

### Known limitations

Feature and rendering parity with RaceRender is incomplete. See the [feature audit](docs/racerender-feature-audit.md), including legacy timeline/adjustment import, arbitrary Enhanced scripts, 360° workflows, grouping, and network transfer.
