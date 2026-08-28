# Repository guidance

## Scope

These rules apply to the entire repository. Direct task instructions take precedence.

## Architecture

- Treat Peraviz as a low-latency visualizer fed by a native data pipeline.
- Keep protocol handling, MVR/GDTF interpretation, DMX resolution, interpolation, dirty-state generation, and render-data preparation in native C++ whenever practical.
- Keep Godot focused on presentation, interaction, scene resources, renderer-facing mutation, and UI. Native worker threads must not mutate Godot scene nodes.
- Keep structural setup separate from live playback. Prefer versioned, sectioned, batched contracts with stable numeric IDs and packed payloads.
- Avoid per-frame `Array`, `Dictionary`, `String`, `Variant`, allocation, and scene-tree churn. Reuse renderer resources and nodes.
- Do not restore the removed fixed visual-frame row or obsolete visual-frame buffer path.
- Use [docs/architecture.md](docs/architecture.md) as the active runtime source of truth. Do not duplicate its implementation detail here.

## GDTF policy

- GDTF specification correctness takes priority for fixture semantics. Preserve and report unknown or unsupported behavior rather than guessing or silently ignoring it.
- Model repeated GDTF families as identified collections, not fixed one-off fields.
- Keep parser and serialization-neutral semantic changes compatible with Perastage unless a task explicitly approves divergence.
- Extend the compiled native runtime for new live semantics; do not make legacy Dictionary-driven Godot resolution authoritative.
- Update [docs/gdtf-support-matrix.md](docs/gdtf-support-matrix.md), focused documentation, and regression tests when capability coverage changes. Do not claim unsupported attributes.

## Change discipline

- Preserve supported public behavior unless architectural replacement or a breaking migration is explicitly approved.
- Keep ownership boundaries clear among project data, UI, runtime logic, parsing/writing, and rendering.
- Keep changes focused and avoid parallel authoritative states. Temporary bridges require an owner, an expiration condition, and a deletion guardrail.
- Consider extraction as touched files approach 1,000–1,200 lines; prioritize extraction near 1,200–1,500 lines.
- Keep explicit source ownership in build files. Do not introduce broad recursive registration without a documented reason.
- Add a concise English comment above each new or substantially changed C++ function definition.
- Write comments, developer documentation, and commit-facing notes in English. Do not wrap imports in `try`/`catch` blocks.
- Keep generated, cache, and build artifacts out of source control.
- Update `docs/release-notes-draft.md` for meaningful user-facing or internal changes and keep it release-ready.

## Validation

Run checks relevant to the change. The normal baseline is:

- `tests/check_no_large_files.sh`
- `tests/check_runtime_architecture.sh`
- native CTest tests for the touched subsystem
- headless Godot tests for touched GDScript behavior
- `git diff --check`

Record the exact command and reason when the environment prevents a check.
