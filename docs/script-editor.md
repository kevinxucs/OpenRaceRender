# Enhanced script authoring

Add an Enhanced display, or select an imported script-based display, then choose **Create/Edit drawing scripts…** in the inspector. The editor keeps private background/foreground drafts. Choose the stage, edit monospaced source, import/save UTF-8 text, set the canvas (1–2048 pixels per side), font, persistent variables and canvas-aspect behavior. The preview's checkerboard shows transparency.

**Compile & Test** parses both stages, checks supported function names including unreachable branches, then runs the actual bounded drawing interpreter at the selected project time. It uses recorded source placement/trim/rate or explicit design sample data. Samples are never saved/exported. **Playhead** copies the composition time. The test preview is the raw script canvas; group visibility, separate widget backgrounds, picture transformations and instance opacity are not included.

Output messages show stage/line syntax errors, runtime errors and Print output. A passing test covers the current inputs/branches, not every possible data value. Print reports background/current foreground output while suppressing historical replay spam. At most 100 messages of 2048 characters are captured, with an omission count. The worker runs off the UI thread; Cancel test, editing or closing invalidates stale results and cancels execution. Parser/source/variable/expression/instruction/replay bounds remain enforced. There are no loops, arbitrary evaluation, native lookup, file access or network access from scripts.

Apply validates the complete draft, checks that the document/object/edited segment still match the original, then writes one undoable edit. Identity, placement, source, channel, grouping, marks and unrelated payload fields remain. Imported canvas metadata is updated with aspect choices. Timeline edits use existing inheritance; Cancel changes nothing in the project. Changing code/font/canvas invalidates cached rendering through the payload identity. Applying a script style preserves its canvas aspect while retaining the target widget's instance settings.

For source-free scripts, SampleTime and DisplayTime follow elapsed project time from the object's active segment. Recorded scripts retain their source clock/rate. Persistent replay remains deterministic for repeated/backward/nonzero chunk rendering. This version does not change the existing background execution/cache policy for stateless scripts.

## Persistence and compatibility

Sources/fonts/canvas/flags are stored using the existing structured Enhanced payload in `.orrp`/`.orrt`, retaining scripts through templates/styles and native Undo. Newly authored displays have no fabricated native common record: rebuilt native `.rrp/.rrt/.rro` export refuses them until that authored encoding is verified. Existing imported native script payload edits retain the previous legacy writer's checks; live native reopening of these new edits remains unverified. Text source import/export uses UTF-8, while the native guide's language describes ASCII strings. Do not assume native acceptance of Unicode source extensions.

The editor exposes the implemented language, rather than guaranteeing complete language/visual parity. F29 adds [time formatting, names, record queries and type rules](script-semantics.md). Print has a diagnostic sink; ordinary preview/export does not write those messages to external files or services. Font availability, gradients and other drawing approximations retain their existing limits.

## Command line

```sh
OpenRaceRender script-edit project.orrp --object 0 \
  --background background.txt --foreground foreground.txt \
  --canvas-width 320 --canvas-height 180 --font Helvetica \
  --persistent --out scripted.orrp
OpenRaceRender script-check scripted.orrp --object 0 --time 2.3 --out test.png
OpenRaceRender script-check layout.orrt --object 0 --time 2.3 --samples
```

Indexes are zero based; omission selects the first eligible Enhanced display. Script edit changes the base display and preserves later segment overrides; GUI supports selecting a timeline segment. `--stateless` disables persistence. Script-check resolves the active segment, emits JSON diagnostics and optionally saves PNG. Sample checks skip missing recorded-source loads. Source editing can run without valid linked media. Input and output projects must differ; newly authored output uses `.orrp`.

`convert project.orrp --out layout.orrt` now exports a portable layout, stripping source paths/timing/export state instead of merely renaming the project JSON. Script source/settings are retained.

## Validation

The supplied full mirrored Enhanced editor/language guide was read. Four new core/two editor tests cover exact known pixels, persistent/stateless counts, current-only messages, rate and source-free clocks, source/font/canvas/native persistence, template retention, canvas/style aspect, unknown unreachable calls, size/NUL/depth/cancellation limits, draft isolation, Apply/Undo/timeline and stale-object/segment protection. The full local suite passes 336 tests with the authorized library/graphics services.

`python3 scripts/validate-script-editor.py` authors original code through the public CLI, checks byte-exact source/settings and original-instance retention, tests messages, compares encoded full/chunk frames with independent solid-color references across a telemetry trigger, checks portable template/sample testing, and refuses invalid source without an output file. Tests/artifacts stay under ignored build/validation/script-editor. Existing persistent-history tests remain unchanged and pass.

Live editor interaction, source file panels and native source reopening remain unverified. CUA was retried for this feature and still reports cgWindowNotFound. The first CLI acceptance run found a missing command-dispatch registration, which was fixed; its own untouched blank test process was stopped. No user session was opened or altered.
