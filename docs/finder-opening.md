# Opening projects from Finder

## Failure and fix

The previous app could launch into an empty session when using Finder's **Open With → OpenRaceRender**. This was reproduced both with the application stopped and with an empty editor already running. Finder selected the expected app bundle; the RRP itself parsed correctly.

The app handled only `application(_:openFiles:)`. macOS can instead send `application(_:open:)` with file URLs; Apple's [delegate documentation](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)) explains that this callback takes precedence over the filename methods. The previous handler also discarded startup requests if the editor model had not yet attached to its window. Apple documents that [file-open delivery can occur before launch finishes](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:openFile:)).

Both callbacks now use one route. Early requests retain their URL until the editor attaches. Command-line launch paths are processed once, and an incoming Finder request takes priority over startup arguments. macOS option values such as `YES` are not interpreted as project paths. File URLs are passed directly, preserving spaces and Unicode; non-file URLs are ignored.

The app uses a single editor window, consistent with its one shared project model. A first routing prototype using an external-event WindowGroup produced two windows in the live check; the final build uses the AppKit URL callback and one Window scene. Duplicate requests during a load are coalesced. A newer project open or New Session cancels the older task, and stale results cannot replace the newer session or clear its loading state. Existing unsaved-change checks remain on the project-open path.

## Verification

Four new editor tests exercise actual project parsing through the delegate/model path:

- A synthetic RRP URL arrives before the window attaches, then loads with its display, source settings and output marks. Finder delivery takes priority over an older command-line path.
- A running editor receives filename and URL callbacks; duplicate requests keep the original in-flight load.
- A newer open and New Session prevent older asynchronous results from replacing their state.
- Launch arguments run once; spaces, Unicode and uppercase RRP extensions work, while macOS option values and non-file URLs are ignored.

All 88 tests passed locally with graphics services and the optional local library available: 80 core tests and 8 editor tests.

In the final single-window app, a real Finder cold launch loaded the supplied RRP with 18 displays, 2 available inputs, 129,609 telemetry samples, and output marks 03:03.783–23:21.375. The live check did not write the original RRP. The final command-line inspection independently confirmed its inputs and display/sample counts. Running-app delivery is covered by the callback regression test; the attempted live repeat check was interrupted before a conclusive observation.

The file association is left to macOS and the user. **Open With** can select OpenRaceRender without changing RaceRender's default association. This change affects file delivery and loading, not legacy-format feature coverage; see the [feature audit](racerender-feature-audit.md).
