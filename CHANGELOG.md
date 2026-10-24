# Changelog

## Unreleased

Initial open-source development version, identified as `0.1.0` by the app bundle.

### Added

- Video-backed lap/event synchronization wizard, exact-time navigation, visible In/Out controls and timeline range marks.
- Blank layout, draggable widget palette, named template/style saving, embedded gauge artwork and native template previews.
- Remembered export ranges/settings/destinations, consistent toolbar/keyboard/CLI defaults, and safe numbered repeat filenames.
- Workflow regression coverage for synchronization, reusable layouts, source remapping and moved-project asset paths.

### Fixed

- Widget palette dragging across the AppKit video preview: native mouse tracking places widgets at release, provides a drop indicator and cancels outside the canvas. Completed live template-design/save/reuse validation.
- Library discovery and thumbnail reads blocking the main thread; custom and bundled libraries now load asynchronously.
- Missing session dirty/undo tracking, preview selections creating edits, and duplicated native save extensions.
- Concurrent multi-file drops colliding on source numbers, template source placeholders remaining unbound, incompatible source choices, retained session configuration in templates, and video/audio relink duration.
- Reloading telemetry after undoing a removed source, and image/gauge references after relocating project folders.

### Earlier additions

- Original macOS app icon, generated artwork source and automatic multi-resolution ICNS packaging.
- Optional self-contained app packaging for local RaceRender libraries, with automatic discovery, checksummed manifests, user overrides and separate template/style/image/video-position categories.
- Matched 4K chunk comparisons: imported camera picture controls, HSV saturation and multiplicative brightness, legacy Rec.709 decoder compatibility, recorded longitudinal G, map stroke/zoom and native text corrections.
- Hardware-assisted H.264 High Profile export with explicit video/AAC bitrates, Rec.709 tags, direct GPU camera rendering and cached map traces.
- Full-session validation fixes: integer widget raster sizes, imported video aspect flags, telemetry-end HUD visibility, exact rational export timebases, and matching widget/destination bitmap formats.

- Local legacy artwork decoding and a bounded Enhanced drawing interpreter; traditional widgets honor saved fonts, colors, ranges and orientation.
- Live-reference widget corrections: aspect-preserving bitmap placement, clockwise gauge sweeps, short needles, saved layer visibility, rounded automatic-range bars, text outlines/alignment, thermometer labels, additive RGB blends, best-lap map traces and chronological lap timing.
- Peak/base speed and turn G-force banners: Auto activation repair, built-in channel/unit resolution, persistent script replay with bounded checkpoints, stable seeking and partial exports, and visible canvas-edge text.
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
