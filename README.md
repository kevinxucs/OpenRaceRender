# OpenRaceRender

[![CI](https://github.com/kevinxucs/OpenRaceRender/actions/workflows/ci.yml/badge.svg)](https://github.com/kevinxucs/OpenRaceRender/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An MIT-licensed, native macOS telemetry video editor, with independent readers for RaceRender 3 projects, layouts, and styles. Built with SwiftUI, AVFoundation, CoreGraphics, and CoreImage. No vendor executable, SDK, artwork, or template library is bundled.

This is an evolving implementation. It does **not** have full RaceRender feature or rendering parity. The [feature audit](docs/racerender-feature-audit.md) distinguishes working features from remaining gaps, including limitations of legacy imports.

## Build and run

Requires macOS 14 or newer and an installed Xcode toolchain with Swift 5.9 or newer. Builds natively for the host architecture, including Apple silicon.

```sh
git clone https://github.com/kevinxucs/OpenRaceRender.git
cd OpenRaceRender
./scripts/build.sh
./scripts/run.sh
```

The build produces `build/OpenRaceRender.app`, signed locally with an ad hoc signature. You can launch that bundle directly. The application has no third-party package dependencies and does not require a RaceRender installation to run.

```sh
./scripts/test.sh
```

Optional media acceptance checks require `ffmpeg` and `ffprobe` for test media generation and inspection; the application itself uses native macOS media APIs:

```sh
python3 scripts/validate-media.py
```

## Editing a session

1. Open an `.rrp` or `.orrp`, or add video and telemetry files. Additional cameras start as picture-in-picture displays.
2. Browse templates and styles. An installed `~/Documents/RaceRender 3` library can be imported; native `.orrt` layouts also work. Map template inputs to your sources before applying.
3. Select an input to relink it, set its synchronization offset, trim it, change playback rate, delay its start, or join it after the previous media input. Set picture crop fractions, rotation, mirroring, brightness, contrast, and color here.
4. Select a display to position and resize it, choose its channel and range, or customize a gauge. Use **Base settings** for project-wide defaults. Seek to a time and choose **Add at playhead** to create a segment; its field changes are inherited by later segments until overridden. This supports camera switches and timed titles.
5. For telemetry, use **Synchronize to a data event** to align a movement, lap, or gear event with the video playhead. Under **Data channels & lap timing**, assign channels, create `source × multiplier + offset` fields, or set a GPS finish line at a moving sample. GPS-derived lap times are estimates.
6. The **Objects** timeline shows segment markers. The **Laps** tab seeks to lap starts. Export the entire project, an explicit range, marked start/end times, or selected laps as H.264 MP4 with audio. Save PNG snapshots with the camera button.

Save edits as `.orrp`. Save a reusable layout or a single selected display as `.orrt`. Image displays are embedded when saving reusable layouts. Compatible `.rrp` copy export is deliberately limited to supported edits and preserves the original opaque data.

## Formats

| Format | Support |
| --- | --- |
| `.orrp` | Native JSON project, read/write, including segments, source timing, picture and data settings |
| `.orrt` | Native reusable layout or display style, read/write with input remapping |
| `.rrp` / RRP3 | Partial import: sources, offsets, original display geometry and recognized types; conservative copy export |
| `.rrt` / rrt1, rrt2 | Layout import, thumbnails, saved widget styling and supported embedded artwork |
| `.rro` / rro1, rro2, rro3 | Style import, original drawing scripts/artwork, and compressed previews |
| CSV / TSV / text | Time column required; RaceChrono preamble, sparse values, quoted cells, interpolation and channel aliases |
| GPX / TCX | Timestamped track points, GPS and common sensor extensions |
| NMEA | RMC, GGA, GLL, valid fixes, checksum checks when present, merged samples, midnight rollover |
| VBO | Common `[column names]` and `[data]` layouts, UTC time, velocity, signed minute coordinates |
| FIT | Activity record messages, standard GPS/sensor fields, compressed timestamps, both byte orders, CRC validation; unknown/developer fields skipped |
| Video/audio/images | Formats supported by the host's AVFoundation and AppKit decoders; H.264/HEVC MP4/MOV, common audio and images |

Speed units include mph, km/h, m/s, and knots. GPS speed is estimated when absent. Recorded lap numbers, best lap, lap timers, and distance-based delta are supported. Custom finish lines can replace recorded lap boundaries.

## Command line

```sh
./scripts/run.sh inspect session.rrp
./scripts/run.sh inspect-data telemetry.fit
./scripts/run.sh validate-library "$HOME/Documents/RaceRender 3/Templates"
./scripts/run.sh convert session.rrp --out session.orrp
./scripts/run.sh snapshot session.orrp --time 600 --out frame.png --width 1280
./scripts/run.sh export session.orrp --start 600 --duration 5 --out clip.mp4 --width 1920 --fps 30
./scripts/run.sh --open session.rrp
```

## Compatibility limits

Legacy timeline segments, joins, export profiles, picture/audio adjustments, and every specialized object parameter are not yet decoded. Check the import report and configure those settings explicitly. Imported widgets use saved bitmap aspect ratios, colors, fonts, geometry, original drawing scripts, and full-resolution embedded artwork where supported. Live RaceRender snapshots have been used to correct gauge direction and needles, bars, thermometer labels, RGB blending, maps and lap displays. All 56 Enhanced styles in the locally tested library render through the bounded interpreter. This establishes coverage, not universal pixel parity: font availability/metrics, persistent script state, gradients and other unsupported effects can still differ.

Vendor artwork and scripts are loaded from your local files and are not bundled or relicensed under MIT. The original product's [license](https://racerender.com/RR3/License.txt) does not provide a general standalone-asset redistribution grant.

360° projection/metadata, stereoscopic compositing, TrackAddict network transfer, camera GPS extraction, grouping, full script editing, and several advanced audio/picture controls remain unimplemented. See the audit for details. Parsing all installed templates is a structural compatibility check, not a guarantee of identical rendering.

## Contributing and support

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and validation. Report reproducible bugs or propose improvements through [GitHub issues](https://github.com/kevinxucs/OpenRaceRender/issues). Check the [feature audit](docs/racerender-feature-audit.md) for existing limitations and the [changelog](CHANGELOG.md) for development changes.

Please follow the [code of conduct](CODE_OF_CONDUCT.md). For vulnerabilities, follow the [security policy](SECURITY.md). Public reports and contributions should use synthetic examples and omit private media, telemetry, local paths, and proprietary vendor assets.

## Source layout

`Sources/RaceCore` contains file readers, telemetry, timeline/source mapping, rendering, and export. `Sources/OpenRaceRender` contains the desktop editor and CLI. Tests use synthetic interchange records rather than redistributing proprietary templates or private sessions.

## License and attribution

OpenRaceRender's source is available under the [MIT license](LICENSE). Imported third-party files and assets retain their owners' licenses; importing them does not grant redistribution rights.

RaceRender is a product of HP Tuners/RaceRender LLC. OpenRaceRender is an independent project with no affiliation or endorsement.
