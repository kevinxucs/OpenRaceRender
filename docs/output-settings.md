# Output profiles and workspace

The export sheet has independent output controls. Changing resolution/FPS no longer resizes the editing canvas or changes preview/script clocks. Existing projects without output overrides follow their original canvas/FPS and default stereo 48 kHz audio. Saved marks, time/lap ranges and remembered destinations retain their existing behavior.

Select a **Local file**, **Internet**, or **Television** distribution profile. These are OpenRaceRender presets: local 4K30 at 50 Mbps, local 1080p30 at 20 Mbps, internet 1080p30 at 8 Mbps, internet 720p30 at 5 Mbps, and television 1080p30 at 20 Mbps with a 5% border per side. They use high scaling and stereo 48 kHz / 240 kbps AAC. They are starting configurations, not externally mandated upload specifications. Edit any field afterward for a custom configuration.

Name a configuration and choose **Save / update profile** to reuse it on this Mac. A matching name updates that custom profile; built-ins remain fixed. **Remove** removes only the saved custom preset; applied project settings remain. User profiles are stored in application preferences. Settings applied to a project travel in `.orrp`, even on another Mac without the saved preset. No proprietary native preference/profile file import is claimed.

**Aspect / workspace** offers project, 16:9, 4:3, square, portrait and 21:9 sizes; Picture height preserves the current output aspect. Exact even Width/Height fields support custom sizes. **Fit original canvas** letterboxes the complete project within that size. **Use output proportions** repositions/resizes percentage-based layout using the output aspect, like the native guide's workspace behavior. Individual media Maintain Aspect settings still apply. A warning explains differing proportions. Neither choice modifies the main preview. The export preview is not a separate live thumbnail; use a short rendered range to review a different output aspect.

**Outer border** reserves 0–20% of total width and height on each side, then fits/reshapes the entire composition inside it. Cameras and widgets are clipped to the inner workspace. Scaling offers high Lanczos camera downscaling/high bitmap interpolation, linear, or minimal nearest-neighbor. Source decoding can still dominate performance; no native performance or scaling-algorithm equivalence is claimed.

Audio choices are stereo, mono or no audio, at 44100 or 48000 Hz. Sources retain their routing/gain/display gates before the final audio mix converts to the selected PCM format and AAC encoder. H.264 uses 16-bit PCM into AAC; AAC itself is compressed and has no PCM bit-depth promise. Codec availability/bitrate support remain subject to the host. Video uses H.264 High Profile/Rec.709, automatic or explicit video bitrate and AAC bitrate. Invalid settings are reported before media preparation/output creation. The export sheet keeps its action buttons visible while its controls scroll.

Controls edit saved project export settings with Undo. Cancel closes the sheet while retaining those edits; rendering saves settings/destination with the project. Portable templates strip export settings/profile IDs. Native RRP export retains its existing application-preference limitation: these OpenRaceRender output options are not written as proprietary native application settings.

## Command line

```sh
OpenRaceRender export session.orrp --profile internet-1080 --out share.mp4
OpenRaceRender export session.orrp --width 640 --height 480 --fps 15 \
  --workspace fitCanvas --border 5 --scaling high \
  --audio-rate 44100 --audio-channels 1 --out review.mp4
```

Profile IDs: local-4k, local-1080, internet-1080, internet-720, television-1080. Later explicit options override profiles. Workspace is fitCanvas or output, border is percent per side, scaling is high/linear/nearest, channels are 0/1/2. CLI export size/FPS overrides affect output settings only; snapshot size options keep their existing still-image behavior. CLI never saves overrides into the input file.

## Validation and limitations

Mirrored CreateVideo/TechInfo guides were read. Four core and two editor tests cover migration, separate encoder dimensions/FPS/bitrate, fit/reshape viewport math, border bounds, invalid no-output preflight, preset/native persistence/template stripping, custom profile lifecycle, canvas/marks/preview preservation and Undo. The complete local suite passes 326 tests with the authorized library/graphics services.

`python3 scripts/validate-output-settings.py` uses only original disposable H.264/AAC media. It compares marked encoded frames against independently mapped snapshot geometry for both workspaces and borders, inspects actual dimensions/FPS/duration and AAC channel/rate metadata, checks silent output, CLI profile/overrides, invalid dimensions and unchanged source project bytes. Logs/artifacts remain under ignored build/validation/output-settings.

Live editor/native export controls remain unverified while CUA returns cgWindowNotFound. 360 workspace/metadata belongs to F34; no spherical projection, additional export codec or native profile-file compatibility is claimed here.
