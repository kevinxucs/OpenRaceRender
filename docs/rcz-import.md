# RaceChrono RCZ import

Validated on 2026-10-24. OpenRaceRender reads recorded RaceChrono `.rcz` sessions directly; exporting a CSV first is optional.

## Use a session

Choose **Add input**, drop an RCZ onto the editor, or use Finder's **Open With → OpenRaceRender**. It becomes a data input. Add your camera recording, apply a layout and use **Sync** to align a recorded lap boundary or another event with its video frame. Channels are available to widgets, calculated fields and the telemetry inspector. Save as `.orrp` to retain the RCZ reference, synchronization and other project settings. The recording remains an external file; **Relink file…** can replace a moved recording.

For diagnostics:

```sh
./scripts/run.sh inspect-data session.rcz --time 60
```

This reports the session title, relative duration, channels, recorded laps, warnings and values at the requested time. `firstSampleUnixTime` identifies sample zero for comparisons with timestamped exports.

## Supported data

- Single-session ZIP containers, including a wrapping session folder and resumed fragments.
- Independent GPS, CAN, OBD and sensor stream clocks. Their timestamp union retains fast channels without reducing everything to GPS frequency.
- Integer and floating-point channels, packed GPS coordinates, distance, common vehicle/sensor channels and sensor positions such as individual tyres. Speed is stored in m/s, acceleration in G, pressure in kPa and temperature in °C; the UI applies its selected speed unit.
- Gyroscope calibration from fragment metadata. Phone sensor axes retain their recorded orientation; arbitrary phone X/Y axes are not assigned vehicle longitudinal/lateral G.
- Continuous interpolation, held discrete values, missing-value sentinels and gaps between resumed fragments. Resumed distance counters are made cumulative using the visible fragment bounds.
- Exact recorded lap boundaries and numbers. Incomplete, clipped and invalid laps are excluded from best-lap selection.
- Unknown channel identifiers retained as raw numeric values with an import warning. Unsupported numeric encodings are reported and skipped.

Metadata bounds clip buffered samples in partial exports. Sample zero uses the first included sample timestamp, rather than the session creation time. RCZ and CSV partial exports can contain different buffered ranges; compare absolute timestamps before judging synchronization.

The reader validates ZIP member sizes and checksums without extracting files. It accepts stored/DEFLATE members, with limits of 4,096 members, 64 MiB per expanded member and 256 MiB total expanded data. Telemetry is bounded to two million timestamps, 256 channels and 32 million table cells. Encrypted, ZIP64 and multi-volume archives are rejected.

## Scope

This imports recorded telemetry. It does not write RCZ files, combine a multi-session backup, import vehicle/track profiles as recordings, or reproduce RaceChrono's sensor fusion and derived channels absent from the archive. Use a RaceChrono CSV export if you need those computed values or encounter an unsupported archive variant. RCZ is an internal format that may change; RaceChrono's developer documents this compatibility caveat alongside the timestamp representation in the [official forum](https://racechrono.com/forum/d/2313-2313).

The implementation is independent Swift code with no third-party parser dependency. Research used the official [resume-folder description](https://racechrono.com/forum/d/2232-2232), [channel identifiers](https://racechrono.com/support/equations/identifiers), a community [format investigation](https://github.com/timliudev/track-log-studio/blob/main/docs/specs/RCZ-FORMAT-SPEC.md), and observed recordings. Binary details were checked against matching RaceChrono CSV exports.

## Verification

| Recording | Duration | Native timestamps | Channels | Compared values |
| --- | ---: | ---: | ---: | ---: |
| Private road test | 594.652 s | 77,032 | 37 | 660 |
| Public short recording | 20.000 s | 1,594 | 11 | 133 |
| Public lap export | 113.405 s | 23,000 | 77 | 1,460 |

All 2,253 sampled values pass `scripts/validate-rcz.py` against matching CSV v3 exports. Comparisons use absolute timestamps and explicit tolerances: 2×10⁻⁷ degrees for coordinates, 0.05 RPM, 0.01 m for distance and 0.001 for other compared channels. This samples matching recorded channels; it does not claim exhaustive equivalence with RaceChrono's computed channels. Public recordings and their CSV exports came from [RaceChrono-to-CSV's sample collection](https://github.com/jLynx/RaceChrono-to-CSV). Recordings and generated reports remain outside the public source tree.

The native UI imported the private recording with all 77,032 samples and 37 channels, saved a disposable `.orrp`, and reloaded its RCZ telemetry after restarting the updated app. Editor tests additionally verify startup file-open delivery, save/reopen and atomic relink with undo. Parser tests cover independent clocks, units, calibration, exact laps, clipped/resumed distance, missing values, malformed streams, DEFLATE and ZIP integrity/bounds. The complete suite passes 98 tests with the local library and macOS graphics available.

`scripts/validate-media.py` generates equivalent synthetic RCZ/CSV telemetry, then renders both through the same speed/G-force layout. Snapshot PNGs are byte-identical, and decoded H.264 overlay frames agree within a mean RGB difference of 0.5/255. Existing media acceptance checks also pass. No private recordings or third-party parser code are included in the repository.

To repeat a local data comparison:

```sh
python3 scripts/validate-rcz.py session.rcz session_v3.csv \
  --out build/validation/rcz/comparison.json
```
