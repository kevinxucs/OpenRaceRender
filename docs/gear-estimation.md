# Gear estimation and calibration

Select a data input and expand **Data channels & lap timing → Gear estimation & calibration**. **Automatic** uses a detected/assigned recorded gear when it has usable samples, otherwise it estimates from RPM and speed. **Calculate** forces estimation; **Recorded only** disables the fallback while retaining any recorded gear.

Built-in native, Apex and GT gear widgets show **EST** for estimated channels. An unmatched or stopped sample shows **—**, separately from recorded neutral (**N**) or reverse (**R**). Imported drawing scripts retain their own formatting; their inspector still identifies the estimated source.

## Calibration

Automatic calibration learns stable RPM/speed ratio clusters from the whole source file, weighted by elapsed time rather than logger sample count. This keeps calibration consistent across seeking, render chunks and project trim changes. Ratios are ranked highest first and numbered from 1. If the lowest observed gear was actually second, use **Gear number adjustment** of +1. If intermediate gears are missing, provide a complete manual ratio list instead of relying on a single offset.

**Use detected ratios as manual calibration** freezes the learned values for this input. Turn off **Learn ratios automatically** to edit a list, add/remove gears and use **Use playhead** to capture a ratio from a frame where the gear is known. Capture uses this input's synchronized source time, even when another logger is first in the project. Ratios must be positive and descending, from first to last gear.

The ratio is **RPM ÷ speed in m/s**; for example, 2000 RPM at 20 m/s gives 100. It is not the gearbox's published mechanical ratio. A published transmission ratio alone does not include final drive and wheel circumference. Choose the desired speed and RPM sources in the input assignments above the controls.

Minimum speed and RPM exclude unreliable low-speed samples. Relative ratio tolerance controls matching. Maximum detected gears and minimum ratio support affect automatic learning; manual calibration supports up to 12 ratios. Reset removes gear-specific mode, calibration and number adjustment together. Changes use the existing input undo history.

## Behavior and limits

Gear samples remain discrete after number adjustment and calculated-field conversion; they do not interpolate through fractional gears. Small matching hysteresis reduces boundary flicker. Ratios outside tolerance, invalid speed/RPM, stopped samples and large source gaps remain unknown. The estimator cannot infer neutral or reverse from speed/RPM alone.

Automatic numbering cannot identify unobserved gears. Clutch/wheel slip, unlocked torque converters, CVTs and timing lag between RPM and speed may create poor calibration or incorrect matches. The tool rejects ordinary transient ratios but does not reliably detect all slip. Use a responsive vehicle/OBD speed source when available and check several gear changes in the composition.

Native projects retain modes, manual ratios, thresholds and number adjustment. Templates discard session-specific calibration. The legacy Gear Calculate marker and whole-number adjustment are supported; Recorded only and custom calibration options require `.orrp` because their native settings are unverified. Native-app reopening of the new Calculate marker remains pending while the UI connection is unavailable.

## Validation

The mirrored HowTo-Datalogger gear-estimation section and InputFileEdit gear controls were read. Seven core and two editor tests cover noisy learned clusters, manual ratios, slip/stopped/missing samples, units, recorded priority, forced/disabled modes, discrete adjustment, validation, persistence, synchronized playhead calibration, undo/template isolation and visible estimated/unknown rendering in three built-in styles. All 255 tests pass with local library and graphics access.

`scripts/validate-gear-estimation.py` compares learned output against a separate known-ratio manual project. It checks unknown stationary/slip samples, three gear styles and encoded output from a nonzero-start chunk without changing calibration. Artifacts remain ignored under `build/validation/gear-estimation`.

RaceRender was checked again after the usage-limit interruption; its window still reports `cgWindowNotFound`. Live native/updated-control validation remains unverified. No native algorithm or pixel parity is claimed for estimates.
