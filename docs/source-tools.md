# Visual source trim and crop

Select a physical input in the source list. Under **Trim & playback**, choose **Visual trim…** or **Crop / zoom…**. Both pause playback and edit a private draft. **Apply** makes one undoable input change; **Cancel** leaves the project unchanged.

## Trim

Video uses paired first/last frame previews, source-time fields, sliders, one-source-frame steps and **Use playhead**. The end boundary is exclusive; its preview shows the last included frame. Metadata supplies actual source duration and nominal frame rate. Data inputs offer Speed, RPM, G-force and Map previews; audio inputs show source times.

The effective length includes playback rate. Synchronization offset, project delay, rate, looping and project export In/Out marks are preserved. A positive synchronization offset already excludes earlier source frames; adjust synchronization first to restore them. Invalid or reversed bounds cannot be applied. **Use playhead** refers to the selected physical joined clip and reports when that clip is inactive.

Virtual join roots do not expose these tools. Select a physical member instead. Frame steps use nominal source FPS; variable-frame-rate files do not have a guaranteed constant frame duration. Data/audio stepping uses project FPS and does not imply that the logger/audio has video frames.

## Crop and zoom

The source preview shows the full oriented frame. Draw a rectangle or drag its corner handles; turn on **Drag to move selection** to reposition it. Pixel edge fields, source/selection dimensions, pixel nudges, centered zoom and full-frame reset are available. The result preview includes the input's existing picture settings.

The rectangle uses top-left source pixels and stores the existing normalized crop fields. Each dimension retains at least 5% of the source, matching the picture processor's bounds. Crop occurs before picture rotation and flips; the source preview applies the media track's orientation. Video offers a preview-time slider, source-frame steps and playhead capture. Images use their actual pixel dimensions.

Image-source picture adjustments now affect file-backed image displays, including images mapped to telemetry. Relinking follows the artwork path even when its display is bound to a data input. Portable template export bakes source picture settings into embedded artwork before discarding session image roles, avoiding lost crop settings or applying them twice.

## Validation

The mirrored RaceRender InputFileTrim/InputFileCrop guides were read. Six core and two editor tests cover crop pixel geometry, letterboxing, bounds, zoom, picture preservation, physical trim timing, invalid drafts, exact portable-image pixels, joined-clip playhead selection and undo. The existing relink regression also covers telemetry-bound images and source-path events. All 212 tests pass with local library and graphics access.

`python3 scripts/validate-source-tools.py` generates original test video, compares physical source frames after trimming, reopens a rebuilt legacy project, checks retained In/Out marks and compares encoded output against snapshots. Artifacts stay under ignored `build/validation/source-tools`.

Live operation of the updated sheets and native RaceRender remains unverified: the UI connection still reports `cgWindowNotFound`. Automated round trips do not establish native-app or pixel parity.
