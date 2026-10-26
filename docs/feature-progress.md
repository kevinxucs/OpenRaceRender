# Guide feature implementation progress

User authorization: implement F01/F05/F07 first, then all remaining guide gaps individually. Keep IDs from [guide-gap-review.md](guide-gap-review.md). Save a compact handoff before each next feature. The agent has no manual conversation-compaction API; durable checkpoints preserve the working context across automatic compaction.

## Current checkpoint

- F01: expanded structured RRP import implemented and validated; specialized effects and subfeatures assigned to later IDs remain explicit limitations.
- F05: expanded native/imported gauge designer implemented and validated.
- F07: text typography and shape design implemented and validated.
- F02: rebuilt RRP3 projects and RRT2/RRO2 export implemented for representable settings, with compatibility checks; see [supported scope and native validation](legacy-export.md).
- Validation: 146 tests pass with the local library and graphics services; release app builds/signs with 369 local resources. All three synthetic media acceptance scripts pass. RaceRender loaded the authored RRP/RRT/RRO and applied written timeline events; the updated editor saved and reopened a UI-exported RRT. See [F02 details](legacy-export.md) and [initial batch validation](import-designer-validation.md).
- F10/F12/F17/F18/F23: some shared model/rendering dependencies were added with import support. These IDs are not complete; their full user-facing workflows still require individual review.

Next feature: **F03 — grouping and multi-selection**. F02 has a durable checkpoint below. The tool inventory has no manual context-compaction API; do not claim that saving this file itself compacts the conversation. Complete a context checkpoint before starting F03, and use automatic compaction when available.

## Remaining queue

F03, F04, F06, F08, F09, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31, F32, F33, F34, F35, F36.

Implement one feature at a time, inspect the relevant mirrored guide pages and existing code, validate the actual workflow, update this checkpoint and commit before starting the next. Network services/obscure formats need current primary documentation and realistic fixtures; record concrete limits rather than inventing support. Public source must not contain private sessions, telemetry or proprietary vendor assets. The local build may retain the user's explicitly authorized library bundle.

## F02 compact handoff — implementation validated

- Added `LegacyWriter.swift` (independent RRP3/RRT2/RRO2), CLI format-aware conversion, template/style format picker, and rebuilt-project export. The conservative `patchLegacy()` API remains for original opaque-copy use.
- Authored gauge background images also serialize into the shared legacy artwork container; multiple independent background layers are refused rather than dropping one.
- Added ten writer tests and `scripts/validate-legacy-writer.py`; all 146 tests pass with local library and graphics access. `build/validation/legacy-writer/{full-tests,build,acceptance,media,designer}.log` are the current validation logs. `docs/legacy-export.md` lists export support and explicit refusals, including native-only HUD widgets, unsupported design schemes, changed GPS finish lines, combined calculations and RCZ sources. No unsupported data is silently flattened.
- Native RR3 checks used only synthetic projects. The authored RRP opens with new displays and marks; RRT input roles map correctly; authored gauge RRO loads through Gauge Designer; timeline caption/position events apply at 1.25 seconds. The editor saved `acceptance/ui-export.rrt` and CLI reopened it. The user's Laguna RRP also exports successfully to ignored `build/validation/legacy-writer/laguna-copy.rrp`; the original is unchanged. That private real-session copy has not itself been opened in RaceRender.
- Template/style integrity resolved: fold `(byte XOR 0xAA)` additively into seed-initialized output buckets, then the existing wrapping key generator. Metadata seed = schema date + payload length, payload seed = schema date; no vendor code/assets are needed. Folds cover decoded metadata (216 bytes for template,84 style) and payload, excluding the separately encoded name.
- Corrected native-observed defaults: source tint disabled via alpha at picture43, not an all-zero record; source rotation is float20 with no tint-color flag. Gauge619 bits0x70 encode modes (0 needle,0x10 dual,0x30 graph);619 bit4 in value terms (mask4) is two decimals;633 mask24 encodes numbering (0 normal,8 x1000,16 x100,24 x10).627=191 selects major/minor Dash1 with explicit intervals. Split value/angle are648/656. Unused appended gradients696/700/704 and second alert708 need disabled alpha. Gauge618 selects type (0 generic,1 speed,2 tachometer). Common283 is not gauge mode.
- Type14 is embedded image, distinct from shape12. Exact bounded bitmap parsing now precedes recovery scanning in templates, including Unicode names. Unchanged imported data settings/opaque bytes survive rebuilds. Native first-clip joins normalize to virtual streams with role/clock preservation; virtual child delays now participate in placement, fixing trim + negative offset roundtrip.
- Private oracle files/disassembly/probes remain ignored under `build/validation/legacy-writer`. Do not commit them. The committed acceptance generator uses only original synthetic media/data.
- OpenRaceRender is on saved synthetic `acceptance/authored.orrp`, just successfully exported `ui-export.rrt`. RaceRender is on the synthetic timeline test, at1.25seconds with a saved custom camera rotation15; native inspector normalization may leave the window dirty. Its on-disk synthetic fixture was later regenerated by acceptance. Preserve current native state to a new private file if another project must be opened, rather than discarding it.
- Automatic approval review rejected choosing No at an unsaved RR prompt earlier. Resolved safely by choosing Yes and saving a new `designer/rrt-probe-state-20261026.rrp`; no outstanding approval request. Do not retry discarding unsaved state.
- CUA after compaction: call `await cua.rewriteDocumentation()` first. Native combo-box choices commit reliably with the dropdown button + arrow keys + Return; clicking list text alone can leave the value unchanged. File panels use Command+shift+g, set path, observe, double-click selected GoTo row, observe, click Open/Save.
