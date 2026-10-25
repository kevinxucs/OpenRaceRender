# Widget channel selection

Select a display and choose its data input, then choose **Automatic** or a specific column under **Channel**. The caption beneath the picker identifies the actual source column. Imported field names such as `Gear`, `RPM` and `Accel Y` also appear as selectable values, so the picker does not misleadingly show Automatic for an unmatched saved value.

| Display | Automatic field |
| --- | --- |
| Speed, speed graph, peak/base speed | Speed, converted to the project's speed unit |
| Tachometer, shift lights | RPM |
| Gear | Gear, held between updates |
| Peak turn G | Lateral acceleration |
| Throttle/bar, brake | Throttle/accelerator, brake |
| Temperature | Oil, coolant or intake, identified by the display name/style |

The peak banners calculate completed extrema from their source history; a recording does not need dedicated “peak speed” or “peak G” columns. Seeking and exporting a partial range replay the required prior state. A peak is held until another qualifying event completes, so it can differ from the current speed or G value.

The source caption reports **Channel unavailable in this input** when a field is absent. For example, a recording can include coolant and intake temperatures without recording oil temperature. Selecting Automatic cannot supply an unrecorded measurement. Generic Enhanced scripts without a known widget type need an explicit column.

## Compatibility fixes

An earlier template decoder advanced its generator at a position where the format skips it. This could corrupt six bytes near the start of an Enhanced payload's channel name while leaving its drawing script intact. The decoder now respects that skip. Native projects containing the known affected 67,168-byte payload signature recover those channel bytes on open. Existing explicit native selections and segment overrides are retained; opening a file does not rewrite it. Save the project normally to persist the recovered names.

Automatic is now an explicit override: renderers use the widget's standard field rather than falling back to the imported payload's channel name. This also remains Automatic after saving and reopening older native projects. Numeric legacy displays no longer interpret their color/text header as a channel name.

## Verification

Synthetic tests cover the decoder's fixed byte vector, affected channel recovery, unaffected/localized names, explicit and segment overrides, save/reopen, and rendered Automatic values for gear, shift lights, all three temperatures and persistent speed/G displays. Local validation also opened an affected native project in the GUI, checked Automatic source captions, reimported its original template, and inspected frames from a three-second H.264 export. Private projects, recordings and vendor templates are excluded from the repository.

For a project-level mapping report:

```sh
./scripts/run.sh inspect project.orrp
```

Each display reports its saved `channel`, semantic `resolvedChannel`, and matched `dataChannel` (null when unavailable).
