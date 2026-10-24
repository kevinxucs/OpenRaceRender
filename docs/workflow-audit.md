# Session and template workflow audit

Reviewed on 2026-10-24 using the native macOS editor, synthetic video/telemetry, saved project files, exported media, and the installed RaceRender layout library. Private recordings and vendor assets stay outside the public repository.

## Story 1: synchronize and render a session

| Step | Gap found | Change |
| --- | --- | --- |
| Import footage and CSV | Template source placeholders could remain disconnected when files were added later. | Imported files fill matching empty source roles; existing video display positions are retained. |
| Apply an existing template | Source pickers offered incompatible media; fallback mapping could attach an image or gauge to the wrong type. | Source choices and remapping match media types. Explicit “None” stays unassigned, including segment source switches. |
| Align a lap start | The sync sheet obscured the preview and offered only a coarse slider and frame buttons. It recalculated the event list during every seek. | The wizard includes a live video preview, recorded lap/event picker, direct video/source time entry, play/pause, second/frame stepping, alignment feedback, and a seek-to-event check. Event discovery runs when the source changes. |
| Select render bounds | Flags were buried in a menu, invisible on the timeline, and could form an inverted range. | Visible In/Out buttons, I/O shortcuts, colored timeline boundaries, a shaded span and exact-time navigation. Setting a conflicting mark clears the opposite mark. |
| Adjust picture | Input-wide brightness, contrast and saturation already worked, but the scope and reset behavior needed care. | Controls retain their source-wide scope; resetting an imported camera preserves its decoder color interpretation. Display-specific adjustments remain separate. |
| Save/reopen | Some direct session edits did not mark the document dirty; selecting a preview object did. Save dialogs could append the native suffix twice. | Session bindings participate in undo/change tracking; selection alone creates no undo entry. Native file types are declared and save names receive one extension. |
| Render again | Toolbar export initialized marks, while Command-E could retain the initial ten-second range. The previous destination was forgotten. | Both routes initialize from saved marks or the previous custom range. Output location, custom range and encoder settings persist in the project. Repeat exports suggest a numbered filename. |
| Render the marked span from CLI | Omitting range flags rendered a fixed ten-second clip. | Saved marks are the default; explicit flags override them. Invalid or out-of-project ranges are rejected before choosing output. |

The UI acceptance session aligns data Lap 2 at 4.000 seconds to video 3.000 seconds, giving a +1.000-second source offset. It marks 3.000–8.000 seconds, adjusts brightness/contrast/saturation to 0.9/1.1/1.2, saves, and renders a 5.000-second H.264/AAC file containing 150 video frames at 30 fps. Reopening preserves those marks, and Command-E restores the same range and suggests a second output filename in the previous folder.

Export settings and the chosen output location are saved into an existing `.orrp` when rendering begins. An unsaved project still needs Save to persist its settings. Existing output files are never overwritten by the exporter.

RaceRender's documented workflow also aligns a visible video event with a recorded data event; its export flags prefill a time span. References: [Synchronization Tool](https://racerender.com/RR3/docs/InputFileSync.html), [Create Video File](https://racerender.com/RR3/docs/CreateVideo.html).

## Story 2: design and reuse a template

| Step | Gap found | Change |
| --- | --- | --- |
| Start with a blank layout | No explicit blank choice; removing existing overlays was manual. | “Blank” in the template browser and “Start blank layout” in the editor retain footage/audio and remove overlays in one undoable action. |
| Add widgets | Widgets were hidden in an add menu, with no draggable palette. Empty projects hid the preview even after adding objects. | A scrollable widget palette supports click-to-add and drag placement. A project with display objects shows the design canvas even without inputs. Text objects start with visible sample text. |
| Edit widget properties | Geometry, source/channel, ranges, accent, gauge design, visibility and picture/orientation controls existed. | New objects select their inspector immediately. Empty-source widgets can bind when telemetry is subsequently added. Preview clicks alone no longer dirty the document. |
| Save a reusable template | Saving immediately opened a file dialog, retained session export/data configuration, and could leave gauge artwork linked to external files. | A named template/style dialog explains its contents, optionally includes camera/audio positions, strips source paths/timing/data configuration/export state, and embeds image and gauge-background bytes. |
| Find the saved template | Custom layouts had no generated thumbnail; the save location was arbitrary. | Save defaults to `~/Documents/OpenRaceRender/Templates` or `Styles`. The browser reads these folders and generates native-layout previews. |

Native reusable files use `.orrt`. They are source-role placeholders and artwork, not copies of video or telemetry. The same layout can bind to a new session even when its source numbers differ. A saved single display uses the same container and appears in the Styles category when saved there.

RaceRender likewise distinguishes reusable display layouts from session inputs and allows template exports to include selected displays. Reference: [Create Template](https://racerender.com/RR3/docs/TemplateCreate.html).

## Additional stories explored

| Story | Gap fixed | Verification |
| --- | --- | --- |
| Open a library on a slow or unavailable filesystem | Synchronous directory enumeration froze the editor during the live check. Discovery and thumbnails now run outside the main thread, with incremental results and cancellation. Missing roots are checked before enumeration. | The rebuilt browser displayed all 61 packaged templates and remained responsive while scanning fallback folders. |
| Move a project folder with its media and custom artwork | Input paths were relative, while image-display and gauge-background paths could still point at the old folder. Missing absolute paths could acquire an unrelated project-directory prefix. | Native save/read handles all three asset references relative to the project. A regression test moves the folder and verifies the resolved paths. |
| Relink a replacement camera clip | Relink refreshed telemetry lengths but left a video's old duration. | Video/audio relink reloads AVFoundation duration. |
| Remove a telemetry source, then undo | Restoring the input list did not necessarily reload telemetry when channel settings were unchanged. | Reload is now keyed to data paths, source numbers and data settings. |
| Drop multiple media/data files together | Independent asynchronous imports could choose the same source number. | Finder drops are batched and media imports are serialized through one queue. |
| Re-render without overwriting an earlier result | Reusing the prior name could lead directly to an export error. | An available numbered filename is suggested while keeping the previous directory. |

## Automated checks and scope

`WorkflowTests` covers synchronization with positive/negative offsets and trimmed/rate-adjusted sources, rejection without mutation, saved marks/destination round trips, invalid ranges, template sanitization/art embedding, source remapping and moved project assets. `scripts/validate-media.py` checks actual decoded video/audio, timing, fractional frame rate, encoder metadata, layers, camera switching, and a CLI export that honors saved marks over stale previous export settings.

Live UI verification completed for both requested stories. The final retest exposed a nonworking SwiftUI drag path across the AppKit video preview. Native palette mouse tracking now places one widget at the release point, shows a drop indicator, and cancels without editing when released outside the preview.

The template acceptance run dragged Speed and G-Force onto footage with imported CSV data, renamed Speed to “Session Speed,” set its maximum to 200, sweep to 240 degrees, label to “Speed,” and precision to one decimal. The native save dialog produced one `.orrt` extension in the custom Templates folder and included the two overlays without camera displays or session state. The library discovered the file with a generated thumbnail. Applying it to a separate 640×360 session retained its camera at input 4 and remapped both widgets from telemetry input 2 to input 9. Reading the UI-saved files verified identical geometry/settings, and a rendered frame showed 29.1 MPH and 0.22 G at three seconds. No live verification remains pending for these stories.

This audit improves these concrete workflows; it does not establish full RaceRender feature or pixel parity. Advanced audio/picture effects, grouping, arbitrary scripting and legacy timeline import retain the limitations listed in the [feature audit](racerender-feature-audit.md).
