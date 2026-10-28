# Session recovery and diagnostics (F36)

Unsaved edits receive a separate recovery copy in:

```text
~/Library/Application Support/OpenRaceRender/Recovery
```

Copies update about 750 ms after editing pauses, with a checkpoint about every three seconds during continuous edits. Encoding runs in the background. Writes replace the previous copy atomically; failed or oversized writes retain the previous successful copy and show a recovery warning. The current snapshot limit is 256 MiB. Recovery is best effort and does not replace saving your project.

After an unexpected exit, the next ordinary launch offers available copies. **Restore copy** creates an unsaved document with its project settings, media references, widgets, output marks and remembered export destination. **Save As** keeps the recovered version. Restoration does not write to the original project. Media stays at its existing locations; unavailable files use the normal relink workflow. The snapshot contains the playhead captured at its last checkpoint. Undo history and an interrupted video export are not resumed.

**Help → Recover unsaved session…** opens the same list later. **Keep for later** leaves copies available. **Archive** moves a copy into `Recovery/Archived`; enable **Include archived copies** to restore it again. A restored copy is archived only after the recovered document has its own durable snapshot. Unreadable copies remain on disk for inspection. Snapshots owned by a running editor are excluded using a process-held lock, which the OS releases after unexpected termination.

Successful saves and confirmed clean shutdown remove only that document's active temporary copy. Other pending or archived recoveries remain. Recovery folders use owner-only permissions and snapshots are readable/writable only by their owner. They contain project content and file references, so treat them like your project files.

**Reopen last saved project on launch** is optional and off by default. Recovery takes precedence over this preference; a project explicitly opened from Finder takes precedence over both. The default startup does not open old Documents/media paths. Restoring a copy or opting into reopening may request access to the referenced folders.

## Recover without opening the editor

When the window cannot start, the built application's CLI can create a new project from a recovery copy:

```sh
build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender recover-project \
  "$HOME/Library/Application Support/OpenRaceRender/Recovery/RECOVERY_UUID.json" \
  --out /path/to/recovered.orrp
```

Choose an actual UUID-named copy and a new `.orrp` output. The command retains the recovery input, refuses copies owned by a running editor and refuses an existing output. It also reads archived or separately copied recovery files.

## Diagnostic log

**Help → Show diagnostic log…** provides a local, selectable event history, Refresh, Export report and Show log folder. The journal is stored in:

```text
~/Library/Application Support/OpenRaceRender/Diagnostics/events.json
```

It retains the latest 1,000 events across launches: imports, telemetry loading, preview preparation/player failure, recovery, saves, exports and clean shutdown. Entries contain typed event names, times, numeric dimensions/counts/timings and error domain/code. Reports add the application and OS versions. Raw error descriptions, source paths, project names/content, telemetry samples and credentials are excluded. Unknown error domains are replaced with `OtherError`. No report is uploaded automatically. Describe your reproduction steps and any displayed error message separately when reporting a bug.

## Validation and limits

400 tests pass with local library/graphics access. New tests cover durable content/marks/output state, original preservation, owner permissions, live-session exclusion, archive/reopen, corrupt/oversized copy retention, stale-write rejection, clean-save/shutdown cleanup, continuous typing, Finder precedence, opt-in saved-project reopen and diagnostic bounds/privacy. A real child process holds a recovery lock; terminating it verifies that the snapshot becomes available without a clean unlock. CLI tests check copied-project output, no overwrite and unchanged source-directory permissions.

`scripts/validate-session-recovery.py` prepares an original synthetic leftover snapshot. `--check-cli` checks the actual built command and retained project state. `--install` enables a manual startup/Restore/Save As/log-export check; `--verify` checks those UI outputs. Live F36 GUI validation could not run because the computer-use service failed to start its native pipe, including after reset. The synthetic installed copy was archived to avoid a test startup prompt; no user projects were changed. Do not treat the headless/editor-model checks as a completed live UI check.

References: locally mirrored [RaceRender recovery startup description](https://racerender.com/RR3/docs/Q%26A.html#Splash) and [diagnostic-log troubleshooting guide](https://racerender.com/RR3/docs/Troubleshooting.html).
