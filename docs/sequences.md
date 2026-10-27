# Joined sequences and time fillers

Select a video/audio input and choose **Edit joined sequence…** in its inspector, or **Edit sequence / add time filler…** from its source-list context menu. The editor shows the physical clips in playback order. Move them with the up/down buttons, rename them, change playback rate or open **Trim clip…** for the visual trim tool.

**Add time filler after selection** inserts a one-second gap. Select it to change its duration, move it anywhere in the sequence or remove it. During a filler this stream contributes no picture or audio; other sources and overlay objects continue. A gap above another camera reveals that camera. With no camera underneath it, the canvas is black.

All sequence changes are private until **Apply**, which creates one undoable edit. **Cancel** leaves the project unchanged. If another operation changes the project while the editor is open, Apply refuses the stale draft so that newer changes are preserved. Physical source trim sheets inside the sequence also use private Apply/Cancel drafts.

The editor keeps the logical stream's source role stable, even when its original first clip moves later. It creates a virtual container where needed and retains the original picture/audio/trim settings on the physical clip. Root duration metadata follows source edits. Trims on a virtual root still limit the stream; stale source-duration metadata alone no longer cuts newly extended child clips.

## Other source controls

The source-list context menu offers **Move stream up/down** for independent inputs and **Move clip up/down** for joined members. Streams move with their members; moving joined clips changes playback order. Source identifiers and display bindings remain stable. Join roots and gaps have explicit labels instead of appearing as missing template files.

Gap inputs have their own inspector with label, positive duration, sequence editor and remove controls. They need no external file. Removing a filler or unjoining/trimming a clip updates root duration. Importing another media file no longer mistakes an empty-path virtual join root for a template placeholder.

**Join after previous input** supports compatible physical inputs and virtual streams with neutral overall timing. Merging a virtual source removes its container rather than adding the container's duration as an extra clip. Source switches and primary-length bindings follow the combined role. Reset overall source-stream trim/rate/delay/offset/loop before merging a virtual stream; clip-level timing remains intact. Existing source video/audio displays may be removed by joining, as in the original join command.

## Rendering and interchange

Native `.orrp` saves retain explicit time fillers. Portable templates retain source roles instead of session sequences. Legacy RRP export refuses explicit filler records until their native encoding is verified; it does not substitute an empty media path. An imported unverified native source type produces a warning, and native filler import is not claimed.

AVFoundation's empty composition tail did not keep the video reader producing frames. A hidden end-clock track now references a retained source asset so that trailing gaps and overlays render to the requested end. The hidden frame is never drawn. Audio can end at the final real audio sample; a trailing filler still has no sound. This requires at least one readable camera in the project; camera-free export remains F27.

## Validation

The mirrored Main guide's Join, Move Up/Down and Add Time Filler workflow was read. Seven core and three editor tests cover private drafts, first-clip moves, exact middle/trailing gap clocks, child trim/metadata, stale/bad edits, root/member ordering, source roles, native persistence, asset validation, safe stream merging, undo and adding audio beside an existing virtual root. All 235 tests pass with local library and graphics access.

`scripts/validate-sequences.py` generates original red/blue camera clips with distinct tones. It checks middle/trailing gaps, continuing overlays, native reopening, encoded duration/pixels/audio and exports containing only a gap. The source trim media acceptance is rerun after the shared timeline changes. Artifacts are ignored under `build/validation/sequences`.

Live updated/native UI remains unverified because the UI connection reports `cgWindowNotFound`. No claim of native filler record or live UI parity is made. The media pipeline uses the [AVFoundation reader/compositor/writer interfaces](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html); the trailing-gap behavior above was established by local encoded-output tests.
