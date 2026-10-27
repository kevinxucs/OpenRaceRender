# Input and per-display audio (F23)

Video/audio inputs expose **Input audio**; video and audio display widgets expose **Display audio**. Set volume from 0–200%, mute, left/right balance and channel handling. Image/data inputs do not show unused audio controls. The toolbar speaker button mutes preview globally; input/display settings also affect exported files.

**Mute** stores zero volume, as in the guide. While the inspector stays open, unmuting restores the gain remembered when muted. Reopening a project with zero volume cannot infer its previous nonzero gain. The percentage field and slider edit the same normalized value and support Undo.

Source processing runs first: channel routing, source gain and balance. Each visible display then independently routes, scales and balances that signal, and the display outputs add together. Routing options are stereo, swap, left-to-both, right-to-both and a 50/50 mono mix. Balance attenuates the opposite side linearly. For independent left/right selection from an original stereo recording, leave the input stereo and route each display separately.

Two visible camera displays using one input contribute twice unless their individual gains/mutes are adjusted. Hiding a display or its group removes that contribution at the timeline boundary; opacity is independent of audio. Timeline audio settings inherit/reset like other parameters. Source trims, offsets, rates, loops and joins continue to determine when each audio placement is active. High combined gains can clip at the final sample clamp; lower the relevant source/display gains when mixing loud sources.

## Mono and other PCM inputs

An audio tap can retain a mono source's one-channel processing format, which cannot represent separate speaker gains. Apple documents the tap's [client processing format](https://developer.apple.com/documentation/mediatoolbox/mtaudioprocessingtappreparecallback). OpenRaceRender therefore normalizes mono/nonstereo tracks and unsupported PCM representations to stereo Float32 backing audio before using its shared tap. Supported stereo tracks, including normal compressed camera audio, bypass this step.

Mono expansion preserves the original sample levels and timing; the backing uses Float32 at the source sample rate without a lossy codec. It is shared by preview/export and cached by source path, size, modification time and audio track. Gain, routing and synchronization edits reuse the backing audio. The first preparation needs an audio decoding pass and PCM disk space; subsequent preparations reuse it. Cache files live under `~/Library/Caches/OpenRaceRender/StereoAudio`, never in the project or Documents. They can be removed while the app is closed and will be regenerated. Developer acceptance checks can redirect the cache with `OPENRACERENDER_AUDIO_CACHE`.

Source files remain unchanged. Completed cache files publish atomically, concurrent preparations share a conversion, and missing/corrupt cache data is rebuilt. PCM representations that the tap cannot safely process directly, such as 24-bit packed samples, are normalized as well. Multichannel layouts use the system's stereo conversion; exact surround-layout/native mixing parity has not been validated.

## Compatibility and validation

Input routing/gain/balance and display gain/balance retain known native serialization. The source's stored gain stages now multiply consistently with native export. Per-display routing is an OpenRaceRender extension; rewritten native export refuses it rather than dropping it. Use input-level routing when a native project copy is required.

305 tests pass, including three matrix/legacy cases, two editor-binding/Undo cases and an actual PCM normalization/cache/recovery test. `scripts/validate-audio.py` uses isolated 440/880 Hz channels to verify gain, independent display routing/pan, timed mute/mono, group silence, nonzero chunk gating, hard-panned mono and 24-bit stereo. The former mono-pan failure is covered by this encoded check. The established grouping media regression also passes. Preview and export share the prepared audio mix; live audition/native UI remains limited by `cgWindowNotFound` and is not claimed here.
