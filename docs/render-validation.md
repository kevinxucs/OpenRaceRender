# Render validation

Validation uses real exports from RaceRender 3.7.3 Ultimate for macOS and OpenRaceRender on the same Apple M1 Pro Mac (10 CPU cores, 32 GB RAM). Media is copied to local storage before testing. Private media, telemetry, projects, screenshots and proprietary styles stay in the ignored `build/validation` directory.

## Quality and performance protocol

Export representative five-second ranges at 3840×2160, 60000/1001 FPS, H.264, 98,304 kbps video and 240 kbps stereo AAC at 48 kHz. RaceRender uses Maximum picture scaling quality and Maximum CPU use. Run exports sequentially, with no other render or build running during the timed samples. Report project loading separately from rendering.

Inspect decoded frames at the beginning, middle and end of each range. Compare both the entire picture and separate video/HUD regions. Full-frame scores include layout, font rasterization, telemetry history and compression, so they cannot establish encoder quality by themselves.

The final matched late-session sample took approximately **19.7 seconds in RaceRender and 8.6 seconds in OpenRaceRender**, about **2.3× faster** on this Mac. RaceRender wrote 301 frames and OpenRaceRender wrote 300 for the nominal five-second interval; that endpoint difference is under 0.4% and does not explain the speed difference. Both files use H.264 High Profile near the same requested bitrate. These are measured chunk results, not a full-session runtime projection or a claim about every machine/project.

The reference MP4s in this test omit color-matrix tags. Neutral picture-control snapshots and comparison against the original camera establish that these exports need Rec.709 decoding; allowing FFmpeg's untagged-video default would introduce a false color difference. Use `--reference-matrix bt709` for these particular files, rather than applying that override to every reference file.

```sh
./scripts/run.sh export session.rrp --start 600 --duration 5 \
  --width 3840 --height 2160 --fps 59.94005994005994 \
  --video-bitrate 98304 --audio-bitrate 240 --progress --out open-4k.mp4

python3 scripts/compare-renders.py reference-4k.mp4 open-4k.mp4 \
  --out build/comparison --reference-matrix bt709 \
  --roi video:240:230:710:270
```

The comparison script creates matched snapshots, side-by-side images, amplified difference images, JSON metrics, and a local HTML comparison slider. It requires FFmpeg/FFprobe and Python's standard library.

## Full-session behavior

Also export the entire session from a freshly opened project. A 856×480, 5 FPS diagnostic keeps a long session manageable while exercising all source transitions and the accumulated widget history. Both applications must use the same dimensions, frame rate and bitrate. This diagnostic supplements the 4K quality/performance samples; it does not replace them.

```sh
./scripts/run.sh export session.rrp --start 0 --duration 1468.70056 \
  --width 856 --height 480 --fps 5 --video-bitrate 4000 \
  --audio-bitrate 240 --progress --out open-full.mp4

python3 scripts/compare-renders.py reference-full.mp4 open-full.mp4 \
  --out build/full-comparison --width 856 --reference-matrix bt709 \
  --times 0,60,185,300,600,900,1200,1460,1467
```

Short RaceRender exports in the observed process retained earlier Enhanced peak/base and turn state. Starting the entire session from zero produced the expected completed peaks instead. OpenRaceRender replays that state from the display's start so seeking and partial exports remain deterministic; it does not reproduce stale state from a previous render.

## Corrections covered by this validation

- Import the camera's saved brightness, contrast and saturation, including recovery for older native imports that omitted them.
- Use multiplicative brightness and HSV saturation in encoded RGB, checked against native neutral/individual/combined adjustment snapshots.
- Preserve the legacy Rec.709-to-BT.601 decoder interpretation for imported video appearance. New native media keeps normal color interpretation.
- Use recorded longitudinal acceleration when supplied, with speed-derived acceleration as a fallback.
- Correct traditional map stroke/zoom, text placement and rounded-bar surface/label position.
- Match integer pixel allocation at small output sizes, import the saved video aspect flag, and hide imported data displays when their source ends.
- Write explicit H.264 High Profile video and AAC bitrate settings with Rec.709 metadata.
- Render the base camera directly into the GPU destination surface, cache map geometry, and match widget bitmap formats to the destination to reduce copying and channel conversion.

Font availability, small rasterization/gradient differences, unsupported imported settings, and temporal sampling can still affect exact pixel parity. Structural template coverage and successful export do not establish universal rendering equivalence.
