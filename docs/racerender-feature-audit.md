# RaceRender 3 feature research and adaptation

Research date: 2026-10-22. Reference application: installed RaceRender 3.7.3 Ultimate for macOS. This audit covers the public guide and hands-on inspection. Status describes the current source, not intended future behavior.

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
- Create Video exposed entire-project, time-span and lap-range choices; output profiles; workspace/aspect ratio; resolution/frame rate; audio format; bitrates; scaling quality; spherical metadata and optional upload. Lap-range mode was selected to inspect its first/last controls. No RaceRender render or upload was started.
- Video input settings showed trim/rate, audio volume/channel handling, crop/zoom, flip/rotation, brightness, contrast, saturation, hue, sharpness, chroma key, colorization and sphere controls. That dialog was cancelled.

These observations informed behavior. They do not establish that every reference feature has been fully reproduced or that native artwork matches proprietary styles.

## Implementation matrix

“Implemented” means usable in native projects. “Partial” identifies a specific remaining limitation.

| Feature | OpenRaceRender status | Location or remaining work |
| --- | --- | --- |
| Native macOS editor, open/save, drag/drop, relink | Implemented | SwiftUI editor, `.orrp` JSON |
| Preview play/pause, frame stepping, scrubbing, mute, PNG snapshot | Implemented | Shared compositor and AVPlayer |
| Concurrent cameras, PiP and split-screen | Implemented | Multiple video objects and percentage geometry; extra cameras default to PiP |
| Layer order, duplicate, delete, opacity, positioning/resizing | Implemented | Editor and compositor; Shift snapping |
| Source trim, delayed project start and playback rate | Implemented | `InputTiming`, `InputPlacement`; source time mapped once for all consumers |
| Joined sequential media | Implemented | Join after previous source; unjoin; children ordered by the input list |
| Sync offset and manual event alignment | Implemented | Synchronization sheet, frame adjustment and source event time |
| Data event discovery | Implemented subset | Starts/stops, recorded lap starts, first shifts; aircraft event detection absent |
| Per-display inherited timeline segments | Implemented subset | Source, visible, geometry, opacity, text, color and channel; discrete changes |
| Timeline tracks and markers | Implemented subset | Select, scrub, create/remove, reset inheritance; no zoom/shift tool yet |
| Timed titles/captions and camera switching | Implemented | Segments and active start/end span |
| Explicit project length and export marks | Implemented | Project inspector and flag menu |
| Crop/digital zoom, aspect preservation, rotation and flip | Implemented | Normalized crop fractions; source and media-display picture settings |
| Brightness, contrast, saturation | Implemented | Shared CoreImage pipeline |
| Hue, sharpness, colorize, chroma key | Not implemented | Additional input picture operations |
| Audio mixing and source volume | Implemented subset | Audio follows active display source/visibility; preview mute |
| Audio balance, channel swap/mono routing and object-specific gain | Not implemented | Stereo processing and per-object controls |
| Input looping | Not implemented | Repeated composition time ranges |
| Gauges, bars, graphs, G-force, gear, lights, temperatures | Imported styles plus native fallbacks | Saved fonts/colors, procedural scripts and decoded artwork are used where supported |
| Gauge designer | Implemented subset | Range, sweep, orientation, reverse direction, labels, divisions, numbering scale, decimals, redline and background |
| Gauge dual needle, every needle/mark/gradient parameter | Not implemented | Expanded gauge schema and UI |
| Custom images/logos and shapes | Implemented subset | Image/rectangle displays; reusable image styles embed image bytes |
| Object grouping | Not implemented | Parent/group transforms and multi-selection |
| Auxiliary channels and source channel assignments | Implemented | Data inspector and object channel picker |
| Calculated data fields | Implemented subset | Affine `source × multiplier + offset`; other arithmetic operators absent |
| Interpolation and sparse sample handling | Implemented | Duplicate merging, forward fill, numeric interpolation |
| Recorded lap timing, best lap, lap seeking, lap export | Implemented | Timers, lap list, export range conversion includes source timing/rate |
| GPS finish-line lap detection | Implemented estimate | Forward crossing of a width-limited gate, interpolated crossing time, minimum lap duration |
| Recognized-track database and edited lap times | Not implemented | Track database and manual lap overrides |
| Track map and vehicle position | Implemented subset | Full course and current position; no map background editor or ghost comparison |
| Best-lap delta | Implemented subset | Requires compatible distance and recorded/calculated lap boundaries |
| GPS speed fallback and four speed units | Implemented | mph, km/h, m/s, knots |
| Derived heading, G-force and gear estimation | Not implemented | Currently uses available source channels |
| CSV/TSV and RaceChrono | Implemented | Bounded text reader with preamble/header recognition |
| GPX/TCX | Implemented subset | Timestamped track points and common sensors; not every vendor extension |
| NMEA | Implemented subset | RMC/GGA/GLL; GP/GN talkers and valid fixes; no camera-container extraction |
| VBO | Implemented subset | Common whitespace sections; no claim of every device-specific variation |
| FIT | Implemented subset | Activity records, standard GPS/sensors, byte order, compressed time, integrity checks; unknown/developer fields skipped |
| H.264/HEVC camera media and common audio/images | Host decoder support | AVFoundation/AppKit determine actual codec availability |
| `.rrp` input and display import | Partial | Common records, paths/offsets, and traditional gauge range, label, sweep, orientation, interval and needle color |
| Legacy timeline/join/picture/export-setting import | Not implemented | Preserved opaque source bytes; native settings must be configured |
| `.rrt` and `.rro` import | Styles and artwork supported | Embedded BGRA artwork, compressed containers, traditional styling and Enhanced scripts; font metrics and unsupported effects can differ |
| Template/style browsing and input remapping | Implemented | Installed legacy library plus native `.orrt` |
| Reusable layout/single-display export | Implemented native format | `.orrt` with source placeholders; no legacy RRT/RRO writer |
| Enhanced script execution/editor | Bounded interpreter; editor absent | All 56 installed Enhanced styles render in the local-library check; persistent script state and complete language parity remain incomplete |
| H.264 MP4 export, audio, 4K and selected ranges | Implemented | Native export; resolution, FPS, project/time/lap ranges |
| Manual bitrate, output profiles, audio format/scaling quality | Partial | Resolution presets; platform encoder chooses bitrate/audio configuration |
| 360° workspace, fisheye flattening and spherical metadata | Not implemented | Projection and MP4 metadata work remains |
| Stereoscopic/anaglyph color-channel compositing | Not implemented | Specialized composition modes |
| TrackAddict network/WiFi transfer | Not implemented | Local import only |
| Direct upload and portable media packaging | Not implemented | Export video and manage media locally |
| Setup wizard and side-by-side synchronization | Partial | Add inputs/templates and manual event sheet; no dedicated wizard or two-pane sync tool |

## Verification

All 39 tests pass with the local-library check enabled (the default CI run skips that one optional check). The test suite covers parser bounds, legacy codec/patch behavior, native round trips, timeline inheritance, trim/rate/delay mapping, joined-clip cut boundaries, lap export range conversion, GPS finish-line crossings, calculated fields, GPX/TCX/NMEA/VBO import, FIT endian/scaling/compressed timestamps/checksums, and picture transforms.

The media acceptance script generates disposable camera clips, renders native H.264/AAC, and checks actual output pixels and audio. It covers trim/rate/join, exact visibility changes, audio gating, source switching and layers. Generated media and external samples live under ignored `build/validation`.

The full installed legacy library contains 61 templates and 303 style files (255 main styles, 28 image styles and 20 video-position presets). Structural validation reads all 364 files and 1,091 display objects without failures, including compact presets with no thumbnail. The sample RRP imports 18 supported displays and its telemetry. This is deliberately separate from a claim of pixel-identical output.

Additional format references: [TopoGrafix GPX schema](https://www.topografix.com/gpx/1/1/), [Racelogic VBO specification](https://developers.racelogic.co.uk/Portal/Tutorials/tutorialVBOfilestructure.html), [Garmin FIT protocol](https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html), and the [official Garmin profile definitions](https://github.com/garmin/fit-python-sdk/blob/main/garmin_fit_sdk/profile.py). These were used as format references; no SDK dependency was added.

## Original widget styles and artwork

The importer now decodes embedded full-resolution BGRA bitmap containers, including raw DEFLATE records, and retains the original bytes. The renderer reads traditional widget colors, fonts, ranges and geometry. A bounded interpreter runs the drawing assets stored in local Enhanced styles, covering assignments, conditionals, math, telemetry access and drawing primitives. It has no host evaluation, file or network interface, and limits source size, instructions, nesting and canvas allocation.

Local checks render all 56 Enhanced styles in the installed library and compare representative gear/thermometer/gauge output against stored vendor previews. These are coverage and visual checks, not a claim of pixel-identical output across all styles or platforms. Font availability, persistent variables, exact gradients, specialized parameters and unsupported effects remain practical limits. No vendor artwork, scripts or template files are included in this repository. They are read from the user's installation or imported project. The [vendor license](https://racerender.com/RR3/License.txt) does not grant general standalone asset redistribution.

## Next compatibility work

Highest-value remaining work is decoding the legacy timeline and source-adjustment records, followed by persistent Enhanced state, remaining font/gradient differences and image-container variations. Then expand picture/audio controls, grouping, track/ghost tools, 360° handling and file transfer. Each should receive a real reference-app workflow check and an output-level acceptance test before its status is promoted to implemented.
