# 360° projects and source projection (F34)

Enable **360° equirectangular workspace** in Session settings or Project setup. The initial size is 3840×1920. The coordinate range expands to **−100% through 200%** in both directions. Normal templates stay in the central 0–100% area and appear one-third as wide/high. Source timing, export marks and data mapping are unchanged. Workspace changes, geometry and lens settings participate in Undo and native `.orrp`/`.orrt` persistence.

The preview's **360 view guide** outlines that center area and its horizontal band. It is an editing aid and is not rendered into snapshots/video. Drag/drop, hit testing, marquee selection, resize handles, alignment, pixel nudges and group transforms use the expanded coordinates. **Align to canvas → Fill 360 workspace** fills the panorama with the selection. A flattened 360 video should usually fill −100,−100 with width/height 300%; normal overlays and conventional cameras can remain around the center. Keep text and gauges near Y 0–100% to limit apparent distortion in a spherical viewer. Templates marked as spherical enable the expanded workspace when applied; flat overlay templates can still be used within it.

## Source and display picture controls

Open **Picture & orientation → Fisheye / 360 projection** on a video/image source or display:

- **Equirectangular panorama** pans an already flattened image horizontally, wrapping at the seam. Pan is in degrees; positive angles select increasing source longitude at the center. Fractional shifts blend across the first/last columns.
- **Single fisheye lens** unwraps an equidistant circular lens to a 2:1 frame. Set lens field of view, optical axis (**Up**, suitable for 360fly-style layouts, or **Forward**), normalized center and radius as a fraction of the shorter source edge. Coordinates use the app's lower-left origin. Pan adjusts the front-facing direction. Uncovered rays or coordinates outside the source remain transparent, so video displays black there over the normal background.

The default fisheye calibration is 240°, centered, with radius 0.5 of the shorter edge. It is a starting calibration, not a claim that every camera matches this model. Input/display controls are composable; do not unwrap the same source twice. Image/video transforms, picture effects and projection share the snapshot, preview and export path. Per-display lens settings can be saved in a template; the existing reusable-layout workflow clears source-specific input picture settings along with source paths.

Dual-lens stitching, vendor-specific distortion calibration/automatic 360fly identification, cubemaps/mesh projections, VR180, stereoscopic spherical media, native RRP lens/workspace writing and an interactive VR headset viewer are outside this implementation. Native RRP export refuses the new unverified settings. Native panoramic workspace mode 6 is recognized on RRP/RRT import. Native input sphere mode 2 imports its saved pan and FOV into the up-facing single-lens model with a calibration warning. Use the camera's software to stitch multi-lens recordings first. Already flattened video can be configured explicitly even when its source lacks metadata.

## Output and metadata

The output profiles include **360° panorama · 3840×1920** and **360° draft · 1920×960**. Spherical metadata defaults on for spherical projects. Marked output requires a 2:1 frame and no border; choose a matching output profile/size. The editing canvas and independent output settings keep their existing roles. To render an ordinary flat diagnostic file, turn off **Include 360° spherical metadata**. The app writes a monoscopic Google Spherical Video V1 marker after encoding, without recompressing media. Old 16:9 spherical compatibility modes are not implemented.

**File → 360° metadata tool…** inspects MP4/MOV markers and writes a distinct add/clear copy. It never overwrites the input or an existing output. Adding requires one monoscopic video track and a 2:1 encoded frame. The tool only marks the supplied picture; it does not unwrap/stitch it or compensate track rotation. Clearing removes active V1 spherical UUID and V2 `sv3d` markers, while retaining unrelated metadata and stereo declarations.

The implementation retains existing media bytes/chunk offsets, replaces the old movie index with an ignored `free` atom and appends the new index. App-generated outputs use this operation on their newly created file; the separate tool works on a copy. Frame/audio data is not decoded or re-encoded. File-copy behavior can benefit from the filesystem's copy support, and all index reads are bounded to 64 MiB. Fragmented movies, multiple video tracks, unrecognized sample entries and zero-sized atoms over 4 GiB are refused. The resulting active index is at the end; fast-start placement is not preserved. Old ignored index bytes may remain in `free` space, so clearing markers is a playback/metadata operation, not forensic erasure.

CLI examples:

```sh
OpenRaceRender spherical-metadata video.mp4
OpenRaceRender spherical-metadata video.mp4 --add --out video-360.mp4
OpenRaceRender spherical-metadata video-360.mp4 --clear --out video-flat.mp4
```

## Validation

382 tests pass with local library/graphics services. New core tests compare pan/seam and fisheye pixels to analytic coordinates, verify transparent uncovered directions, expanded geometry/persistence/templates, safe V1/V2 marker editing and a playable automatically marked export. Editor tests cover negative-coordinate drop placement, pixel nudges, alignment/fill, Undo and templates.

`scripts/validate-spherical.py` compares pan to an independent FFmpeg rearrangement and fisheye output to an independent CPU model. Video and audio packet hashes remain identical across add/clear copies; FFprobe independently recognizes the equirectangular marker. Marked full-session/chunk frames match. Original synthetic snapshots were visually inspected. Native RaceRender was operated on an original synthetic video using its panoramic template. Its saved workspace mode, expanded geometry and sphere pan/FOV controls were verified, and an independent native snapshot was compared. This exposed and fixed padded bitmap import and bottom-up artwork orientation. The native sphere mapping differs visibly from the equidistant model: saved pan/FOV import does not establish native projection pixel parity. Real camera calibration and interactive viewer behavior remain unverified. OpenRaceRender’s live workspace toggle, dimensions, guide and Undo were verified on a disposable blank session. Native fixtures and locally supplied template artwork remain ignored and are not committed.

References: locally mirrored [RaceRender 360 guide](https://racerender.com/RR3/docs/Pano360.html), Google's [Spherical Video V1](https://github.com/google/spatial-media/blob/master/docs/spherical-video-rfc.md) and [V2 metadata](https://github.com/google/spatial-media/blob/master/docs/spherical-video-v2-rfc.md). The shader and MP4 editor are independently implemented; no vendor code or calibration assets are included.
