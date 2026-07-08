# Peraviz architecture

## Purpose

This document defines the stable target architecture for Peraviz.

It describes module ownership, runtime data flow, C++ and Godot responsibilities, structural installation, live updates, threading, rendering boundaries, diagnostics, and completion criteria.

It does not describe temporary migration checkpoints as if they were final architecture. Current implementation status, legacy paths, and remaining migration work must be documented separately in the relevant runtime or migration documents.

## Architectural goal

Peraviz is a low-latency real-time lighting visualizer built around:

- A native C++ parsing, compilation, simulation, and runtime data pipeline.
- A Godot rendering and client layer.
- A narrow, versioned, schema-driven boundary between both layers.
- Stable identifiers for fixtures, components, geometry, resources, and render targets.
- Structural installation performed only when scene topology changes.
- Dirty render deltas transferred during live playback.
- Shared serialization-neutral GDTF semantics compatible with Perastage.

The architecture must minimize latency between incoming control data and the rendered result without duplicating authoritative state across C++ and Godot.

## Core principle

C++ prepares what Godot needs to render.

Godot applies prepared structural data and render-ready live updates.

Godot must not become a second GDTF parser, DMX resolver, fixture-state engine, or protocol-processing layer.

## Rule precedence

Architecture and refactoring rules are defined in `AGENTS.md`.

When a task is explicitly declared as an architectural replacement, legacy removal, or breaking internal migration:

- The target architecture in this document is authoritative for the affected subsystem.
- Obsolete internal APIs may be removed.
- Legacy runtime paths should not remain active as fallback.
- Public file-format and protocol compatibility remains required unless explicitly changed by the user.
- Git history is the reference for removed internal code.

## High-level system model

Peraviz separates three major phases:

```text
Import and compilation
    -> structural installation
    -> live runtime updates
```

These phases have different ownership, data lifetime, and performance requirements.

## Import and compilation flow

```text
MVR and GDTF input
    -> native archive and file access
    -> project-owned MVR parser
    -> project-owned GDTF parser
    -> validation and diagnostics
    -> serialization-neutral semantic models
    -> compiled fixture types
    -> selected DMX modes
    -> compiled channel programs
    -> structural scene and component description
```

This phase may perform heavier work because it runs during scene loading, fixture compilation, patch changes, mode changes, or structural rebuilds.

It must not be repeated for every DMX frame.

## Structural installation flow

```text
Compiled scene and fixture data
    -> stable fixture and component IDs
    -> geometry and render-target registry
    -> resource references and hashes
    -> immutable schema
    -> Godot scene and renderer installation
```

Structural installation occurs after:

- MVR load.
- GDTF load or recompilation.
- Fixture-type change.
- Selected DMX mode change.
- Patch change.
- Geometry topology change.
- Component topology change.
- Renderer-target registration change.
- Static resource topology change.
- Protocol or schema-generation change.

Godot may create Nodes, RIDs, materials, textures, shaders, meshes, and other renderer-facing resources during this phase.

Godot must cache the resulting render targets and avoid rediscovering them during live playback.

## Live runtime flow

```text
Art-Net, sACN, or DMX input
    -> native packet receiver
    -> universe filter
    -> relevant-address filter
    -> fixture-instance lookup
    -> compiled DMX program evaluation
    -> ModeMaster and relation evaluation
    -> physical-state calculation
    -> interpolation and smoothing
    -> render-state cooking
    -> dirty-state generation
    -> typed packed deltas
    -> Godot bridge
    -> domain-specific render appliers
    -> cached Nodes, RIDs, materials, textures, and shaders
    -> renderer and GPU
```

The live path must not perform:

- XML parsing.
- MVR parsing.
- GDTF semantic parsing.
- Attribute-name interpretation.
- ChannelFunction or ChannelSet lookup by string.
- Scene-tree discovery.
- Resource recreation when a parameter update is sufficient.
- Per-fixture Dictionary reconstruction.
- Duplicate simulation in Godot.
- CPU-heavy gobo generation every frame.

## Native C++ ownership

The native layer owns all high-frequency semantic and simulation work.

### Native responsibilities

- Art-Net, sACN, and DMX packet receiving.
- Packet validation.
- Universe filtering.
- Ignoring unused universes.
- Relevant-address filtering.
- Fixture patch lookup.
- MVR-derived scene data required by the runtime.
- GDTF archive access.
- GDTF parsing and validation.
- Canonical attribute resolution.
- Geometry and geometry-reference resolution.
- DMX mode compilation.
- Logical channel compilation.
- ChannelFunction and ChannelSet compilation.
- ModeMaster handling.
- Relation handling.
- Physical-range mapping.
- DMX profile handling where supported.
- Color-space, emitter, filter, gamut, and wheel semantics where supported.
- Interpolation and smoothing.
- Pan and tilt resolution.
- Intensity and visibility resolution.
- Color calculation.
- Beam and optical calculation.
- Gobo and prism state resolution.
- Shutter and strobe state resolution.
- Dirty-state generation.
- Render-ready value preparation.
- Versioned schema creation.
- Typed packed delta assembly.
- Diagnostics and profiling counters.
- CPU-side resource preparation when practical.

### Native design rules

- Prefer data-oriented and cache-friendly layouts for hot paths.
- Avoid per-channel and per-fixture heap allocation during live playback.
- Avoid string parsing and Dictionary lookup after structural compilation.
- Use stable numeric IDs for fixture instances, fixture types, components, geometry, emitters, wheels, wheel slots, resources, and render targets.
- Represent repeated GDTF families with collections and IDs.
- Do not collapse repeated families into one fixed field per fixture.
- Keep parser and compiled-model data serialization-neutral.
- Do not introduce Godot Nodes, RIDs, materials, textures, or renderer-specific objects into shared GDTF semantic models.
- Keep locks short.
- Never hold native locks while calling into Godot or renderer-facing APIs.
- Prefer immutable snapshots, double buffering, lock-free queues, or short protected swaps for cross-thread handoff.

## Godot ownership

Godot owns scene presentation and renderer-facing behavior.

### Godot responsibilities

- Scene presentation.
- Camera and viewport behavior.
- User interaction.
- UI.
- Diagnostics presentation.
- Renderer configuration.
- Mesh creation and assignment.
- Material creation and assignment.
- Shader creation and parameter updates.
- Beam rendering.
- Atmosphere and post-processing.
- Renderer-facing texture creation and updates.
- RID creation and updates.
- Installation of structural scene data.
- Registration of render targets.
- Application of prepared typed live deltas.
- Renderer-specific visual approximations after native semantic resolution.

### Godot design rules

- Do not parse Art-Net, sACN, DMX, GDTF, or MVR semantics during live playback.
- Do not decode coarse, fine, or ultra-fine DMX channels.
- Do not evaluate ChannelFunctions, ChannelSets, ModeMaster rules, or relations.
- Do not assign semantic meaning to GDTF attribute names.
- Avoid high-frequency `get_node()` calls.
- Avoid per-frame scene-tree searches.
- Avoid per-frame Node creation and deletion.
- Avoid per-frame material duplication.
- Avoid per-frame texture recreation.
- Cache Node, RID, material, shader, mesh, and texture references during structural installation.
- Apply updates in batches.
- Skip unchanged data.
- Use domain-specific appliers.
- Do not reconstruct a universal fixture-state Dictionary.
- Do not maintain a second authoritative fixture-state engine.
- Prefer shared meshes, shared materials, `MultiMeshInstance3D`, RenderingServer APIs, packed buffers, and shader-side parameters when appropriate.

## Serialization-neutral GDTF model

The GDTF semantic and compiled models must remain independent from:

- Godot renderer types.
- Godot Nodes.
- Godot RIDs.
- Peraviz-specific renderer caches.
- Perastage editor commands.
- Perastage undo and redo state.
- Archive-writing logic.
- UI-only data structures.

The shared semantic contract with Perastage concerns meaning and deterministic compiled data, not shared renderer or editor implementation.

The compiled model must support:

- Stable identities.
- Repeated families.
- Unknown and custom attributes.
- Invalid references.
- Unsupported official attributes.
- Approximation diagnostics.
- Source provenance.
- Deterministic contract output.

## Component model

A component is a compiled semantic runtime entity associated with one or more geometry or render targets.

Examples include:

- Geometry transform components.
- Emitters.
- Beam optical components.
- Color emitters or filters.
- Gobo wheels.
- Animation wheels.
- Color wheels.
- Prism systems.
- Shapers.
- Media displays.
- Lasers.
- Environment outputs.
- Generic visual parameters.

The architecture must not assume that each fixture has exactly:

- One pan.
- One tilt.
- One emitter.
- One beam.
- One gobo wheel.
- One prism.
- One color system.

Each repeated family must use IDs and collections.

## Stable identifiers

Stable identifiers are required for:

- Fixture types.
- Fixture instances.
- Selected DMX modes.
- Geometry instances.
- Components.
- Emitters.
- Wheels.
- Wheel slots.
- Prisms.
- Shapers.
- Media layers.
- Resources.
- Render targets.
- Schema generations.

IDs must be assigned during parsing, compilation, scene construction, or structural registration.

Do not derive component or render-target IDs from collision-prone formulas such as arbitrary fixture-ID multiplication.

IDs must remain stable for the lifetime of the installed structural schema.

## C++ and Godot boundary

The boundary must remain narrow, explicit, versioned, schema-driven, and batch-oriented.

It is divided into:

- Structural installation.
- Live delta transfer.
- Diagnostics.

## Structural contract

The structural contract may contain:

- Protocol version.
- Schema generation.
- Fixture-type IDs.
- Fixture-instance IDs.
- Selected mode IDs.
- Component IDs.
- Geometry IDs.
- Emitter IDs.
- Wheel IDs.
- Wheel-slot IDs.
- Resource IDs or hashes.
- Render-target IDs.
- Static transforms.
- Component-to-target mappings.
- Resource-to-target mappings.
- Static capability metadata required by renderers.
- Diagnostic references.

Godot installs this contract and builds its renderer-facing registry.

The structural contract must not be rebuilt every frame.

## Live delta contract

The live contract contains only changed render domains.

It may contain:

- Geometry transforms.
- Emitter intensity.
- Visibility.
- Light energy.
- Beam intensity.
- Material emission energy.
- Linear RGB color.
- Beam angles.
- Edge softness.
- Zoom.
- Iris.
- Frost.
- Focus.
- Wheel selection.
- Wheel-slot selection.
- Resource selection.
- Wheel index angle.
- Wheel rotation speed.
- Wheel rotation direction.
- Shake frequency.
- Shake amplitude.
- Prism selection.
- Prism movement.
- Shaper values.
- Shutter and strobe output.
- Media parameters.
- Laser parameters.
- Generic prepared visual parameters.

The live contract must not require Godot to perform:

- DMX decoding.
- Physical-range calculation.
- GDTF semantic lookup.
- String-based attribute resolution.
- ModeMaster evaluation.
- Relation evaluation.
- Wheel-slot selection from raw channel values.

## Packed data rules

Use integer storage for:

- Protocol versions.
- Schema generations.
- Section types.
- IDs.
- Indexes.
- Masks.
- Counts.
- Flags.
- Strides.
- Offsets.
- Modes.
- Resource references.

Use float storage for:

- Physical values.
- Render-ready scalar values.
- Linear colors.
- Angles.
- Energies.
- Intensities.
- Speeds.
- Frequencies.
- Amplitudes.
- Shader parameters.

Do not encode integer identities as floats.

## Boundary API shape

Preferred API shapes include:

```text
install_compiled_scene(structural_snapshot)
install_render_registry(render_registry)
submit_universe_frame(universe_id, frame)
consume_render_deltas()
get_runtime_schema()
get_diagnostics_snapshot()
```

Avoid final production APIs shaped like:

```text
set_fixture_bindings(Array<Dictionary>)
set_fixture_channel(fixture_id, channel, value)
set_pan(fixture_id, value)
set_tilt(fixture_id, value)
set_color_r(fixture_id, value)
set_color_g(fixture_id, value)
set_color_b(fixture_id, value)
```

The avoided style creates excessive marshaling, encourages magic channel mappings, duplicates semantic logic, and makes the legacy binding path authoritative.

## Domain-specific application

Godot must apply live data by domain.

Examples:

- Geometry transform applier.
- Emitter intensity applier.
- Emitter color applier.
- Beam optics applier.
- Wheel selection applier.
- Wheel motion applier.
- Prism applier.
- Shaper applier.
- Temporal output applier.
- Media display applier.
- Laser applier.
- Generic visual parameter applier.

One domain must not reset unrelated domains using missing or default values.

A color update must not reset intensity.

A wheel update must not reset beam energy.

A transform update must not trigger full fixture lighting reconstruction.

## Gobo and image-resource architecture

C++ should own, when practical:

- GDTF resource lookup.
- Archive extraction.
- Image decoding.
- SVG parsing or rasterization.
- Normalization.
- Alpha-mask generation.
- Hashing.
- CPU-side cache lookup.
- SDF generation where justified.
- Atlas planning.
- Multi-wheel composition planning.
- Wheel and slot semantic resolution.
- Prepared motion parameters.

Godot should own:

- Final `Image` and `ImageTexture` creation.
- Texture updates.
- Renderer-facing material creation.
- Shader assignment.
- RID creation.
- Shader parameter updates.
- Renderer-specific filtering and sampling.

Do not regenerate gobo images every frame for:

- Rotation.
- Index angle.
- Continuous rotation.
- Direction.
- Shake.
- Offset.

These should normally be shader or renderer parameters.

A texture or resource reference should change only when slot selection, resource topology, or composition changes.

## Threading model

### Native threads

Native worker threads may perform:

- Packet receiving.
- Packet decoding.
- Universe filtering.
- DMX evaluation.
- State resolution.
- Dirty-state generation.
- CPU-side resource decoding.
- CPU-side image preparation.
- Snapshot or delta assembly.

Native workers must not directly mutate:

- Godot Nodes.
- Godot Resources.
- Godot RIDs.
- Materials.
- Textures.
- RendererServer objects.

### Handoff

Use:

- Immutable snapshots.
- Double buffering.
- Lock-free queues.
- Short mutex-protected swaps.
- Frame coalescing.
- Latest-wins semantics where appropriate.

Do not hold a lock while calling into Godot.

## Rendering and instancing

Peraviz should reuse renderer resources aggressively.

Prefer:

- Shared meshes.
- Shared materials.
- Shared textures.
- Shared shaders.
- Cached RIDs.
- `MultiMeshInstance3D`.
- `RenderingServer.multimesh_set_buffer()`.
- Packed instance buffers.
- Shader-side parameter changes.
- Preallocated update buffers.

Avoid:

- One unique material per fixture when not required.
- One unique texture per fixture when not required.
- Recompiling shaders during live playback.
- Recreating meshes during live playback.
- Reallocating textures for parametric movement.
- Thousands of independent high-frequency GDScript property calls when a batch path is possible.

GPU compute or custom rendering paths should be introduced only after profiling demonstrates a clear benefit.

## Dirty-state model

The runtime must detect changes by semantic render domain.

Examples:

- Transform dirty.
- Intensity dirty.
- Color dirty.
- Optics dirty.
- Wheel selection dirty.
- Wheel motion dirty.
- Prism dirty.
- Temporal output dirty.
- Material dirty.
- Resource topology dirty.

Structural changes and live parametric changes must be distinguished.

Examples:

- Selecting a different gobo resource is structural or resource-topology work.
- Rotating the selected gobo is a live parametric update.
- Creating a new beam renderer is structural work.
- Changing beam intensity is a live parametric update.

Dirty-state generation belongs in native C++.

## Diagnostics

Diagnostics must be available without becoming part of the authoritative live path.

Maintain counters for at least:

- Packet receive time.
- Packet queue depth.
- Packets dropped.
- Packets coalesced.
- Universes received.
- Universes ignored.
- Relevant channel bytes evaluated.
- Fixture-program evaluation time.
- ModeMaster and relation evaluation time.
- Physical-state resolution time.
- Dirty component count.
- Structural rebuild time.
- Delta assembly time.
- C++ and Godot transfer time.
- Godot apply time.
- Resource update time.
- Render frame time.

Diagnostics should also report:

- Invalid GDTF references.
- Unsupported official attributes.
- Unknown custom attributes.
- Approximation decisions.
- Missing resources.
- Schema mismatches.
- Protocol mismatches.
- Stale render targets.
- Failed structural installations.

Diagnostic Dictionaries and strings may be used outside the hot path.

## Error handling

Invalid or unsupported data must not be silently guessed.

The system should:

- Preserve unknown or custom data where possible.
- Emit deterministic diagnostics.
- Reject incompatible schema versions.
- Reject stale schema generations.
- Skip invalid rows safely.
- Avoid out-of-bounds buffer access.
- Keep the previous valid renderer state when a malformed update is rejected.
- Distinguish unsupported behavior from invalid data.
- Distinguish approximation from exact support.

## Testing architecture

Tests must verify the intended production path.

The minimum required GDTF-first vertical test is:

```text
Real GDTF input
    -> project-owned parser
    -> serialization-neutral compiled fixture type
    -> selected DMX mode
    -> structural scene and component registry
    -> compiled Dimmer, Pan, and Tilt programs
    -> DMX frame
    -> native physical and render-state resolution
    -> typed dirty delta
    -> direct Godot render-domain application
```

This test must not depend on manually constructed magic channel-type bindings.

Additional tests should cover:

- Schema version rejection.
- Schema-generation rejection.
- Invalid section offsets.
- Invalid row strides.
- Unknown attributes.
- Unsupported attributes.
- Repeated wheels.
- Repeated emitters.
- Repeated geometry components.
- Unused universe rejection.
- Irrelevant channel-change filtering.
- Unchanged-frame suppression.
- Dirty-domain isolation.
- Structural and live update separation.
- Missing resources.
- Legacy API absence after migration.
- Peraviz and Perastage semantic contract consistency.

## Migration constraints

A migration is not complete when:

- New compiled types exist but the production path still uses legacy bindings.
- Godot still creates the authoritative fixture channel map.
- Magic channel-type numbers remain in the final path.
- The old runtime remains registered as fallback.
- Both C++ and Godot maintain authoritative fixture state.
- A universal per-fixture Dictionary remains the live state model.
- Fixed single-instance gobo, prism, or emitter fields remain the only representation.
- Guard scripts pass only because they inspect the wrong directory.
- Tests validate only manually constructed legacy inputs.
- Documentation describes target behavior as active without an end-to-end proof.

Temporary bridges are allowed only when explicitly documented and governed by the rules in `AGENTS.md`.

## Performance principles

- Correct ownership comes before micro-optimization.
- Avoid duplicate work before optimizing individual functions.
- Filter unused universes early.
- Filter irrelevant channel changes early.
- Coalesce incoming frames where latest-wins behavior is correct.
- Precompute patch and program lookup tables.
- Preallocate hot-path buffers.
- Reuse renderer resources.
- Avoid per-frame strings and Dictionaries.
- Avoid scene-tree traversal during live playback.
- Measure receive, decode, resolve, transfer, apply, and render phases separately.
- Do not assume that rendering is the bottleneck when camera movement remains smooth.

## Documentation ownership

Update this document when changing:

- Native and Godot responsibility boundaries.
- Structural installation flow.
- Live runtime flow.
- Boundary protocol shape.
- Stable ID ownership.
- Threading model.
- Resource preparation ownership.
- Renderer application ownership.
- Dirty-state model.
- Completion criteria for the target architecture.

Do not add temporary implementation checkpoints to this document as permanent architecture.

Use these documents for more specific details:

- `docs/gdtf-runtime-architecture.md`
- `docs/dmx-visual-runtime.md`
- `docs/gdtf-support-matrix.md`
- `docs/peraviz-perastage-gdtf-contract.md`
- `docs/godot_performance_guidelines.md`
- `peraviz_tree.md`

## Final architectural invariants

The following conditions must remain true:

1. C++ owns GDTF semantics and DMX resolution.
2. Godot owns rendering and presentation.
3. Structural installation and live updates are separate contracts.
4. The boundary is narrow, versioned, schema-driven, typed, and batched.
5. Stable IDs are assigned during compilation or structural registration.
6. Repeated GDTF families use collections and IDs.
7. Godot does not reconstruct fixture semantics during live playback.
8. Native threads do not mutate Godot renderer objects directly.
9. Dirty-state generation occurs in native C++.
10. Renderer targets are cached during structural installation.
11. Legacy internal compatibility does not override an approved architectural replacement.
12. Public format and protocol compatibility remains protected.
13. Unknown and unsupported behavior is diagnosed rather than guessed.
14. Tests exercise the real production path.
15. Documentation distinguishes target architecture from current implementation status.
