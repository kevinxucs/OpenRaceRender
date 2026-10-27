# Heading and G-force estimates

Select a data input, then expand **Data channels & lap timing → Motion estimates**. Heading, longitudinal G and lateral G each offer:

- **Automatic:** prefer the detected or assigned recorded channel; estimate it when that role is absent.
- **Calculate:** use the estimate even when a recorded channel exists.
- **Recorded only:** leave that role unavailable when no recorded channel is assigned/detected.

Choose the heading source in the channel assignments above these controls. **Heading adjustment** rotates the displayed heading in degrees, and **Reverse heading direction** handles sources that turn in the opposite direction. The inspector identifies the recorded source or estimation method. Widget channel lists include the generated columns; explicit widget channel selection still overrides the automatic role.

## Shared calculations

Heading is clockwise from north, normalized to 0–360°. GPS estimates use latitude/longitude motion. Metric XY position fields can also provide heading and speed, with X east and Y north; XY coordinates are assumed to be in meters. Speed-derived longitudinal acceleration is positive forward and negative during braking. Estimated lateral acceleration is positive to the right, using physical course change and speed. Values are in G using 9.80665 m/s² per G.

GPS/XY course is independent of heading display adjustment, so changing the compass orientation does not rotate or reverse physical G estimates. When position is unavailable, recorded heading and speed can estimate lateral G. Recorded channel values keep their logger's sign/unit convention. Map raw device axes explicitly if they are not vehicle-aligned, or choose Calculate for motion estimates.

Generated columns and their provenance are shared by gauges, graphs, native/imported G widgets, Enhanced scripts and image mappings. Missing estimated samples stay missing; the imported G widget no longer bypasses Recorded only with a private fallback. The basic native G widget also honors an explicit lateral channel selection.

Heading interpolation takes the shortest path through north. RaceChrono's native RCZ resampler now does this before merging channel clocks, and promotes its recorded heading to the heading role. Gear and other discrete channels retain their stepped behavior.

Configuration always starts from the parsed source data. Reapplying assignments, unit/time conversion, calculated fields or finish-line settings does not accumulate generated columns or apply a conversion twice. Value/graph bounds are invalidated with the new configuration. Source assignment pickers list recorded columns; per-widget pickers also include generated columns.

## Limits and persistence

Estimates depend on position/course/speed quality and sampling rate. They are finite-difference calculations with available neighbors, not inertial sensor measurements. Endpoints have fewer neighbors. Stationary positions have no meaningful heading; lateral G can be zero at a valid stationary sample. Derivatives break across nonfinite samples and large time gaps (more than the greater of two seconds or five median sample intervals). Smoothing and sparse GPS update controls are separate F18 work.

Native projects retain modes, adjustments and source assignments. Templates discard session-specific data settings. The legacy heading Calculate marker is supported from the mirrored guide; recorded-only heading and explicit G calculation modes are refused during rewritten RRP export because their native controls have not been verified. Unchanged imported native settings can retain their opaque source bytes. Native-app reopening of the new heading marker remains unverified while the UI connection is unavailable.

## Validation

The mirrored InputFileEdit and HowTo-Datalogger descriptions were read. Nine core and two editor tests cover cardinal GPS headings, analytic circular motion, linear acceleration, recorded priority/forced modes, heading wrap, stationary/gapped data, repeat configuration, native/legacy persistence, saved-project loading/undo, template isolation, shared imported/native G rendering and channel inference. All 246 tests pass with local library/graphics access.

The rendered comparison exposed a real inference bug: Lateral and Longitudinal acceleration could match the short lat/lon prefixes and collapse the map. Inference now respects those word boundaries. The trace and position marker also share one coordinate basis when both XY and GPS fields exist.

`scripts/validate-derived-motion.py` compares estimated heading/G widgets with an independent analytic recorded-reference CSV, then checks encoded frames and disabled modes. The established media acceptance passes, including RCZ/CSV overlay equivalence. A three-run read-only import check of the user's sample measured median 0.155s for the prior build and 0.161s for this build; this small local check is not a general rendering benchmark. Private outputs remain ignored under `build/validation/derived-motion`.

Live updated/native UI operation remains unverified: the UI connection reports `cgWindowNotFound`.
