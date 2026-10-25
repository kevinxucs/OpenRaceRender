# Apex Telemetry and Apex Road

An original native vector design inspired by the hierarchy of the user's [GT7 HUD reference](https://www.gran-turismo.com/images/c/i1NV9IVoZx3lNEE.jpg): large speed/gear at the bottom, an RPM ribbon, restrained cyan accents, red brake/redline cues, translucent charcoal panels and a clear central driving view. It uses macOS system fonts and original drawing code; no game artwork, RaceRender scripts or vendor assets are distributed.

## Layout and channels

**Apex GT / Apex GT Road** are analog variants: two 270° circular dials with white graduations, live needles and a red tachometer limit; a zero-padded TRIP counter below the speedometer; tall graphical brake/throttle travel bars around the central gear readout; and an original top-down car drawing with four temperature-colored wheels. Pressure and °C readings sit next to the corresponding wheel. Trip distance comes from the recording's distance channel, not the vehicle's unknown lifetime mileage. Gauge limits, redline, units and source bindings remain editable. Digital Apex files without the optional `presentation: gt` setting retain their existing rendering.

| Area | Instruments |
| --- | --- |
| Bottom | Speed in project units, gear, RPM ribbon, shift lights, accelerator and brake percentages, steering angle/wheel, yaw rate, combined G and longitudinal/lateral components |
| Lower right | FL/FR/RL/RR tyre pressures and temperatures, with a vehicle outline for orientation |
| Upper right | Aspect-correct GPS route and current position, completed peak speed, completed minimum speed, completed turn peak G |
| Right side | Oil/coolant/intake/ambient temperatures, GPS accuracy, satellites, logger battery |
| Upper left | Lap, lap time, best lap/time, delta, session elapsed time, distance, altitude and heading |

**Apex Road** keeps the same 30 editable objects but hides the five lap timing objects and arranges session metrics in their place. Apply Apex Telemetry for track recordings. Hidden lap objects remain available in Road mode. Oil and other missing measurements show a dash rather than zero; the road-test RCZ has neither oil temperature nor recorded lap boundaries.

Tyres default to psi and °C. Pressure headers in kPa, bar or psi are converted to the selected pressure unit. The tyre widget reads each corner independently, so one unavailable corner does not zero the others. Numeric fields expose label, units, precision and a multiplier in **Apex instrument**. The same source/channel, geometry, visibility, color, alignment, save and undo controls work as other native widgets. Speed follows the project speed unit. Distance defaults to miles, independently editable through its multiplier/unit.

RPM defaults to an 8,000 rpm maximum and 6,800 rpm redline; these are design defaults, configurable in the inspector. The G plot defaults to ±1.5 G. Steering is shown in degrees; yaw in degrees/second. Tyre pressure/temperature channels use the `Tyre pressure FL` / `Tyre temperature FL` naming pattern through RR, independent of RaceChrono device suffixes.

## Peaks and performance

The original native extrema index runs over source samples once and caches completed events. Speed maxima require a subsequent decrease greater than 0.45 m/s; minima require a subsequent increase of that size. Turn G uses lateral magnitude, a 0.08 G turn reset and a 0.06 G decrease to complete a peak above 0.12 G. These small thresholds reject noise; values are held until the next qualifying completed event. No future event is shown. These rules are an independent implementation, not a claim of exact equivalence to every RaceRender peak script.

The immutable event index supports binary-search lookup for seeks and chunk exports. Route geometry is cached by telemetry identity/revision and keeps its physical aspect ratio. No frame-grid script replay or vendor artwork decoding is needed for this design.

## Create and reuse

Choose the built-in template in **Templates**, or choose **Original: Apex Telemetry** as the widget palette source to place individual instruments. Existing video/audio displays are retained when applying the overlay. Reusable `.orrt` files contain empty data source roles, with no recording paths, GPS samples, session timing or export marks.

```sh
OpenRaceRender make-template apex --out Apex.orrt
OpenRaceRender make-template apex-road --out Apex-Road.orrt
OpenRaceRender make-template apex-gt --out Apex-GT.orrt
OpenRaceRender make-template apex-gt-road --out Apex-GT-Road.orrt
```

The private road-test project uses the native RCZ input and copies the existing project's source synchronization and render bounds. The RCZ begins 0.080 seconds earlier than the CSV's first timestamp, so its source offset is the existing CSV offset plus 0.080 seconds. This does not modify the recording or original project. Video and RCZ files remain external to the reusable template.

## Validation

Six regression tests cover clean template generation/round trips, data source remapping, native instrument settings, road-mode visibility, missing values, tyre unit conversions, no future extrema, repeated forward/backward seeks and rendered pixel consistency. The full local suite has 121 tests. Private visual checks use multiple 1080p snapshots over the recording and a short H.264/AAC export. Recordings and rendered road-test images remain outside the public repository under ignored build validation files.
