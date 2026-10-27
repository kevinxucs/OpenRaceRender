# Groups and multiple selection (F03)

Command-click display rows to toggle selection; Shift-click selects a contiguous range. On the composition, Command/Shift-click toggles widgets, and dragging empty space selects a rectangle. The background camera does not intercept the rectangle; select cameras from the list or with Option-click. Normal clicks select the outer group. Option-click selects a member for individual editing.

Use **Display → Group selected displays** (Command-G) or **Ungroup selected groups** (Command-Shift-G). Select siblings at the same hierarchy level when grouping. Selecting one existing group with other siblings adds them to that group; selecting multiple groups creates an enclosing group. Group and member rows remain individually accessible, with indentation showing membership.

Drag the combined selection box to move, or its upper-right handle to resize. The inspector supports combined numeric geometry, and alignment and Option-arrow pixel nudges operate on the whole selection. A drag is one undo operation. Duplicate, delete and layer ordering operate on selected subtrees. Group templates retain their children, including nested groups, and each application assigns fresh identities so repeated imports cannot cross-wire parents.

Group geometry edits preserve child timeline events. A base edit transforms the base and explicit future geometry; an edit at a timeline segment adds member overrides at that instant, retaining later independent overrides. Native projects retain the pre-edit member event so removing a newly authored group event restores a member event that previously occupied the same time. Imported RaceRender group events lack that extra history; removing one removes the matching member events, as a group operation. Undo restores the complete prior project.

Visibility, opacity and active time gates apply to descendants in overlay drawing, camera compositing, snapshots, audio and asset validation. Ungrouping bakes the removed group gates into released members. RaceRender export bakes group state into member records while keeping the hierarchy. Existing restrictions on legacy template/style timeline export still apply; use `.orrt` for templates containing events.

## Reference behavior and validation

The supplied guide's `Main.html` and `HowTo-ComplexGauge.html` describe group movement, resizing and adding displays to an existing group. RaceRender 3.7.3 Ultimate was also used with an original synthetic project:

- Grouped a caption and an ellipse. Child coordinates remained canvas percentages. A newly created group stored an unrelated placeholder rectangle, while its inspector showed the actual union of child bounds.
- Moving and horizontally resizing the group wrote transformed coordinates into each child. A later group event at 1.25 seconds wrote matching geometry events into the children as well as the group. Applying a second parent transform during rendering would therefore be incorrect.
- OpenRaceRender follows those absolute-coordinate records and computes selection bounds from descendants. It preserves existing member events when creating a group; the native application's documented grouping operation discards those events.

Private reference saves remain under ignored `build/validation/legacy-writer/acceptance/native-group*.rrp`. No native files, assets or executable extracts are needed by this feature.

The full suite passes **160 tests** with the authorized local library and graphics services. Fourteen new tests cover hierarchy identity, nested groups, legacy placeholder geometry, repeated template application, native and legacy round trips, event restoration, subtree operations, visibility/opacity baking and selection editing. The editor tests include real AppKit mouse events through `PreviewView` for marquee selection over a background camera, group dragging, one-step undo and Option-click member selection.

`scripts/validate-grouping.py` creates original three-second camera/audio media. It verifies exact native/RRP snapshot pixels at visible, hidden and resumed positions after normalizing the RRP workspace size. The actual encoded video is black and silent during the hidden interval and resumes both streams afterward. This exposed a pre-existing audio automation issue: discrete AVAudioMix volume points could interpolate across a hidden interval. Ordinary audio now uses the same sample-accurate processing gate as routed audio.

The updated editor's Display menu was inspected live. A subsequent file-picker run encountered repeated accessibility automation timeouts; process samples showed an idle main thread rather than a render or hierarchy loop. Full live inspector/save validation remains limited by that automation connection. Automated editor/view tests and file/render acceptance pass. Diagnostic samples and logs are ignored under `build/validation/grouping`.
