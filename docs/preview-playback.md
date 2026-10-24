# Black composition preview

The composition could turn completely black during playback even though the
playhead advanced and AVFoundation continued decoding frames. Both the camera
and the composited telemetry disappeared; the selection outline remained visible.

The preview inserted an `AVPlayerLayer` manually into the sublayer tree of an
AppKit-managed, layer-backed `NSView`. The fix creates the player layer through
`makeBackingLayer()` instead. AppKit manages its geometry and lifecycle, and the
transparent selection/drop overlay remains a normal subview. Refreshing the
preview changes the player and redraws the overlay without manipulating the
backing layer's frame or inserting an unmanaged video sublayer.

This follows AppKit's [backing-layer customization API](https://developer.apple.com/documentation/appkit/nsview/makebackinglayer())
and its [guidance on layer ownership](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html).
The compositor, picture adjustments and export pipeline are unchanged.

## Verification

- Reproduced the black preview in the open, imported Laguna Seca session before
  the change. System logs showed successful camera decoding and frame delivery.
- Reopened a separate native copy preserving the open session's edits. Verified
  the camera and all 18 displays at the start, during playback, after a seek past
  16 minutes, and paused at the original failure position of 48.7 seconds.
- `PreviewTests` exercises resizing, redraws, nonzero view origins, removal and
  reattachment, player replacement, and clearing the player. It fails against the
  old implementation and passes with the fix.
- All 73 tests completed with no failures; three optional local-fixture tests
  were skipped. No private media, project files or screenshots are committed.
