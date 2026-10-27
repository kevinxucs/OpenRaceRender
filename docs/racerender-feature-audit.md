# RaceRender 3 feature research and adaptation

Research date: 2026-10-22. Reference application: installed RaceRender 3.7.3 Ultimate for macOS. This audit covers the public guide and hands-on inspection. Status describes the current source, not intended future behavior.

The [2026-10-25 full local-guide review](guide-gap-review.md) provides 36 scoped implementation choices, source evidence, and corrections to assumptions about which features the guide actually documents. The user selected F01/F05/F07 first and subsequently authorized the remaining queue; [feature progress](feature-progress.md) records the current implementation.

## What the public guide establishes

RaceRender is organized around concurrent input streams and display objects. Sequential editing uses joined inputs. A display can change source, visibility, geometry or other properties at a timeline segment; untouched properties inherit from earlier segments. Input trimming, synchronization, rate and project delay operate separately from these display changes. These distinctions now exist in OpenRaceRender's model and compositor. Sources: [Basics](https://racerender.com/RR3/docs/Basics.html), [Main screen](https://racerender.com/RR3/docs/Main.html), [Timeline segment editor](https://racerender.com/RR3/docs/TimelineEdit.html).

The guide distinguishes adjustments that affect an input everywhere from display-specific settings. It describes source playback rate, trimming, cropping, rotation, mirroring, color controls, audio controls, channel assignments, calculated fields and event synchronization. OpenRaceRender now exposes a substantial subset through its source and display inspectors. Sources: [Input configuration](https://racerender.com/RR3/docs/InputFileEdit.html), [Trimming](https://racerender.com/RR3/docs/InputFileTrim.html), [Cropping](https://racerender.com/RR3/docs/InputFileCrop.html), [Synchronization](https://racerender.com/RR3/docs/InputFileSync.html), [Display properties](https://racerender.com/RR3/docs/DispObjEdit.html).

Reusable layouts and single-display styles are separate concepts. Gauge design includes range, sweep, orientation, labels, needle and face styling. Export supports entire projects, explicit time spans and lap ranges. Sources: [Template creation](https://racerender.com/RR3/docs/TemplateCreate.html), [Gauge designer](https://racerender.com/RR3/docs/DispObjGaugeDesign.html), [Video export](https://racerender.com/RR3/docs/CreateVideo.html).

For the full advertised scope, consult the vendor's [feature comparison](https://racerender.com/RR3/Features.html), [format list](https://racerender.com/RR3/docs/TechInfo.html), [data overlay guide](https://racerender.com/RR3/docs/HowTo-Datalogger.html), [GPS finish-line guide](https://racerender.com/RR3/docs/InputFileSetLap.html), [Enhanced scripting reference](https://racerender.com/RR3/docs/DispObjEnhanced.html), [360° guide](https://racerender.com/RR3/docs/Pano360.html), and [network transfer guide](https://racerender.com/RR3/docs/Transfer.html).

## Hands-on observations

The installed application was actually launched and operated, using a local RRP project and its media. The following were observed through the native UI:

- The New Project Menu offers data-overlay, picture-in-picture, split-screen, panoramic, dual-data and stereoscopic templates, plus a setup wizard.
- The supplied project loaded its video, telemetry and display list. Playback/pause and frame advance were exercised.
- The data synchronization tool showed independent source start, project delay and playback rate. Its wizard listed movement, stop, lap-boundary, gear and altitude events.
- The Lap List showed partial staging/in-laps and a best lap. Double-clicking a lap moved the main playhead to that lap's project time.
- A speedometer's properties exposed lower-left percentage geometry, aspect preservation, opacity, source/channel, range, sweep, colors, labels, a gauge designer and timeline controls.
- A temporary display segment was created at ten seconds. Its segment selector showed the base interval ending there and the new interval continuing to the end. The temporary segment was then removed. The source RRP was not saved.
- Create Video exposed entire-project, time-span and lap-range choices; output profiles; workspace/aspect ratio; resolution/frame rate; audio format; bitrates; scaling quality; spherical metadata and optional upload. Lap-range mode was selected to inspect its first/last controls. Subsequent validation rendered short native 4K/59.94 chunks and compared exported frames and isolated picture-control snapshots. No upload was used.
- Video input settings showed trim/rate, audio volume/channel handling, crop/zoom, flip/rotation, brightness, contrast, saturation, hue, sharpness, chroma key, colorization and sphere controls. That dialog was cancelled.

These observations informed behavior. They do not establish that every reference feature has been fully reproduced or that native artwork matches proprietary styles.

## Implementation matrix

“Implemented” means usable in native projects. “Partial” identifies a specific remaining limitation.

| Feature | OpenRaceRender status | Location or remaining work |
| --- | --- | --- |
| Native macOS editor, open/save, drag/drop, relink | Implemented | SwiftUI editor, `.orrp` JSON; missing-file notice, validated undoable replacement and range-aware export asset checks |
| Preview play/pause, frame stepping, scrubbing, mute, PNG snapshot | Implemented | Shared compositor and AVPlayer |
| Concurrent cameras, PiP and split-screen | Implemented | Multiple video objects and percentage geometry; extra cameras default to PiP |
| Layer order, duplicate, delete, opacity, positioning/resizing | Implemented | Editor and compositor; Shift snapping |
| Source trim, delayed project start and playback rate | Implemented | `InputTiming`, `InputPlacement`; source time mapped once for all consumers |
| Joined sequential media | Implemented | Join after previous source; unjoin; children ordered by the input list |
| Sync offset and manual event alignment | Implemented | Synchronization sheet, frame adjustment and source event time |
| Data event discovery | Implemented subset | Starts/stops, recorded lap starts, first shifts; aircraft event detection absent |
| Timeline editing and inheritance | Implemented with documented limits | Zoom/window navigation, retime/shift, field inheritance, explicit parameter clears and group restoration; [scope](timeline-editing.md) |
| Per-display inherited timeline segments | Implemented subset | Source, visibility, geometry, opacity, text, color, channel, picture, gauge, typography, shape, artwork and audio; discrete changes |
| Timeline tracks and markers | Implemented subset | Select, scrub, create/remove, reset inheritance; no zoom/shift tool yet |
| Timed titles/captions and camera switching | Implemented | Segments and active start/end span |
| Explicit project length and export marks | Implemented | RRP3 output-flag import, visible In/Out controls, keyboard shortcuts, timeline boundaries and saved export defaults |
| Crop/digital zoom, aspect preservation, rotation and flip | Implemented | Normalized crop fractions; source and media-display picture settings |
| Brightness, contrast, saturation | Implemented | Signed adjustment controls with existing multiplier storage; shared preview/export pipeline |
| Hue and sharpness | Implemented | RRP3 import and native roundtrip; HSV hue rotation, blur/sharpen controls; sharpness edge response can differ from RaceRender |
| Colorize, chroma key | Implemented native workflow | Source/display video/image controls, key sampling/ranges/softness and tint/spectrum; [validation and legacy limits](picture-effects.md) |
| Audio mixing and source volume | Implemented subset | Audio follows active display source/visibility; preview mute |
| Audio balance, channel swap/mono routing and object-specific gain | Implemented | Source stereo/swap/left/right/mono routing and display gain/pan, including timed changes |
| Input looping | Implemented | Repeated placements to project length; shared video track and separate timed audio |
| Configurable 2D graphs | Implemented | Time/distance/channel axes, seven plot modes, ranges, styling, timeline/templates and legacy graph writing; [scope](graphs.md) |
| Gauges, bars, G-force, gear, lights, temperatures | Imported styles plus native fallbacks | Saved fonts/colors, procedural scripts and decoded artwork are used where supported |
| Gauge designer | Implemented subset | Range, sweep, orientation, reverse direction, labels, divisions, numbering scale, decimals, redline and background |
| Expanded gauge design | Implemented | Dual/filled modes, nonlinear split, geometry, marks/pins, independent captions and threshold colors/gradients; see validation limits |
| Shared widget background editor | Implemented with live-validation limits | Import/drop, transform/key, export, external edit/reload and whole-widget draft preview; [scope](background-editor.md) |
| Data-controlled embedded images | Implemented with native validation limits | Proportional/threshold visibility, opacity, rotation, brightness, hue and flashing; [scope](image-controls.md) |
| Text, custom images/logos and shapes | Implemented | Text typography/outline, seven shapes, gradient fill and outline; reusable styles embed image bytes |
| Object grouping | Implemented | Multiple selection, marquee, nested groups, combined edits, timeline geometry, subtree operations and inherited visibility/audio; [native observations and validation limits](grouping.md) |
| Subset template export | Implemented | Per-object selection, exported names and input-role names, necessary group ancestors, source-switch/history roles and portable artwork; [workflow](template-export.md) |
| Auxiliary channels and source channel assignments | Implemented | Data inspector and object channel picker |
| Calculated data fields | Implemented subset | Affine `source × multiplier + offset`; other arithmetic operators absent |
| Interpolation and sparse sample handling | Implemented | Duplicate merging, forward fill, numeric interpolation |
| Recorded lap timing, best lap, lap seeking, lap export | Implemented | Timers, lap list, export range conversion includes source timing/rate |
| GPS finish-line lap detection | Implemented estimate | Forward crossing of a width-limited gate, interpolated crossing time, minimum lap duration |
| Recognized-track database and edited lap times | Not implemented | Track database and manual lap overrides |
| Track map and vehicle position | Implemented subset | Native full course; legacy best-lap trace, saved colors, edge, start checker and vehicle arrow; no map background editor or ghost comparison |
| Best-lap delta | Implemented subset | Requires compatible distance and recorded/calculated lap boundaries |
| GPS speed fallback and four speed units | Implemented | mph, km/h, m/s, knots |
| Derived heading, G-force and gear estimation | Partial | Longitudinal G uses the recorded channel when available, otherwise a two-second speed-difference window; heading and gear estimation remain absent |
| CSV/TSV and RaceChrono CSV | Implemented | Bounded text reader with preamble/header recognition |
| RaceChrono RCZ sessions | Implemented subset | Independent stream clocks, units, recorded laps, resumed fragments and native project reload; [scope and measured validation](rcz-import.md) |
| GPX/TCX | Implemented subset | Timestamped track points and common sensors; not every vendor extension |
| NMEA | Implemented subset | RMC/GGA/GLL; GP/GN talkers and valid fixes; no camera-container extraction |
| VBO | Implemented subset | Common whitespace sections; no claim of every device-specific variation |
| FIT | Implemented subset | Activity records, standard GPS/sensors, byte order, compressed time, integrity checks; unknown/developer fields skipped |
| H.264/HEVC camera media and common audio/images | Host decoder support | AVFoundation/AppKit determine actual codec availability |
| `.rrp` input and display import | Expanded subset | Structured RRP3 timing, joins, timeline, notes/length, supported data/picture/audio and display settings; specialized effects remain partial |
| Legacy picture import | Partial | Camera brightness/contrast/saturation/hue/sharpness and decoder color compatibility imported; colorize, chroma key and other operations remain opaque |
| Legacy timeline and join import | Implemented subset | Source/geometry/visibility/opacity/style payload/artwork/audio; unknown flags reported. Export profiles are application preferences outside the RRP |
| `.rrt` and `.rro` import | Styles and artwork supported | Embedded BGRA artwork, compressed containers, traditional styling and Enhanced scripts; font metrics and unsupported effects can differ |
| Template/style browsing and input remapping | Implemented | Installed legacy library plus native `.orrt` |
| Original Apex templates | Implemented | Track/road layouts with 30 native vector instruments, tyre data, steering/yaw, cached route/extrema and editable instrument settings; see [Apex templates](apex-template.md) |
| Design with styled widgets | Implemented | Searchable drag palette for basic widgets, local styles and template components; compatible style chooser preserving geometry/bindings, design samples, alignment, proportional resizing and pixel nudges; see [designer validation](template-designer.md) |
| Reusable layout/single-display export | Native and supported legacy formats | `.orrt`, RRT2 and RRO2; previews, source roles, embedded artwork and integrity records. Legacy compatibility is checked before writing; [scope and native validation](legacy-export.md) |
| Rebuilt RRP project export | Implemented subset | Added/removed/reordered displays and inputs, marks, source settings and supported timeline records; native-only displays/settings are explicitly refused |
| Enhanced script execution/editor | Bounded interpreter and authoring editor | Private source/canvas/font drafts, cancellable compile/test messages, timeline/Undo and CLI; [scope and remaining semantics](script-editor.md). All 56 installed styles passed earlier local rendering coverage; full parity remains incomplete |
| H.264 MP4 export, audio, 4K and selected ranges | Implemented | Native export; resolution, FPS, project/time/lap ranges |
| Manual bitrate, output profiles, audio format/scaling quality | Implemented native workflow | Local/internet/TV and user profiles, independent fit/reshape output workspace, border/scaling, mono/stereo/disabled 44.1/48 kHz AAC and bitrate controls; [limits](output-settings.md) |
| 360° workspace, fisheye flattening and spherical metadata | Not implemented | Projection and MP4 metadata work remains |
| Stereoscopic/anaglyph color-channel compositing | Not implemented | Specialized composition modes |
| TrackAddict network/WiFi transfer | Not implemented | Local import only |
| Direct upload and portable media packaging | Not implemented | Export video and manage media locally |
| Setup wizard and side-by-side synchronization | Partial | Video-backed lap/event data sync wizard with exact time entry and frame stepping; no general multi-camera setup wizard |

## Verification

All 255 tests pass with the local-library checks and graphics services available (CI skips optional local-library checks). The test suite covers parser bounds, legacy codec/patch behavior, native round trips, timeline inheritance, trim/rate/delay mapping, joined-clip cut boundaries, lap export range conversion, GPS finish-line crossings, calculated fields, GPX/TCX/NMEA/VBO import, FIT endian/scaling/compressed timestamps/checksums, RCZ clocks/units/calibration/resumed fragments/integrity, Finder input dispatch and project reopen, picture transforms, widget aspect fitting, gauge direction and layer visibility, automatic bar ranges, Enhanced label layers/RGB blends, sRGB samples, chronological best laps, speed-derived acceleration, interpolated lap delta, Auto activation migration, persistent seek/rewind behavior, state isolation, unit conversion, canvas-edge text, markers, signed picture controls, preview surface layout, validated relinks and export dependencies. Channel-selection regressions cover decoder skip positions, recovery of affected saved channel names, Automatic overriding imported payloads, explicit/segment overrides and unavailable fields; see [channel selection](channel-selection.md). Preview regressions also cover hosted video contents, canvas/wizard handoff, teardown and frame-based telemetry offset adjustments; see [preview lifecycle](preview-lifecycle.md).

The media acceptance script generates disposable camera clips, renders native H.264/AAC, and checks actual output pixels and audio. It covers trim/rate/join, exact visibility changes, audio gating, source switching, layers and equivalent RCZ/CSV overlays. Generated media and external samples live under ignored `build/validation`.

The full installed legacy library contains 61 templates and 303 style files (255 main styles, 28 image styles and 20 video-position presets). Structural validation reads all 364 files and 1,091 display objects without failures, including compact presets with no thumbnail. The sample RRP imports 18 supported displays and its telemetry. This is deliberately separate from a claim of pixel-identical output.

Additional format references: [TopoGrafix GPX schema](https://www.topografix.com/gpx/1/1/), [Racelogic VBO specification](https://developers.racelogic.co.uk/Portal/Tutorials/tutorialVBOfilestructure.html), [Garmin FIT protocol](https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html), and the [official Garmin profile definitions](https://github.com/garmin/fit-python-sdk/blob/main/garmin_fit_sdk/profile.py). These were used as format references; no SDK dependency was added.

## Original widget styles and artwork

The importer now decodes embedded full-resolution BGRA bitmap containers, including raw DEFLATE records, and retains the original bytes. The renderer reads traditional widget colors, fonts, ranges and geometry. A bounded interpreter runs the drawing assets stored in local Enhanced styles, covering assignments, conditionals, math, telemetry access and drawing primitives. It has no host evaluation, file or network interface, and limits source size, instructions, nesting and canvas allocation.

Local checks render all 56 Enhanced styles in the installed library and compare representative gear/thermometer/gauge output against stored vendor previews. These are coverage and visual checks, not a claim of pixel-identical output across all styles or platforms. Font availability, frame-grid replay sampling, exact gradients, specialized parameters and unsupported effects remain practical limits. No vendor artwork, scripts or template files are included in this repository. They are read from the user's installation or imported project. The [vendor license](https://racerender.com/RR3/License.txt) does not grant general standalone asset redistribution.

### Live rendered-frame comparison, 2026-10-23

RaceRender 3.7.3 was operated again and its own BMP snapshots were saved at 300 and 600 seconds. Those 1000×560 preview images were compared with OpenRaceRender renders of the session's layout and telemetry at the same times. The reference application recovered its previous session after becoming unresponsive during the first load. Source recordings and the original RRP were not overwritten; comparison files remain under ignored `build/validation/reference`.

This exposed errors that thumbnail-only checks missed. Saved bitmap dimensions and the Maintain Aspect Ratio flag now determine a centered content rectangle. Traditional widgets render at their saved raster resolution before scaling. Gauge rotation is relative to South and sweeps clockwise by default; saved needle tips/tails, major/minor marks, alternate interval numbering and disabled number/face colors are respected. The throttle bar uses its measured automatic data range and rounded shaded background. Enhanced text labels are a separate layer with saved font/position settings. RGB blending uses a brighter additive transition, and explicit sRGB canvases preserve saved color values.

The map's selected best lap removes the pit-lane branch from its trace and uses saved trace/edge colors, the start checker and vehicle arrow. Current-best lap displays now consider completed laps at the playhead rather than future laps; the distance-based delta interpolates between samples. The legacy automatic longitudinal G-force follows a two-second speed-difference window, matching the displayed acceleration at both sampled times. These checks improve the tested layout; they do not establish pixel parity for every style, frame, persistent animation or output profile.

## Next compatibility work

Structured source/timeline import, representable legacy writing, grouping and arbitrary subset template export with role naming have since been added. Graph axes and time windows (F06) have also been added; data-controlled images (F08) have also been added; background editing (F09) has also been added; timeline editing (F10) has also been added; visual trim/crop (F11) has also been added; guided project setup (F12) has also been added; side-by-side camera synchronization (F13) has also been added; sequence editing/time fillers (F14) has also been added; shared heading/G estimates (F15) have also been added; calibrated gear estimation (F16) has also been added; previewed data assignments/conversions and reusable profiles (F17) have also been added; source/gauge smoothing controls (F18) have also been added; map-based GPS finish/track-library tools (F19) have also been added; shared two-run maps/lap ghosts (F20) have also been added; map display editing (F21) has also been added; configurable manual timers/time-of-day clocks (F22) have also been added; per-display audio/routing and mono normalization (F23) have also been added; native keying/colorize controls (F24) have also been added; independent preview/audio/full-screen controls (F25) have also been added; output profiles/workspace/border/audio formats (F26) have also been added; camera-free preview/export (F27) have also been added; Enhanced script editing/testing (F28) has also been added, followed by the remaining IDs in the [implementation queue](feature-progress.md). Remaining font/gradient and image-container differences, track/ghost tools, 360° handling and file transfer still need targeted validation.

## Peak speed and turn G-force banners

The two supplied peak banners are Enhanced displays with Auto activation and the persistent-variables flag. Auto was incorrectly read as hidden, the speed/G-force display kinds bypassed channel decoding, and each foreground render restarted the script variables. Their text also used the canvas edge, which the old text anchor placed outside the bitmap.

Auto now renders while its input is active. Older native imports are migrated once, with a marker that preserves subsequent native hide edits. Built-in Speed uses project units and Accel Y resolves to lateral G-force. The original local scripts retain their peak/base detection and turn-direction logic. Their background initializes once; foreground variables persist on the project frame grid. Bounded replay/checkpoints rebuild state for backward seeks, repeated frames, source offsets/rates, timeline segments and exports starting mid-session. Histories are isolated by object, script, telemetry revision, channel, units and timing. History replay is limited to one million frames, with bounded checkpoint storage; historical drawing calls are suppressed while variable updates run.

Reference-app inspection confirmed Auto and Persistent Script Variables for these displays. With the supplied telemetry at ten minutes, OpenRaceRender now renders Base Speed: 70 MPH and Right Turn: 1.08 G. The speed style alternates between recent maximum and minimum events as its original script specifies. Synthetic regression tests cover event holding, seeking, rewind, repeat rendering, isolation, delayed input availability, speed units, text clipping and migration. Vendor scripts, session data and comparison renders remain local.

## Session and template usability audit

The [workflow audit](workflow-audit.md) records the session-to-export and blank-template stories, the gaps found through actual editor use, related recovery workflows, and their verification. It supersedes the earlier manual-sheet description of data synchronization above.

## Guide-selected import and designer update

F01, F05 and F07 received structured import and native design controls, verified against disposable projects saved with RaceRender 3.7.3. See [validation and remaining limits](import-designer-validation.md). Synthetic video/audio acceptance verifies timeline mute, stereo routing, repeat placements and nonzero-start export; the 134-test suite includes malformed records, inheritance, migration, typography/shape pixels and gauge modes.

## F25 preview controls

Preview resolution/FPS/scaling, temporary seek quality, audio format simulation/resampling and a dedicated composition window now have independent saved controls. Actual composed frames and audio samples are tested; live full-screen/native operation remains unverified. See [preview settings](preview-settings.md).

## Camera-free video

Telemetry, still/graphics, optional audio and blank scenes can now export through an internal clock without a saved fake source. [Scope and validation](camera-free.md).

## Enhanced script editor

Private background/foreground authoring, canvas/font/aspect/persistence, cancellable renderer tests, diagnostics/current Print messages, timeline Apply/Undo and CLI source editing/checks are now available. [Scope and native limits](script-editor.md).
