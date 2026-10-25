# Composition preview lifecycle

The main editor and synchronization wizard use the same composed video player. Video frames include camera picture settings and telemetry overlays; a separate AppKit overlay handles selection and widget dragging.

The player layer is hosted in its own `PlayerSurfaceView`. This view assigns its layer before enabling `wantsLayer`, disables AppKit content redraws, and contains no subviews. The surrounding preview owns the video surface and selection overlay as separate sibling views. AppKit can redraw the container and selection without modifying the video layer's contents.

This follows Apple's distinction between [layer hosting and layer backing](https://developer.apple.com/documentation/appkit/nsview/wantslayer). The earlier `makeBackingLayer()` override let AppKit manage video-layer drawing. That is unsafe because [AVPlayerLayer contents are opaque and cannot be changed](https://developer.apple.com/documentation/avfoundation/avplayerlayer). A layer can retain the right player and dimensions while its onscreen video disappears, so identity/layout assertions alone did not catch this regression.

While the synchronization wizard is presented, the main canvas detaches its player layer. When the sheet closes, ownership returns to the canvas. Dismantled previews detach their layers and release model/canvas references. This avoids competing video surfaces and retained sheet previews.

Regression checks cover resize/reattachment, player replacement, redraw isolation, overlay mouse routing, repeated canvas/wizard handoffs and teardown. Live validation additionally checks playback, seeking, offset edits and wizard dismissal using a local edited session; its private media and recovery copies remain outside the repository.

## Manual frame synchronization

The telemetry input inspector's **−1 frame / +1 frame** buttons adjust synchronization without moving the video playhead. An offset is stored in source seconds, so one project frame changes the offset by `input playback rate / project fps`. Positive advances the telemetry. The buttons preserve other source settings, create an undo checkpoint, and retain the exact value in native project saves. Numeric entry shows up to six decimal places. Synthetic tests cover 24, 30, 30000/1001 and 60 FPS with normal, half-speed and double-speed data.
