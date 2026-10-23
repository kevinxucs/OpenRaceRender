# Contributing

OpenRaceRender welcomes bug fixes, compatibility improvements, documentation, and tests. Check the [feature audit](docs/racerender-feature-audit.md) before starting a larger change, and open an [issue](https://github.com/kevinxucs/OpenRaceRender/issues) to discuss its intended behavior.

## Development setup

Use macOS 14 or newer with an Xcode toolchain that provides Swift 5.9 or newer.

```sh
git clone https://github.com/kevinxucs/OpenRaceRender.git
cd OpenRaceRender
./scripts/test.sh
./scripts/build.sh
./scripts/run.sh
```

The package has no external dependencies. `RaceCore` contains file readers, telemetry, timeline mapping, rendering, and export. `OpenRaceRender` contains the editor and CLI. Keep core behavior usable without a GUI.

## Changes and validation

- Keep changes focused and explain the resulting behavior in your pull request.
- Add regression tests for parser, timing, rendering, or compatibility bugs. Use small synthetic fixtures whenever possible.
- Run `./scripts/test.sh` and `./scripts/build.sh` before submitting. For compositor changes, also run `python3 scripts/validate-media.py`; it requires `ffmpeg` and `ffprobe` on your PATH.
- Update the README, feature audit, and changelog when supported behavior changes. Distinguish structural file parsing from faithful rendering.
- Match nearby Swift code: two-space indentation and clear names. Keep Python tooling at four-space indentation.

The media check creates disposable inputs and outputs under ignored `build/validation/features`. It does not require personal footage or an installed RaceRender library. SwiftPM needs a writable module cache; the scripts configure one inside the checkout. A restrictive development sandbox may also need to allow macOS media services for export tests.

An optional fidelity check reads your installed style library without copying it into the repository:

```sh
OPENRACERENDER_LIBRARY="$HOME/Documents/RaceRender 3" ./scripts/test.sh --filter WidgetTests
```

This checks execution of local Enhanced styles. Compare output against their stored previews or the reference app before claiming visual parity. The default CI run skips this optional check because vendor files are not distributed with the project.

## Compatibility contributions

Describe the format/version and the workflow that reproduces a problem. Bound-check lengths, offsets, and counts before reading binary data. Cover malformed and truncated inputs as well as valid ones. Preserve unknown legacy bytes where possible and report unsupported behavior clearly.

Please do not commit proprietary RaceRender templates, artwork, binaries, private project files, or recorded telemetry/video. Share only material you have permission to distribute. GPS logs can reveal precise locations, and project files can contain local paths and embedded assets; use synthetic examples for public reports. Test fixtures covered by the default ignore rules can be added with `git add -f Tests/Fixtures/<file>` after reviewing their contents and license.

## Pull requests

Target `main` and use the pull request template. State what changed, why, and how it was verified. A screenshot or small synthetic render is useful for visible changes. Include relevant issue links and describe compatibility limits.

Contributions are accepted under the project's [MIT license](LICENSE). By submitting a contribution, you represent that you have the right to contribute it under that license.
