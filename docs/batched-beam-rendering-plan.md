# Batched beam rendering plan

Peraviz currently updates fixture emitters through individual Godot nodes, lights, materials, gobo projectors, and beam renderer instances. That keeps the renderer flexible, but live DMX shows with many moving heads can become CPU-bound from per-emitter node and material updates.

A safe next step is a `BatchedBeamRenderer` that coexists with the current legacy and volumetric renderers instead of replacing them immediately.

## Incremental approach

1. Add an opt-in renderer mode that owns one or a small number of `MultiMeshInstance3D` nodes for simple beam proxy geometry.
2. Keep a stable mapping from fixture UUID, emitter index, or `SpotLight3D` instance ID to a MultiMesh instance index.
3. Update per-instance transforms, color, intensity, cone angle, length, and visibility from the existing beam parameter dictionary.
4. Move shared haze, softness, falloff, and debug controls into shader uniforms or compact per-instance custom data.
5. Keep gobo projection, legacy cones, and volumetric modes available until the batched path has feature parity for common live DMX shows.
6. Use the hot-path telemetry counters to compare per-frame node updates against batched buffer updates before making the new renderer the default.

## Compatibility notes

- The existing beam renderer interface should remain the boundary for fixture runtime code.
- The first prototype should avoid changing MVR or GDTF import behavior.
- Debug overlays and technical monitor counters should continue to work with both batched and existing renderers.
