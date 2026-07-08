# AGENTS.md (global)

## Objective

Keep Peraviz clean, modular, scalable, and suitable for real-time visualization.

Peraviz must behave like a low-latency visualizer. Heavy fixture processing, GDTF and MVR interpretation, DMX, Art-Net and sACN handling, interpolation, state resolution, dirty-state generation, and render-data preparation should live in native C++ whenever practical. Godot should receive prepared rendering data and focus on graphics, scene presentation, interaction, and renderer-facing resource updates.

## Rule precedence

The following precedence applies when instructions appear to conflict:

1. Explicit instructions from the user for the current task.
2. Active architectural replacement rules in this file.
3. GDTF-first runtime priorities.
4. Mandatory global rules.
5. General preferences for small, incremental, compatibility-preserving changes.

An explicit request for a large structural refactor, architectural replacement, legacy removal, or breaking internal migration overrides the normal preference for incremental refactoring and internal behavior preservation within the affected subsystem.

Compatibility with public file formats, external protocols, supported user workflows, and documented project data remains required unless the user explicitly changes that requirement.

Compatibility with obsolete internal APIs, temporary bridges, legacy runtime structures, and superseded implementation details is not required during an approved architectural replacement.

## Mandatory global rules

1. **Real-time architecture first**
   - Treat Peraviz as a real-time client renderer fed by a native simulation/data pipeline.
   - Keep expensive work out of Godot scripts and scene-tree callbacks.
   - Godot should not repeatedly parse, resolve, or recompute fixture state when C++ can provide a precomputed frame snapshot.
   - Prefer batched updates, stable identifiers, dirty flags, and frame-coalesced state transfer over per-fixture/per-channel chatter.

2. **C++ owns heavy data processing**
   - C++ owns Art-Net, sACN and DMX packet handling, universe filtering, fixture patch lookup, GDTF and MVR-derived fixture model data, attribute resolution, physical-value calculation, interpolation, smoothing, dirty-state generation, and high-frequency state diffing.
   - C++ should prepare final or near-final render values such as transforms, linear color, light energy, beam intensity, beam angles, edge softness, visibility, material emission, wheel selection, slot selection, rotation, speed, shake, prism state, and temporal output.
   - Godot should not receive raw DMX, ChannelFunction data, ChannelSet data, ModeMaster rules, attribute names, protocol-level bindings, or physical-range calculations in the live rendering path.
   - Avoid moving protocol-level or GDTF semantic concepts into Godot unless there is a measured and documented reason approved by the user.

3. **Godot is the rendering/client layer**
   - Keep Godot responsibilities focused on scene presentation, cameras, user interaction, materials, meshes, beams, atmosphere, post-processing, and renderer configuration.
   - Godot may create or update renderer-owned resources from data prepared by C++, but it must not duplicate native GDTF or DMX interpretation.
   - Avoid large GDScript managers that duplicate native-side logic.
   - Avoid high-frequency `Node` creation/deletion during live playback. Reuse nodes, RIDs, textures, meshes, materials, shaders, and visual instances.
   - Do not traverse the scene tree at frame rate to rediscover render targets that can be registered and cached during structural setup.
   - When many identical meshes are visible, evaluate `MultiMeshInstance3D`, `RenderingServer`, shared meshes/materials, GPU-friendly buffers, and shader-side work before adding thousands of individual `MeshInstance3D` updates.

4. **Measure before and after optimization**
   - Any performance-oriented change must include a short note with the measured bottleneck, the change made, and the before/after result when practical.
   - Use Godot profiler, manual timing, OS/native profilers, and GPU profiling where relevant.
   - Do not assume the bottleneck is rendering if camera movement is smooth with the same scene load. Investigate data processing, state transfer, allocations, synchronization, and scene-tree updates.

5. **Modularity before growing large files**
   - Avoid adding large logic blocks to hotspot files.
   - If a change introduces a new responsibility, create or use adjacent files organized by responsibility.
   - Prefer small services with clear ownership over broad manager classes.

6. **File-size guardrail (soft limit)**
   - When touching a file near **1000-1200 LOC**, look for extraction opportunities before adding major behavior.
   - When touching a file near **1200-1500 LOC**, prioritize extraction before adding feature logic.
   - If extraction is not feasible in the same PR, include a short technical note in the PR description with the next recommended split.

7. **Architecture and build conventions**
   - Keep explicit source ownership in CMake or build files. Do not use broad recursive source registration for project source files unless the repository already requires it and the reason is documented.
   - Respect module boundaries described in `docs/architecture.md`, `docs/godot_performance_guidelines.md`, and `peraviz_tree.md`.
   - If those documents do not match the real repository, correct them before relying on them as architectural authority.
   - Keep platform-specific native code isolated behind small interfaces.
   - Keep generated/cache/build artifacts out of source control.
   - Removed legacy code remains available in Git history and does not need to stay compiled as reference material.

8. **C++/Godot boundary policy**
   - Use one narrow and explicit integration layer between C++ and Godot. Do not scatter protocol parsing, fixture resolution, or structural compilation calls across unrelated scripts.
   - Keep structural installation and live updates as separate contracts.
   - Structural installation may transfer stable fixture, component, geometry, emitter, wheel, slot, resource, and render-target IDs after loading or rebuilding the scene.
   - Live updates must transfer only prepared dirty changes such as transforms, intensity, visibility, linear color, optical parameters, wheel selection, wheel motion, shutter, strobe, and material or shader parameters.
   - Prefer versioned, schema-driven, batch-oriented APIs and packed integer/float buffers over `Array<Dictionary>` and per-fixture Dictionaries.
   - IDs, indexes, masks, counts, flags, offsets, strides, and protocol metadata must remain integer data.
   - Physical and render-ready scalar values may use packed float storage.
   - Minimize allocation and Variant, Dictionary, Array, String, and temporary object churn at frame rate.
   - Transitional bridges must have a documented deletion condition and must not become the primary runtime path.
   - Document any active cross-boundary data structure in `docs/architecture.md` or a nearby protocol/boundary document.

9. **Threading and synchronization policy**
   - Native receiving/processing threads must not directly mutate Godot scene nodes.
   - Use lock-free queues, double buffering, or short mutex-protected swaps for frame snapshots.
   - Create worker threads during initialization/loading rather than just-in-time during live playback.
   - Keep locks short and avoid holding locks while calling into Godot or GPU-facing APIs.

10. **GPU and instancing policy**
   - Reuse meshes, materials, textures, and shader resources aggressively.
   - For repeated identical or near-identical fixture parts, prefer shared resources and instance data instead of duplicated geometry.
   - Consider `MultiMeshInstance3D` or `RenderingServer.multimesh_set_buffer()` for large batches of similar elements.
   - Keep per-frame material duplication and shader recompilation out of the live path.

11. **Mandatory function comments**
   - Add a concise one- or two-line English comment above every new or substantially changed function definition.
   - The comment must explain the function's responsibility, not restate the function name.
   - Keep comments accurate when refactoring.

12. **Language policy for contributions**
   - All new or updated code, comments, commit-facing notes, and developer documentation must be written in English.
   - User-facing Spanish/English strings are allowed only where the UI or documentation explicitly requires localization.

13. **Documentation sync policy**
   - Any change that affects architecture, performance strategy, C++/Godot data flow, supported protocols, import/export behavior, renderer behavior, fixture behavior, or visible UI behavior must update documentation under `docs/` in the same task.
   - Documentation must distinguish clearly between target architecture, currently active implementation, explicitly legacy code, and remaining migration work.
   - Do not describe a target architecture as active until an end-to-end test proves that the production path uses it.
   - Keep README links aligned with current documentation entry points whenever those entry points change.
   - Minor internal refactors, formatting-only changes, and invisible build maintenance do not require user documentation updates unless they change project structure or developer workflow.

14. **Mandatory checks before closing changes**
   - Run and keep green, when available:
     - `tests/check_peraviz_tree_modules.sh`
     - `tests/check_no_large_files.sh`
     - `tests/check_godot_boundary_lightweight.sh`
     - Any runtime architecture guardrail relevant to the changed subsystem.
     - Native unit and integration tests relevant to the changed pipeline.
   - Architectural checks must inspect the real repository paths.
   - A missing expected source directory must fail the check instead of silently passing.
   - Guardrails must validate active dependencies and API relationships, not only banned names.
   - Tests must exercise the intended production path rather than manually constructing obsolete internal inputs.
   - If a new architectural boundary is introduced, add or update a small `tests/check_*.sh` script in the same PR.
   - If a check cannot run on the current platform, document why in the PR notes and run the closest meaningful equivalent.
   - Do not declare a migration complete while its primary end-to-end path is untested.

15. **Refactoring strategy**
   - Use normal refactoring mode unless the user explicitly requests a structural replacement.
   - In normal refactoring mode, refactor incrementally around touched code paths, preserve supported public behavior, and prefer small focused changes.
   - Activate architectural replacement mode when the user explicitly requests a large architectural refactor, structural replacement, legacy removal, breaking internal migration, or irreversible pipeline change.
   - In architectural replacement mode, the requested architecture is authoritative for the affected subsystem.
   - Internal APIs may be broken, renamed, or removed.
   - Legacy implementation paths must be deleted from the active build rather than wrapped, adapted, retained as fallback, or kept for reference.
   - Git history is the reference for removed code.
   - Temporary bridges are prohibited unless the user explicitly requests one or they are strictly required to keep the application buildable during a documented multi-step migration.
   - Any temporary bridge must have one owner, a clear expiration condition, a deletion guardrail, and no new feature development.
   - Do not preserve old behavior first when that behavior depends on the architecture being replaced.
   - Prefer one complete vertical slice through the new architecture over broad partial compatibility.
   - A migration is not complete if the new types exist but the production path still feeds them through legacy bindings, Dictionaries, magic channel codes, duplicate state caches, or old appliers.
   - A migration is not complete if the old runtime remains registered, callable, compiled, or selected as an automatic fallback.
   - Large deletions and coordinated multi-file changes are allowed when necessary to establish the requested architecture.
   - Keep the scope limited to the affected subsystem, but do not artificially reduce it in a way that leaves two competing architectures active.

16. **Debug and profiling hooks**
   - Keep debug/profiling UI and logging centralized behind feature flags or a small diagnostics module.
   - Debug instrumentation must not add significant overhead in Release builds.
   - Prefer structured frame timing counters for receive, decode, resolve, transfer, apply, and render phases.

## Current likely hotspots to watch

These are expected hotspots for Peraviz and must be confirmed against the current code before large changes:

- Native protocol receivers and packet queues.
- Universe filtering and fixture patch lookup.
- Fixture state resolution and interpolation.
- C++ to Godot bridge / GDExtension boundary.
- Godot scripts that iterate over all fixtures every frame.
- Scene-tree updates for pan/tilt, beam, dimmer, color, strobe, prism, and gobo state.
- Mesh/material duplication for identical fixture models.
- Per-frame allocations, string parsing, dictionary lookups, and Variant conversions.

## Change quality

- Keep responsibility names explicit.
- Prefer small and focused changes in normal refactoring mode.
- In architectural replacement mode, prefer a complete coherent replacement over an artificially small diff that leaves duplicate active pipelines.
- Prefer data-oriented, cache-friendly structures for high-frequency native paths.
- Prefer immutable or double-buffered frame snapshots for cross-thread handoff.
- Before introducing cross-module coupling, add an interface or helper in the module that owns the responsibility.
- Delete obsolete ownership paths instead of adding another synchronization layer.
- Do not duplicate the same authoritative state in C++ and Godot.
- Do not keep two active pipelines for the same responsibility unless the user explicitly requests staged coexistence.
- If a performance or compatibility compromise is necessary, document the exact reason, affected path, and deletion or follow-up condition.


## GDTF-first runtime priorities

1. GDTF specification correctness is the first architectural priority.
2. Native C++ owns GDTF parsing, validation, compilation, DMX resolution, physical-state calculation, relation handling, ModeMaster evaluation, diagnostics, dirty-state generation, and render-data preparation.
3. Godot owns rendering and presentation, not GDTF semantic interpretation.
4. The live C++/Godot boundary is versioned, schema-driven, packed, batched, and free of per-fixture Dictionaries.
5. Structural setup and live updates use separate contracts.
6. Repeated GDTF families must be represented with stable IDs and collections, never one fixed member per fixture.
7. Gobo wheels, animation wheels, color wheels, prisms, emitters, filters, shapers, media layers, lasers, and numbered attributes must support multiple instances where the GDTF data permits them.
8. Unknown, custom, invalid, or unsupported GDTF behavior must be preserved in diagnostics and never silently guessed or discarded.
9. The runtime must consume parser-owned and compiler-owned fixture programs directly. Godot-created channel bindings, magic channel-type numbers, or manually reconstructed semantic programs are not an acceptable final path.
10. Component IDs and render-target IDs must be assigned by structural compilation or scene registration. Do not derive them from arbitrary fixture ID multiplication or other collision-prone formulas.
11. Any new GDTF capability must update the support matrix, semantic contract data, and regression tests.
12. Changes to GDTF parsing, semantic interpretation, validation, canonical attribute handling, or serialization-neutral model types must be reviewed for compatibility with Perastage. A Peraviz-only interpretation is not acceptable.
13. Perastage compatibility means shared semantic meaning and deterministic contract data. It does not require sharing Godot renderer types, Peraviz runtime caches, editor commands, undo/redo systems, or archive-writing logic.
14. The first mandatory end-to-end runtime vertical slice is:
    - Real GDTF input.
    - Project-owned parser.
    - Serialization-neutral compiled fixture type.
    - Scene and component registry.
    - Compiled DMX program.
    - Native physical and render-value resolution.
    - Typed dirty delta.
    - Direct Godot render-domain application.
15. Dimmer, pan, and tilt must pass through this vertical slice before adding further compatibility layers or advanced gobo behavior.
