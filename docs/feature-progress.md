# Guide feature implementation progress

User authorization: implement F01/F05/F07 first, then all remaining guide gaps individually. Keep IDs from [guide-gap-review.md](guide-gap-review.md). Save a compact handoff before each next feature. The agent has no manual conversation-compaction API; durable checkpoints preserve the working context across automatic compaction.

## Current checkpoint

- F01: expanded structured RRP import implemented and validated; specialized effects and subfeatures assigned to later IDs remain explicit limitations.
- F05: expanded native/imported gauge designer implemented and validated.
- F07: text typography and shape design implemented and validated.
- Validation: 134 tests pass with the local library, release app builds/signs with 369 local resources, both synthetic media acceptance scripts pass, live design/edit/save checked. See [details and limits](import-designer-validation.md).
- F10/F12/F17/F18/F23: some shared model/rendering dependencies were added with import support. These IDs are not complete; their full user-facing workflows still require individual review.

Next feature: **F02 — full legacy project/template/style writing**, including files authored without original legacy bytes. Review the existing conservative patch writer and all three readers before selecting safe encodings; validate output by opening it in RaceRender. Do not count retaining original opaque data as implementing unsupported operations.

## Remaining queue

F02, F03, F04, F06, F08, F09, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31, F32, F33, F34, F35, F36.

Implement one feature at a time, inspect the relevant mirrored guide pages and existing code, validate the actual workflow, update this checkpoint and commit before starting the next. Network services/obscure formats need current primary documentation and realistic fixtures; record concrete limits rather than inventing support. Public source must not contain private sessions, telemetry or proprietary vendor assets. The local build may retain the user's explicitly authorized library bundle.
