# RaceRender file export (F02)

OpenRaceRender independently writes RRP3 projects, RRT2 templates and RRO2 display styles. The writer uses no vendor executable, framework, source or asset library at runtime. Native `.orrp`/`.orrt` remains the format for the complete OpenRaceRender model.

Use **Export RaceRender project…** for a separate `.rrp` copy. Adding/removing/reordering displays or inputs no longer requires original project bytes. **Save layout as template…** and **Save reusable style** offer a file-format picker for `.rrt` and `.rro`. Export checks compatibility before opening the destination panel. Ordinary Save continues to use the native format.

```sh
./scripts/run.sh convert session.orrp --out copy.rrp
./scripts/run.sh convert layout.orrt --out layout.rrt
./scripts/run.sh convert single-display.orrt --out display.rro
```

## Implemented records

- Project notes, units, explicit/input-bound duration, 16:9/4:3 workspace, output marks and source remapping.
- Video/audio/data inputs; trim, delay, speed, looping, picture controls/crop/rotation/flip, audio gain/balance/routing, recognized data assignments and up to four single-operation calculations.
- Native video, audio, embedded images, text, rectangle/rounded/ellipse shapes and representable circular gauges, including an authored gauge background image. Imported specialized display payloads and unchanged opaque source settings are retained; supported direct payload edits remain exportable.
- Display order, names, parent references, geometry, activation, transparency, input selection and recognized picture/audio settings.
- RRP timeline records for source/position/size/visibility/aspect/flip/transparency/style, audio gain/balance, specialized settings and artwork changes. Display end bounds become visibility events.
- Native first-clip joins become RaceRender virtual streams, preserving the source role, first-clip trim/rate/delay and the joined clock. Existing virtual streams are retained.
- Template input roles (maximum eight), names, BGR preview, embedded BGRA artwork, symmetric record encoding and the eight-byte metadata/payload integrity records. Styles contain one display. No project paths or session settings are needed to load a reusable layout.

## Explicit limits

The writer refuses settings for which a verified equivalent does not exist. This includes native Apex/GT HUD instruments, native-only widget types without legacy payloads, triangle/diamond/line shapes, rotated shape gradients, adjustable text outline widths, arbitrary gauge smoothing/mark shapes/independent alert schemes, multiple native background layers on one display, custom native GPS finish-line changes, combined calculated-field operations, more than four calculations, unsupported timeline flags/record variants and RCZ project inputs. Use CSV for RaceRender data inputs. Original unchanged data records can retain their saved finish-line/settings bytes.

Explicit sequence time fillers require native `.orrp`; their RaceRender source-record encoding has not been verified. Reordered media sequences without fillers remain exportable.

Heading Calculate uses the documented source-field marker. Explicit recorded-only heading and G calculation mode overrides require native `.orrp`; their native source controls remain unverified.

RRT/RRO cannot store OpenRaceRender timeline events or display time bounds; export RRP or native ORRT instead. They are refused rather than silently flattened. RRO styles cannot carry a parent group. Other canvas ratios are refused until their workspace encodings are verified. RaceRender cannot represent an end flag at zero. RaceRender's application-wide video export preferences and OpenRaceRender's remembered destination are not RRP records.

Compatibility does not establish identical pixels. Native fonts, glyph handling, gradients and supported renderers still have the limits described in the feature audit. RR3's macOS preview garbled a non-ASCII arrow while retaining its UTF-16 payload unchanged; the acceptance fixtures use ASCII captions for the visual check.

## Validation

`LegacyWriterTests` covers original-byte-free authoring, source remapping, picture/audio/data settings, marks, timeline inheritance, native/virtual joins, Unicode object names with embedded artwork, image styles, gauge mode/precision/numbering/split fields, integrity derivation, opaque-byte preservation and refusing export before touching a destination.

Run `python3 scripts/validate-legacy-writer.py` after building the app. It creates original synthetic media/data and independently authored projects under ignored `build/validation/legacy-writer/acceptance`, exports all three formats, reopens them and renders the rebuilt RRP. The text/geometry events and timed audio mute pass still/video verification. No private sessions or vendor fixtures are committed.

RaceRender 3.7.3 Ultimate was operated directly for the separate compatibility check:

1. Opened a newly authored RRP, including added captions/shapes and output flags.
2. Opened the generated RRT input-mapping dialog with Camera and Logger assigned correctly.
3. Loaded the independently authored gauge RRO through Gauge Designer, with the expected gauge type, range and geometry.
4. Opened the generated timeline RRP and sought from zero to 1.25 seconds; the caption and ellipse position changed as authored, with neutral camera video visible.
5. Saved disposable native references to verify gauge mode, precision, numbering, interval mode, split point, indicator gradients, source color-tint defaults and custom rotation fields.

These checks found and corrected defaults that self-roundtrips missed: zeroed input settings enable black colorize; gauge modes belong to payload flags, not common byte 283; mark intervals need their interval-mode flag; appended unused gradients require disabled alpha; source rotation is stored directly as a float, without a flag in the tint color.

F06 adds authored/imported type-35 graph writing for verified axes, modes, ranges, palette, widths, gradients, numbers and labels. Lap selection and opposite-side numbers remain native-only and are refused explicitly; see [graphs](graphs.md).

F08 adds E Image control payloads, mapped data roles and length-prefixed artwork. Pulse intervals must be representable in tenths of a second; Visibility uses opacity endpoints for legacy export. Native-saved image import is verified, but corrected authored native reopening remains unverified because the UI window is inaccessible; see [image validation](image-controls.md).

F09 allows a cleared base background. Artwork-clear timeline events require native format and are explicitly refused for RRP output; see [background editor](background-editor.md).

F10 refuses renderer-type changes inside a legacy timeline event. RRT seeds are normalized if an encrypted input identifier would collide with the raw input-table delimiter; valid seeds remain unchanged. See [timeline validation](timeline-editing.md).
