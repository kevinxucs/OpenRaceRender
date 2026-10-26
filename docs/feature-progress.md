# Guide feature implementation progress

User authorization: implement F01/F05/F07 first, then all remaining guide gaps individually. Keep IDs from [guide-gap-review.md](guide-gap-review.md). Save a compact handoff before each next feature. The agent has no manual conversation-compaction API; durable checkpoints preserve the working context across automatic compaction.

## Current checkpoint

- F01: expanded structured RRP import implemented and validated; specialized effects and subfeatures assigned to later IDs remain explicit limitations.
- F05: expanded native/imported gauge designer implemented and validated.
- F07: text typography and shape design implemented and validated.
- Validation: 136 tests pass with the local library, release app builds/signs with 369 local resources, both synthetic media acceptance scripts pass, live design/edit/save checked. See [details and limits](import-designer-validation.md).
- F10/F12/F17/F18/F23: some shared model/rendering dependencies were added with import support. These IDs are not complete; their full user-facing workflows still require individual review.

Current feature: **F02 — full legacy project/template/style writing**, including files authored without original legacy bytes. Review the existing conservative patch writer and all three readers before selecting safe encodings; validate output by opening it in RaceRender. Do not count retaining original opaque data as implementing unsupported operations.

## Remaining queue

F02, F03, F04, F06, F08, F09, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31, F32, F33, F34, F35, F36.

Implement one feature at a time, inspect the relevant mirrored guide pages and existing code, validate the actual workflow, update this checkpoint and commit before starting the next. Network services/obscure formats need current primary documentation and realistic fixtures; record concrete limits rather than inventing support. Public source must not contain private sessions, telemetry or proprietary vendor assets. The local build may retain the user's explicitly authorized library bundle.

## F02 compact handoff — investigation in progress

- F01/F05/F07 commit `904f3f8` is pushed; its GitHub Actions run [40272854926](https://github.com/kevinxucs/OpenRaceRender/actions/runs/40272854926) passed. Workspace/root bounds follow-up has its own validation.
- No new legacy writer is exposed yet. The existing conservative copy exporter remains available.
- Private generated probes live in ignored `build/validation/legacy-writer`: `probe.py`, `probe.rrt`, `probe.rro`, `native-reference.rrt`, `hashes.py`, `native-hashes.py`. `probe.py` independently ports the existing symmetric codec and matches its key test vector. All probe project media/data/text are synthetic. Do not commit native library files or assets.
- RRP header fields at 4/8 are schema version dates (current RR3.7.3 saves 20191031/20161216), not arbitrary timestamps. With these fields, the generated `build/validation/designer/acceptance.rrp` opens in RaceRender with correct Video/RPM dial/Title and 3-second duration. Without them RR parses older record variants, even though the OpenRaceRender reader can read the synthetic file.
- Modern RRT2 exports have a one-byte workspace mode at 12, followed by 64,800 BGR preview bytes; seed/sizes start at 64813. Native export of the synthetic project is `native-reference.rrt` (header dates 20191031/20161216). Inputs are 136 bytes, object metadata 216 bytes after its separately encoded 128-byte name. Native objects are written in descending original index order; the reader sorts them.
- Each RRT object has a payload length plus eight bytes before the payload and eight more after nonempty payloads. Their integrity/marker semantics are unresolved. A probe with zeroed fields is readable here but rejected by RaceRender (`TemplateImportLoad` -83); an offset-broken probe produced -81. Do not call self-roundtrip proof of compatible export.
- Tried ordinary CRC32, Adler32, MD5, SHA1, FNV64 and Fletcher64 over raw/decoded metadata/payload without a match. This does not establish the algorithm. RRO has similar unexplained eight-byte records and needs actual native validation too.
- RaceRender is open on the disposable synthetic acceptance project, after exporting `native-reference.rrt`. OpenRaceRender is open on the disposable guide-features showcase with saved text outline/gradient diamond edits. No original user projects were modified. Restore CUA documentation after context compaction, then inspect fresh AX state.
- Resume by resolving template/style integrity records or implementing a verified RRP writer first. Preflight unsupported native HUD/effects rather than silently dropping them; preserve unknown imported data or reject changes that cannot be represented. F02 remains incomplete and other IDs remain queued.
