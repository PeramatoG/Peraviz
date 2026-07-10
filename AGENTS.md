# AGENTS.md

## Scope

These rules apply to the whole repository. Direct user instructions for the current task take precedence.

## Core architecture rules

1. Treat Peraviz as a low-latency visualizer fed by a native data pipeline.
2. Keep expensive fixture processing, protocol handling, GDTF/MVR interpretation, DMX resolution, interpolation, dirty-state generation, and render-data preparation in native C++ whenever practical.
3. Keep Godot focused on presentation, interaction, scene resources, renderer-facing updates, and UI.
4. Do not move protocol-level or GDTF semantic interpretation into Godot unless the task explicitly approves it and the reason is documented.
5. Keep structural setup and live playback updates as separate contracts.
6. Prefer batched, versioned, schema-driven data transfer with stable numeric IDs and packed payloads.
7. Minimize per-frame `Array`, `Dictionary`, `String`, `Variant`, allocation, and scene-tree churn.
8. Native worker threads must not directly mutate Godot scene nodes.
9. Reuse meshes, materials, textures, shaders, RIDs, and nodes during live playback.
10. Do not reintroduce the removed fixed visual-frame row or obsolete visual-frame buffer path.

## Current runtime facts

1. The active live path uses a native sectioned visual frame with descriptors, integer payloads, and float payloads.
2. Dimmer, Pan, and Tilt use parser-owned selected-mode GDTF `ChannelFunction` data compiled into `CompiledRuntimeScene` and evaluated by the native visual runtime.
3. Dimmer state is property/target-oriented; repeated Dimmer render targets must not collapse into one fixture-level scalar or manifest slot.
4. Godot owns setup-time renderer target records through `NativeRendererTargetRegistry` and live renderer mutation, including Lightweight Prism beam resources and optional realtime spotlight state.
5. Legacy fixture bindings may still exist for inspection or unsupported compatibility domains, but they must not be a Dimmer/Pan/Tilt live fallback.
6. Transitional Godot-side gobo metadata and compatibility paths still exist.

Do not document or test unsupported native attributes as implemented.

## GDTF-first policy

1. GDTF specification correctness is the first architectural priority for fixture semantics.
2. Unknown or unsupported GDTF behavior must be preserved and reported, not guessed or silently ignored.
3. Repeated GDTF families must be represented with IDs and collections rather than fixed one-off fields.
4. Changes to GDTF parsing, canonical attributes, semantic interpretation, or serialization-neutral models must remain compatible with Perastage unless the user explicitly approves a divergence.
5. New GDTF capability work must update relevant support documentation and regression tests.

## Refactoring modes

### Normal refactoring mode

Use normal mode unless the user explicitly requests architectural replacement, legacy removal, breaking migration, or irreversible pipeline replacement.

In normal mode:

- Preserve supported public behavior.
- Keep changes small and focused.
- Refactor around touched code paths only.
- Avoid keeping two authoritative states for the same responsibility.

### Approved architectural replacement mode

When explicitly requested:

- The requested replacement architecture is authoritative for the affected subsystem.
- Obsolete internal APIs may be broken, renamed, or removed.
- Legacy implementation paths should be deleted from the active build rather than retained as fallbacks.
- Temporary bridges require a clear owner, expiration condition, deletion guardrail, and no new feature development.
- Public file formats, protocols, supported workflows, and documented project data remain compatible unless explicitly changed.

## Code and documentation rules

1. Keep responsibility boundaries clear between project data, UI, runtime logic, file parsing/writing, and rendering.
2. Avoid growing hotspot files; consider extraction when touched files approach 1000-1200 LOC and prioritize extraction near 1200-1500 LOC.
3. Keep explicit source ownership in build files; do not add broad recursive source registration unless already required and documented.
4. Add a concise English comment above every new or substantially changed C++ function definition.
5. Keep new or updated code comments, developer documentation, and commit-facing notes in English.
6. Do not wrap imports in try/catch blocks.
7. Keep generated, cache, and build artifacts out of source control.
8. Update `docs/release-notes-draft.md` for meaningful user-facing or internal changes.
9. If architecture, performance strategy, C++/Godot data flow, renderer behavior, fixture behavior, import/export behavior, or visible UI behavior changes, update the relevant documentation in the same task.
10. Do not describe target architecture as active until the production path uses it and tests cover it.

## Checks before closing changes

Run relevant checks that exist in the repository. For most changes, start with:

- `tests/check_no_large_files.sh`
- `tests/check_runtime_architecture.sh`
- Native tests relevant to the touched subsystem.
- Godot headless tests relevant to touched GDScript behavior.
- `git diff --check`

If a check cannot run in the current environment, record the exact command and reason.
