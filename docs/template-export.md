# Subset template export (F04)

Choose **File → Save layout as template…** or **Save template…** in the widget palette. The export sheet starts with non-video/audio displays selected. Use the per-display checkboxes or **All**, **Widgets only**, **Current selection**, and **None** to choose a reusable mini-template. A group checkbox selects/deselects its entire branch; refine it with individual member checkboxes.

Edit the template's object names beside the checkboxes. The input column highlights the roles used by the chosen displays, including timeline source switches. Roles start with generic names such as “Video 1” and “Data 1”; rename them to descriptions such as “Front camera” and “Vehicle sensors”. Those names appear in the input mapping controls when the template is loaded. Unused inputs are excluded. Empty names fall back to their original names.

Selection and names belong to the export draft. They do not rename the session's objects or inputs, change the canvas selection, dirty the project or create undo entries. Cancel and reopen to reset the draft. An empty selection disables saving.

## Groups, files and portability

Selecting a member retains its necessary parent group containers, including their visibility, opacity and timeline state. Other children of those groups remain excluded. The count includes these structural containers. A group's checkbox is fully checked only when every member is selected; the explanatory text describes retained parents for partial selections. Canvas coordinates and object order are preserved.

**Save this display as a reusable style…** starts with the current selection, including multiple objects or selected groups' descendants. A single independent display can use `.rro`; multiple displays and selections requiring group containers use `.rrt` when RaceRender format is selected. Native `.orrt` supports both. Whole templates default to the library's `Templates` folder; independent single styles default to `Styles`.

Artwork is embedded, including image/gauge backgrounds in saved group-event history. Session media paths, synchronization, data configuration, export marks and export state are removed. Template application remaps identities and input assignments, including group-event undo history. Group geometry remains in canvas coordinates.

RaceRender formats retain the existing compatibility checks: up to eight template input roles, supported display/settings representations, and no template timeline events or display time bounds. Use `.orrt` for animated templates. Unsupported settings are reported before opening the save panel; see [legacy export](legacy-export.md).

## Reference and verification

The local [RaceRender Create Template guide](https://racerender.com/RR3/docs/TemplateCreate.html) documents per-object checkboxes and editable object/input template names. Hands-on checking of installed RaceRender 3.7.3 used the saved synthetic `native-group` project: **File → Export Layout as Template…** showed both editable tables; unchecking Video also unchecked its associated input role. Cancelling closed the draft without saving a template or editing the project.

Nine new automated tests cover disjoint widget subsets, nested ancestor retention without siblings, inherited activation/opacity, legacy-index parents, renamed `.orrt`/`.rrt` round trips and explicit two-logger mapping, saved group-event source roles, identity remapping and event restoration, editor draft isolation/reset, group checkbox refinement, multiple selected styles and accurate RRO/RRT selection. The full suite contains 169 tests; local optional-library and graphics checks are enabled for validation.


The updated app was also exercised through its real export sheet. A synthetic project with a camera, two data sources and grouped instruments saved a renamed two-widget subset plus its required group and one renamed role. The saved JSON was checked for exact names, selected objects and empty media paths, converted to `.rrt`, and reopened in the editor; all three imported objects appeared beside the untouched originals. The import result was saved separately. Live validation also caught a Command-A conflict with text editing; the Display command now delegates to the focused text editor, with regression coverage. The existing Open-file import automatically maps roles; explicit two-logger mapping is verified by the roundtrip test, while the library browser already labels mapping pickers with template input names.
