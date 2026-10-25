# Template designer validation

Reviewed on 2026-10-25 against the installed RaceRender 3.7.3 Ultimate and the user's local `Customized - 1.rrt`. The reference contains one camera and 17 telemetry overlays. No vendor files are included in the repository.

## Workflow and gaps fixed

| Step | Gap | Result |
| --- | --- | --- |
| Start blank | The palette offered only generic appearances, and missing telemetry made some imported displays disappear. | Basic widgets remain available; the design canvas shows marked sample data when there is no real telemetry source. Missing session telemetry never receives sample values. |
| Find the familiar widgets | Peak speed/G and exact thermometer/gauge appearances were only accessible by importing an entire layout or finding individual files. | The palette source picker lists installed templates. `Template: Customized - 1` exposes its 17 individual overlays, including both peak banners and three named thermometers. Library styles and files outside the managed library are also available. |
| Drag and place | Only basic widget kinds could be dragged. | Style and template-component cards have generated previews, click/keyboard insertion, drag placement, release feedback and cancellation outside the canvas. Objects bind to a compatible independent source and receive a fresh identity. |
| Pick another style | No direct inspector entry point; the old generic import replaced geometry and could change widget type/binding. | `Choose widget style…` searches and previews compatible appearances, including native styles. It preserves geometry, identity, label, opacity, active range, picture settings, source/channel and timeline. Incompatible type changes are rejected. Undo restores the previous appearance. |
| Edit display settings | Min/max fields did not change the payload used by imported bars and scripts. Generic accent controls did not control script color slots. | Automatic/manual range controls write the actual imported settings. Enhanced widgets expose caption visibility/text/size, trigger threshold and Color A–H. Scripts use these settings where referenced by their drawing program; hard-coded script colors/text remain unchanged. |
| Fine placement | Resizing could distort a display; precise positioning required percentage arithmetic. | Proportional drag resizing is enabled by default. Align to canvas offers edges and centers. Option-arrow moves one output pixel; adding Shift moves ten. Alignment/nudges support segment edits and undo. |
| Save/reuse | Saving was hidden in the File menu or project inspector once a widget was selected. | The palette has `Save template…`. Saving refreshes its template list, embeds artwork, and strips source paths, synchronization and export state. |
| Gauge captions | A library gauge displayed `%su%` literally. | The token follows project speed units and remains a token in the reusable file. |
| Sidebar space | Adding source, search and style controls left little room for input/object lists. | While designing, the input list collapses behind `Show input files`; the toolbar can still import media. The widget grid scrolls within the sidebar. |

To recreate the familiar design: start blank, open the palette, choose `Template: Customized - 1`, then drag the desired widgets onto the canvas. Clicking a card retains its reference geometry; dragging centers it at the release point and keeps it within the canvas. Percentage fields can reproduce negative reference positions such as the gauges' Y = −19. Use the inspector to select other styles and data channels, then `Save template…`.

The original 17-overlay geometry can also be assembled by inserting each component without a drop point. This permits an exact reconstruction while still allowing each display to be styled and placed independently.

## Verification

Live macOS checks started with an empty editor. The palette discovered `Customized - 1`, showed all 17 widgets, and filtered `Peak` to exactly two cards. Speedometer, Peak+Base Speed and Peak G-Force were dragged onto the canvas. The speedometer changed to `44E - Speed` without changing X/Y/width/height (2.191/2.896/26/46); undo restored its original `Trans 135 - Speed` appearance. A peak G resize changed 22×3 to approximately 30.765×4.195, retaining the ratio; undo restored the original. Option-right advanced X by 100/1920 percent, one output pixel. The script maximum was changed from Automatic to 2 and verified in the saved payload. Both a native project and a reusable template were saved through the UI; neither contains sample telemetry or session input paths.

`WidgetDesignTests` assembles all 17 reference overlays separately, saves/reopens a native template, and compares its rendered pixels with the imported reference using the same sample telemetry. The 960×540 images match exactly, with a nonempty-pixel assertion preventing a vacuous comparison. Additional tests cover source remapping, identity, safe placement, undo, segment alignment, sample-data isolation and incompatible styles. `WidgetDesignStyleTests` verifies that imported bar/script range edits change rendered pixels, color slots change output, script bytes remain intact, settings round-trip and gauge unit tokens resolve.

The full suite contains 115 tests. Local comparison images, the reconstructed template, UI-saved files and logs are under ignored `build/validation/template-design`. The pixel comparison establishes reconstruction fidelity within OpenRaceRender, not pixel parity with RaceRender. All local library artwork/scripts remain private.

## Reference and remaining scope

The installed RaceRender toolbox was exercised directly: Add Display Object → Speedometer shows a visual style grid (45 speedometer styles in that installation). Its public documentation describes [display types and styles](https://racerender.com/RR3/docs/DispObjToolbox.html), [display properties and imported styles](https://racerender.com/RR3/docs/DispObjEdit.html), and the [gauge designer](https://racerender.com/RR3/docs/DispObjGaugeDesign.html). OpenRaceRender uses a compatible-kind appearance picker that retains placement rather than resetting every property on style import.

This work does not add a script code editor, full legacy gradient/needle parameter editing, grouping or every RaceRender rendering effect. The existing [feature audit](racerender-feature-audit.md) records those broader limitations. Public builds retain original basic widgets; the familiar vendor appearances require the user's imported local library.
