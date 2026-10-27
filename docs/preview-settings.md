# Independent preview settings

Open **Preview → Preview settings…** or the sliders button above the composition. Apply saves preferences on this Mac without changing the project, export settings, saved range, dirty state or Undo history. Cancel discards the draft. Defaults are 720p, at most 30 fps, high scaling and full-precision stereo/source-rate audio. The composition header reports the effective preview size/FPS; its size tooltip shows the project canvas.

- Picture height: project size or 180/360/540/720/1080/1440/2160 pixels. The preview preserves the canvas aspect ratio, rounds to even pixels and never enlarges the project.
- Target frame rate: project rate or 15/24/30/60 fps, capped at the project rate. The original scene FPS remains the clock for persistent scripts and telemetry history.
- Scaling: High uses Lanczos for the base camera's downscaling and high bitmap interpolation for other layers. Linear uses bilinear scaling; Minimal uses nearest-neighbor. Vector widgets still draw at the effective preview resolution.
- Reduce while seeking: timeline sliders, graph/object-track drags and synchronization/full-screen sliders request at most 360p/15 fps with nearest scaling. Ending the drag restores normal choices. Preparation is debounced; short drags can finish before the reduced player is ready. Numeric/frame seeks keep normal quality. Playback's UI clock is capped at 60 updates per second.
- Preview audio: Stereo, Mono or Disabled. Rate choices are Source, 22050, 44100 or 48000 Hz. Precision choices are full, 16 or 8 bit. Non-source rates are decoded/resampled once into the same reusable stereo PCM cache used for mono normalization. First preparation can take time and disk space. Mono and precision are applied after each source's display/routing mix; multiple sources subsequently sum. This controls signal quality, not the hardware device's output format or physical channel count. Selecting Disabled or muting the toolbar removes audio preparation/tracks; unmuting rebuilds them.

Video playback uses a separate render configuration, retaining original project dimensions/FPS in the scene. Object-only designs render through the same size/scaling caps into an offscreen bitmap. These controls reduce composition work; source decode, complex widgets and first-use audio conversion can still dominate. No universal speedup or native performance parity is claimed.

## Full-screen composition

Choose **Preview → Full-screen composition** (Command-Shift-F) or the expand button above the composition. A separate composition window enters macOS full screen, hides editing selections and offers play/pause, seeking, time and Close. Escape, Close or leaving full screen returns video ownership to the editor. Playback position/state stay shared. It does not edit or delete widgets. If macOS cannot enter full screen, the separate resizable composition window remains usable.

Only one preview surface owns the AVPlayer at a time. Opening the data synchronization wizard closes the composition window and transfers video to the wizard; closing the wizard returns it to the canvas. Full-screen opening is unavailable while that wizard is active. Camera side-by-side synchronization retains its separate raw-source players.

## Validation and limits

The supplied mirrored PreviewSettings/Main/Troubleshooting guide pages were read. The full suite passes 320 tests locally (258 core/62 editor), with no skips. New tests cover independent size/aspect/FPS caps, seek restoration, invalid preferences, persistence without document/Undo changes, nearest versus linear pixels, quantization and repeated editor/wizard/full-screen ownership teardown. Actual generated H.264 frames verify 320×180 at 15 fps from an unchanged 640×360/60 fps scene, camera-frame transitions and exact blue-overlay area; ordinary preparation retains original dimensions/FPS. Actual audio verifies resampled rate/duration/cache reuse, mono sample equality, 8-bit quantization and disabled-track omission. Media is original and temporary; logs remain under ignored build/validation/preview-settings.

Live settings interaction, full-screen animation/Escape and native comparisons remain unverified because CUA reports cgWindowNotFound. Window ownership tests and actual composed-media reads do not substitute for live display testing. The workspace/aspect choice described in the native guide belongs to F26. Audio precision is a signal simulation on the supported Float32/stereo processing path; no old 8-bit device mode or identical native algorithm is claimed.

Primary implementation references: [AVMutableVideoComposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition), [CIImage nearest sampling](https://developer.apple.com/documentation/coreimage/ciimage/samplingnearest()), and [AVAssetReaderAudioMixOutput](https://developer.apple.com/documentation/avfoundation/avassetreaderaudiomixoutput).
