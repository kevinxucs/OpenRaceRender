# Guided project setup

Choose **Setup** in the toolbar or **File → Project setup…**. The same screen is available from the session inspector.

1. Add your files and choose a primary video, audio or data stream. **Trim start & end…** opens the visual source tool. **Set project length to match** keeps project length tied to that stream as trims, playback rate, delay or joined clips change. Trim physical members of a virtual joined stream through the input inspector.
2. Synchronize each other data input to a recorded event in the video, or open **Side by side…** for another camera. These tools return to setup afterward. **Edit input** opens its inspector for source offsets, rates and data configuration. See [camera synchronization](source-synchronization.md).
3. Choose a data input and template. That input is the default mapping for the template's data roles; each role remains adjustable in the template browser. Open the palette to add displays or open the chosen data inspector to configure channels.

Settings below these steps include session name, length policy, preferred speed unit and notes. Project changes apply as you go; Undo remains available after closing setup. Nested trim edits retain their own Apply/Cancel draft behavior.

## Length and preferences

- **Longest input** follows the longest timed source placement.
- **Match an input** follows an independent timed stream, including its joined sequence. Stills and individual joined children cannot be selected as length sources. Removing the bound stream returns to automatic length; Undo restores the binding.
- **Manual** accepts a finite positive duration. Choosing a mode clears the previous mode, so an old manual value cannot silently override input binding.

The transport length is green for input binding and blue for manual length; its help text identifies the policy. Project export In/Out marks remain separate. Notes, speed units and length binding save with native projects and supported legacy RRP exports. Session notes/length do not enter portable templates.

If a length change leaves the playhead beyond the new end, playback pauses and moves to the last project frame instead of leaving the composition outside its playable span.

Changing speed units in setup or the transport also saves the preferred unit for new sessions. **Use setup for new sessions** remembers whether File → New session opens this screen. Existing projects retain their saved unit. Preferences use the app's normal macOS preferences domain; they do not require scanning Documents.

## Validation and limits

The mirrored ProjectSettings guide was read. Three core and four editor tests cover dynamic trim/rate/delay/join/loop length, invalid policies, native/legacy persistence, template isolation, saved defaults, undo/source removal, selected-data mapping and nested synchronization preview ownership. All 219 tests pass with local library and graphics access.

`scripts/validate-project-setup.py` creates original camera/data fixtures, renders before/after changing a bound source trim, checks actual video duration against a longer logger file and compares encoded frames with snapshots. Artifacts remain in ignored `build/validation/project-setup`.

Live setup-sheet and native-app interaction remain unverified because the UI connection reports `cgWindowNotFound`.
