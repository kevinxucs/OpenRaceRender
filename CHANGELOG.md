# Changelog

## F12 — Guided project setup

- Three-step setup connects file import, primary trim/length, per-data synchronization, selected-source template mapping and widget/data configuration.
- Exclusive automatic/input/manual length controls, remembered new-session units and setup preference, project notes, bound-source removal/undo and nested synchronization preview handoff. See [workflow and validation](docs/project-setup.md).

## F11 — Visual source trimming and crop

- Private source-bound trim drafts with first/last previews, frame steps, playhead capture and data visualization. Preserve synchronization, playback settings and export marks.
- Graphical pixel crop, corner resizing, movement, edge fields, nudges, zoom and result preview for video/stills. Image-source picture settings now render and survive portable template export. See [workflow and limits](docs/source-tools.md).
- Simplified timeline extent calculation to avoid a type-checking timeout on the CI Swift toolchain.

## F10 — Timeline editing and inheritance

- Shared zoom/window navigation, event selection/details, exact-time/frame moves, following-event shifts and per-field inherit/freeze controls. Undo/redo keeps the retimed event selected.
- Explicit optional-parameter/renderer clears, restored group child history and protection for ambiguous nested edits. Fixed an intermittent RRT input-delimiter collision with deterministic seed coverage. See [workflow and limits](docs/timeline-editing.md).

## F09 — Shared widget background editor

- Private import/drop/clear drafts with zoom, pan, rotation, aspect, chroma key, PNG export, external edit/reload and whole-widget preview. Apply embeds the result in one undoable base/segment edit.
- Explicit native timeline background clearing and conservative legacy refusal for an unverified clear event. See [workflow and validation limits](docs/background-editor.md).

## F08 — Data-controlled images

- Embedded artwork chooser, proportional and inclusive threshold mappings to visibility/opacity/rotation/brightness/hue, and deterministic flashing. Source selection and settings support undo, segments and portable templates.
- Shared cached image rendering, telemetry dependency checks, native E Image settings and bounded length-prefixed bitmap import/export. See [controls and validation limits](docs/image-controls.md).

## F06 — Configurable 2D graphs

- Time, distance and channel axes; moving, centered, fixed cursor and progress modes; automatic/manual ranges, lap/source ranges, points/lines and saved appearance controls.
- Shared cached graph rendering across preview and export, peak/gap preservation, timeline/template persistence, type-35 import migration and verified graph legacy writing. See [controls and validation](docs/graphs.md).

## F04 — Subset template export

- Per-display checkboxes, group branch selection, All / Widgets only / Current selection / None presets, and editable exported object and input-role names. Draft edits leave the session unchanged.
- Preserve Command-A text selection in template name fields and keep required camera/audio groups when replacing the overlay.
- Retain required ancestor groups without unselected siblings, include input switches and saved group-event history, and preserve portable artwork. Selected reusable styles support multiple objects and choose RRT for grouped subsets. See [workflow](docs/template-export.md).

## F03 — Groups and multiple selection

- Command/Shift selection, canvas marquee, group/ungroup, nested groups, combined move/resize, numeric selection geometry, subtree copy/delete/order and one-step drag undo.
- Stable parent identities prevent repeated templates from cross-wiring groups. Group edits retain child timeline events and native saves retain the history needed to restore an earlier member event.
- Shared visibility/time/opacity gates cover overlays, cameras, snapshots and audio. Fixed interpolated audio fading through hidden intervals using the existing sample-level processing gate. Added original synthetic export acceptance and AppKit mouse-event coverage. See [workflow and native validation](docs/grouping.md).

## F02 — RaceRender file writing

- Independent RRP3/RRT2/RRO2 serialization, including native authoring without original project bytes, source-role remapping, marks, supported source/display settings, timeline payload/audio/artwork changes and virtual joins.
- Legacy template/style format picker and project export command; CLI conversion selects the output format by extension. Unsupported representations fail before writing a destination.
- Native RaceRender checks resolved template/style integrity records and caught black tint defaults, gauge mode/precision/numbering/interval/gradient fields, embedded-image type and source-rotation import errors. Added synthetic media acceptance and writer regression coverage. See [scope and validation](docs/legacy-export.md).

## Unreleased

Initial open-source development version, identified as `0.1.0` by the app bundle.

### Added

- Structured RRP3 source/project/timeline import with joined streams, trim/rate/delay/loops, notes/length binding, crop/rotation/flip, audio gain/balance/routing and supported data assignments/calculations. Unknown settings remain in the original bytes and limitations appear in the import report.
- Expanded vector gauge designer: needle/dual/filled modes, automatic range, smoothing, nonlinear scale, needle geometry, separate marks/pins, caption typography/positions and independent color thresholds/gradients.
- Text font/size/style/alignment/outline and fit controls, plus seven shape types with gradient fills and outlines; native saves, styles and inherited segments retain the settings and artwork.

- Apex GT track/road layouts: circular speed/RPM dials, session trip odometer, graphical pedal travel and a top-down car with temperature-colored tyres and individual pressure/temperature readings. GT presentation is optional, preserving earlier digital Apex layouts and metric unit preferences.
- Original Apex Telemetry and Apex Road templates with 30 editable vector instruments, tyre pressure/temperature display, steering/yaw, completed peak/minimum speeds and turn G, plus native instrument settings and CLI template generation. Cached routes and extrema keep seeking and chunk exports deterministic.
- Searchable draggable library styles and individual widgets from saved templates, a compatible style chooser in the inspector, sample telemetry for template design, proportional resizing, canvas alignment and pixel nudges.
- Editable imported bar/script ranges, script captions/font size, trigger threshold and Color A–H slots, retained in native projects and reusable templates.
- Manual telemetry synchronization by −1/+1 video frame, using the project frame rate and the data input's playback rate; offset entry retains six decimal places.
- Native RaceChrono RCZ session import through Add input, drag/drop, Finder and the CLI, including GPS/CAN/sensor clocks, unit conversion, gyro calibration, recorded laps, resumed recordings, validated relinks and native project reopen. Includes ZIP integrity checks and RCZ/CSV data and render comparisons.
- Hue and sharpness import, editing, saving and rendering; signed picture-adjustment sliders and numeric entry, plus a shortcut from video displays to their input picture settings.
- Managed library under Application Support, explicit non-overwriting library import in the UI and CLI, and a Finder shortcut for managing custom layouts.
- Optional existing signing identity through `--sign-identity` or `OPENRACERENDER_SIGN_IDENTITY` for builds that need stable macOS permission identity.
- Video-backed lap/event synchronization wizard, exact-time navigation, visible In/Out controls and timeline range marks.
- Blank layout, draggable widget palette, named template/style saving, embedded gauge artwork and native template previews.
- Remembered export ranges/settings/destinations, consistent toolbar/keyboard/CLI defaults, and safe numbered repeat filenames.
- Workflow regression coverage for synchronization, reusable layouts, source remapping and moved-project asset paths.

### Fixed

- Saved 4:3/16:9 workspace aspect import and a virtual joined-stream root reading a nonexistent picture record at end of file.
- Changing a widget style resetting its position, size, data binding and timeline. Incompatible widget types are rejected; appearance changes retain the existing instance and support undo.
- Imported bar/script range controls changing only the native inspector fields instead of the payload used for rendering.
- Empty template source roles collapsing the design timeline to one second.
- Recurring blank composition after redraws or synchronization-preview transitions. Video now uses a dedicated layer-hosting view, with the selection overlay as a sibling; AppKit cannot draw over AVPlayerLayer's opaque contents. The canvas and synchronization wizard explicitly hand off player ownership and detach discarded preview views.
- Imported template channel names becoming corrupted by an extra decoder-state advance. Known affected native Enhanced payloads are repaired on open, preserving explicit channel and segment overrides. Automatic now overrides imported script channels, including gear, shift lights, temperatures and peak speed/G displays; the inspector shows the matched source column or an unavailable-channel message.
- Numeric legacy displays interpreting their color/text bytes as channel names.
- Repeated missing-gear channel lookup slowing synchronization event discovery for recordings with many channels.
- Finder project opens leaving a blank editor: handle URL and filename events, retain early launch requests until the editor is ready, and reuse one editor window. Repeated in-flight requests are coalesced, superseded loads are cancelled, and launch arguments run only once.
- Failed relinks replacing the original path before validation, image relinks leaving the displayed file unchanged, and exports silently omitting missing sources. Recovery now retains settings and supports undo; export validation follows the selected span, camera switches, joined clips and embedded artwork, with visible feedback in the export sheet.
- Missing RRP3 green/red output markers, including default export bounds and millisecond labels. Unchanged markers survive compatible RRP copies; native saves preserve edited bounds.
- Picture controls exposing raw 0–2 multipliers. Brightness, contrast, saturation and sharpness now use −100…+100 with zero neutral; hue uses −180°…+180°. Existing project values remain compatible.
- Composition playback turning black after AppKit redraws: the video player now owns the preview's backing surface, with regression coverage for resizing, reattachment and player replacement.
- Repeated Documents permission triggers from automatic library discovery and template-save defaults. Default library access now stays in Application Support and bundled resources; old Documents libraries require a one-time explicit import.
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
