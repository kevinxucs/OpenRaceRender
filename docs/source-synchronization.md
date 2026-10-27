# Side-by-side camera synchronization

Choose **Sync → Cameras side by side…**, **Timeline → Synchronize cameras side by side…**, or the button in a video input's inspector. Project setup also offers this tool beside other cameras.

Choose a reference camera and a different independent target camera. Each raw-source preview has its own slider, source-time field, source-frame steps, Play/Pause and Mute. Find a shared event, such as brake lights, a track marking or a distinct sound. Choose the target playback rate if drift requires adjustment, then select **Align these events**.

Alignment changes the target offset and optional rate together in one undoable edit. The reference timing, source trim, project delay, export marks and other inputs remain unchanged. Positive target offsets skip its initial footage; negative offsets delay it. A target event before its trim or a reference event outside its active span cannot be aligned. A project delay later than the chosen event must be adjusted in the input inspector first.

**Play together** auditions both raw sources from their current positions at their selected rates. These are independent players, so this is not a sample-accurate mixed-audio or composition playback test. **View in composition** closes the tool and seeks the main preview to the saved alignment; play there to check another event and fine-tune the rate if needed. Repeated alignment retains Undo history.

Raw previews apply the media track's orientation and show its full frame. Project crop/color/display effects appear in the composition. Steps use nominal source FPS, which is approximate for variable-frame-rate recordings. Loading/seeking errors are visible and prevent alignment until resolved; obsolete asynchronous loads/seeks cannot replace the newly selected source state.

A physical member of a joined stream can serve as the reference. The first active occurrence is used for a looping reference. Targets must be independent physical camera inputs; adjust joined/virtual target stream timing in its inspector. Selecting a reference and target from the same stream is refused because changing the target would also move the reference. Audio/data event support remains available through the existing data wizard and input timing controls.

## Validation

The mirrored InputFileSync and HowTo-MultipleDataInputs guides were read. Four core tests cover both offset directions, reference/target trim/rate/delay, joined and looped reference clocks, same-stream protection and invalid alignment transactionality. Two editor tests cover one-step undo and real AVAssetWriter/AVPlayer media seeking, metadata and cleanup. All 225 tests pass with graphics/local-library access.

`scripts/validate-source-sync.py` generates two original flash-event camera files with a two-second difference. It checks synchronized snapshots, rebuilt RRP reopening at matching dimensions, marked export and encoded output frames. Artifacts stay under ignored `build/validation/source-sync`.

Live tool/native-app interaction remains unverified because the UI connection reports `cgWindowNotFound`. The real-player automated test exercises media APIs without claiming that live UI verification occurred.
