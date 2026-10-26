# RRP import and gauge/text/shape designer

Implemented from the local RaceRender guide review as F01, F05 and F07. The original gap list remains in [guide-gap-review.md](guide-gap-review.md); [feature-progress.md](feature-progress.md) tracks the subsequent work.

## Import behavior

The structured RRP3 reader follows the source/object/timeline tables instead of scanning inside payloads. Disposable projects saved in RaceRender 3.7.3 were used to identify records by changing source configuration, project length/notes, joined media, data assignments/calculations and timed display properties. User recordings and original projects were not overwritten.

Supported settings include:

- Project notes, preferred speed units, explicit duration or duration bound to an input, and output In/Out marks.
- Source offsets, end trim, project delay, playback rate and looping; virtual joined roots and ordered children.
- Source crop, rotation, mirroring, brightness, contrast, saturation, hue and sharpness.
- Source gain, balance and stereo/swap/left-to-both/right-to-both/mono routing; display gain/balance and timed audio changes.
- Time field/units, supported GPS/sensor assignments, speed conversion, heading adjustment/reversal, gear-number adjustment, interpolation, ignored initial lap triggers and supported constant calculations/unit conversions.
- Inherited display timeline changes for sources, geometry, visibility, aspect, mirroring, opacity, audio, specialized payload settings and artwork.
- Ordinary text typography and shape styling, in addition to the existing specialized gauge/script styles.

Native `.orrp` saves retain the decoded settings. Older native imports recover absent settings from retained RRP bytes once; authored nondefault settings are preserved. Compatible RRP copy export retains unchanged imported records, but still rejects edits it cannot safely represent. Full legacy file writing is tracked separately as F02.

Import remains a supported subset. Group transforms (F03), color-channel masks (F35), chroma/colorize (F24), spherical effects (F34), multi-session selection (F31), some later data fields/conversions (F17), clipping and some timeline mode flags still need their own implementations. Unknown flag combinations are reported where detected; retained opaque bytes are not evidence that an effect renders. GPS finish-line width is an estimate from stored tolerances, not a reproduction of RaceRender's proprietary lap-detection algorithm. Application-wide preview/export profiles were not present in the tested RRP records and cannot be recovered from that file.

## Design controls

Choose a speedometer, tachometer or generic Gauge, then open **Expanded gauge design**. It provides needle/dual-needle/filled modes, automatic limits, averaging, nonlinear midpoint scale, face/trim, needle geometry, independent major/minor marks and pins, independent value/label/number typography and caption positions, and separate needle/marking/face threshold colors with optional gradients. Sizes are relative to the gauge radius. Arbitrary-channel gauges require a channel selection.

Simple imported gauges continue using their established legacy renderer until their expanded design is edited. Imported dual/filled/nonlinear gauges use the expanded renderer. Font metrics, antialiasing, automatic caption placement, gradients and proprietary needle shapes can differ from RaceRender; these controls do not establish universal pixel parity. Both still and video export use the same vector renderer.

Text widgets expose font, size, bold/italic/underline/strike, alignment, reduce-to-fit and outline. Shape widgets expose rectangle, rounded/rounder rectangle, ellipse, triangle, diamond and line, with fill/gradient and outline. Font and line sizes scale from the stored reference canvas height. These settings support inherited timeline segments, native project/style saving and undo. Template saves embed artwork used by both base settings and segments; relative paths resolve after moving a project folder.

## Validation

- 134 tests pass with graphics services and the optional local library enabled: 116 core tests and 18 editor tests. CI omits the optional installation-dependent checks.
- Structured synthetic RRP fixtures cover joins/source clocks, segment inheritance, text replacement, crop/rotation/flip, audio matrices, data time units/conversions, malformed tables, native roundtrip and unchanged legacy copy bytes.
- Drawing checks distinguish seven shapes, gradient/outline and typography changes. Gauge checks cover nonlinear scale endpoints, three modes, geometry/threshold edits, smoothing, automatic bounds and repeatable seeking.
- Live OpenRaceRender validation opened the synthetic project, changed gauge mode, exercised undo, enabled text outline, added a diamond with gradient/outline and saved. The saved JSON retained all edits.
- `python3 scripts/validate-designer.py` generates its own video, stereo tones, CSV, RRP and native designs. Short exports verify left-channel duplication, exact timeline mute, swapped tone frequencies, repeating video across boundaries and a nonzero export start. It saves a still and video showcase under ignored `build/validation/designer`.
- `python3 scripts/validate-media.py` passes the existing trim/rate/join, layered cameras, visibility-gated audio, selected ranges, fractional FPS, H.264/AAC/color tags, imported marks/hue/sharpness, missing-media preflight and RCZ/CSV render comparisons.

These are targeted correctness checks, not a new full-session speed/quality comparison. Local library assets and private reference-app probes stay outside source control.
