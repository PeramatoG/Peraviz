# AGENTS.md (global)

## Objective
Keep Peraviz clean, modular, and suitable for real-time visualization. Peraviz must behave like a low-latency visualizer: heavy fixture, DMX/Art-Net/sACN, interpolation, state-resolution, and scene-update calculations should live in the native C++ side whenever possible, while Godot should receive prepared rendering data and focus on graphics.

## Mandatory global rules

1. **Real-time architecture first**
   - Treat Peraviz as a real-time client renderer fed by a native simulation/data pipeline.
   - Keep expensive work out of Godot scripts and scene-tree callbacks.
   - Godot should not repeatedly parse, resolve, or recompute fixture state when C++ can provide a precomputed frame snapshot.
   - Prefer batched updates, stable identifiers, dirty flags, and frame-coalesced state transfer over per-fixture/per-channel chatter.

2. **C++ owns heavy data processing**
   - C++ should own Art-Net/sACN/DMX packet handling, universe filtering, fixture patch lookup, GDTF/MVR-derived fixture model data, attribute resolution, interpolation/smoothing, pan/tilt/color/dimmer/strobe/prism state preparation, and any high-frequency state diffing.
   - Godot should receive compact, already-resolved data such as transforms, beam parameters, material/color data, visibility/intensity values, and mesh/instance update buffers.
   - Avoid moving raw DMX or protocol-level concepts into Godot unless there is a measured reason and it is documented.

3. **Godot is the rendering/client layer**
   - Keep Godot responsibilities focused on scene presentation, cameras, user interaction, materials, meshes, beams, atmosphere, and renderer configuration.
   - Avoid large GDScript managers that duplicate native-side logic.
   - Avoid high-frequency `Node` creation/deletion during live playback. Reuse nodes/resources and update existing visual instances.
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
   - Keep platform-specific native code isolated behind small interfaces.
   - Keep generated/cache/build artifacts out of source control.

8. **C++/Godot boundary policy**
   - Use one narrow integration layer between C++ and Godot. Do not scatter protocol parsing or fixture-resolution calls across many scripts.
   - Prefer batch APIs such as `apply_frame_snapshot(...)`, `apply_fixture_updates(...)`, or explicit buffer uploads over thousands of small calls.
   - Minimize allocation and Variant/object churn at frame rate.
   - Document any new cross-boundary data structure in `docs/architecture.md` or a nearby protocol/boundary document.

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
   - Keep README links aligned with current documentation entry points whenever those entry points change.
   - Minor internal refactors, formatting-only changes, and invisible build maintenance do not require user documentation updates unless they change project structure or developer workflow.

14. **Mandatory checks before closing changes**
   - Run and keep green, when available:
     - `tests/check_peraviz_tree_modules.sh`
     - `tests/check_no_large_files.sh`
     - `tests/check_godot_boundary_lightweight.sh`
   - If a new architectural boundary is introduced, add or update a small `tests/check_*.sh` script in the same PR.
   - If a check cannot run on the current platform, document why in the PR notes and run the closest available equivalent.

15. **Refactoring strategy**
   - Refactor incrementally around touched code paths.
   - Avoid big-bang rewrites unless the user explicitly requests a large architectural refactor.
   - When replacing a slow path, keep behavior equivalent first, then optimize further with measurements.

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

- Keep changes small, focused, and explicit in responsibility naming.
- Prefer data-oriented, cache-friendly structures for high-frequency native paths.
- Prefer immutable or double-buffered frame snapshots for cross-thread handoff.
- Before introducing cross-module coupling, add an interface/helper in the module that owns the responsibility.
- If a performance compromise is necessary, document the reason and the intended follow-up.
