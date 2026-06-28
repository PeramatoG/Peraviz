# Batched beam rendering plan

Peraviz currently updates fixture emitters through individual Godot nodes, lights, materials, gobo projectors, and beam renderer instances. That keeps the renderer flexible, but live DMX shows with many moving heads can become CPU-bound from per-emitter node and material updates.

The next renderer step should be an opt-in `BatchedBeamRenderer` that coexists with the current legacy and volumetric renderers. This document defines the intended first implementation boundary without changing current renderer behavior.

## Key observation: shared fixture geometry

Fixtures of the same type normally share the same imported model geometry. Peraviz should use that to avoid duplicating static beam proxy data per fixture:

- Group instances by fixture type and beam profile instead of by fixture UUID.
- Reuse one mesh and material setup for every emitter whose fixture type, lens profile, and beam/gobo topology are compatible.
- Keep per-instance data limited to transform, color, intensity, cone length, cone angle, visibility, and optional gobo selection state.
- Treat topology changes, such as a different gobo prism shape, as a reason to move the emitter to another batch rather than rebuilding every fixture of that type.

A practical batch key can start with:

```text
fixture_type_id | emitter_index | beam_shape_mode | gobo_topology_key | material_profile_key
```

The exact key should be resolved from runtime fixture metadata and existing beam parameters, not from MVR/GDTF file mutation.

## First implementation boundary

1. Add a disabled-by-default renderer mode that implements `BeamRendererBase` and owns one or more `MultiMeshInstance3D` nodes.
2. Keep the existing `SpotLight3D` nodes, gobo projector, legacy renderer, and volumetric renderer unchanged.
3. Build a stable emitter-to-instance map from `SpotLight3D.get_instance_id()` to a batch key and MultiMesh instance index.
4. Update only per-instance transforms and custom data for normal DMX frames.
5. Rebuild or reassign an instance only when its batch key changes.
6. Keep all debug counters and hot-path metrics comparable with the existing renderers.

## Suggested data ownership

- `BatchedBeamRenderer`: owns batch maps, `MultiMeshInstance3D` nodes, shared meshes, and shared materials.
- Existing fixture/light apply code: continues producing beam parameter dictionaries.
- Existing gobo projector: remains responsible for gobo texture/projection state until the batched renderer has an equivalent GPU-side representation.
- Scene loading and import code: stay unchanged; imported fixture geometry remains source data and is not mutated.

## Per-instance data target

The first shader/MultiMesh path should fit within Godot's per-instance transform plus custom data constraints:

- Transform: emitter position and direction.
- Instance color: beam RGB and normalized visible intensity.
- Custom data: beam angle, beam range, softness/falloff profile index, and optional gobo/topology index.

If one `MultiMeshInstance3D` cannot carry enough data cleanly, split batches by material/profile so each instance only needs dynamic state.

## Migration checklist for the next PR

1. Add the renderer script and register it behind an advanced/debug render mode.
2. Populate batches from warmed emitter lights without changing scene import or fixture binding behavior.
3. Support dimmer-only and pan/tilt-only updates first, because those should be pure per-instance buffer updates.
4. Fall back to the current renderer for unsupported gobo/topology cases.
5. Compare hot-path metrics for node updates versus batched buffer updates on a rig with many fixtures of the same type.

## Compatibility notes

- The existing beam renderer interface should remain the boundary for fixture runtime code.
- The first prototype should avoid changing MVR or GDTF import behavior.
- Debug overlays and technical monitor counters should continue to work with both batched and existing renderers.
- Current legacy and volumetric modes must remain the default until the batched path is visually validated.
