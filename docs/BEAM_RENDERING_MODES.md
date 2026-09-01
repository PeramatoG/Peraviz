# Beam presentation experiment

Peraviz resolves GDTF/MVR and live DMX in the native runtime. The choices below consume the same resolved texture, color, dimmer, full beam angle, range, scale, index, and rotation state; they are presentation techniques and do not add GDTF capability support.

## Independent surface projection

Every mode assigns the cached, composed gobo texture to `SpotLight3D.light_projector`. Godot 4.7 produces black or stale projector results without shadows, so Peraviz enables shadows while a projector is active and restores the light's previous state when it is cleared. This path is independent of visible-beam presentation and remains the crisp reference for orientation and scale.

Godot 4.7 does not apply `light_projector` textures to volumetric fog. The native-shadow mode therefore retains the projector for surfaces and separately uses a physical mask for fog.

## Presentation modes

### Fog Volume Gobo (Experimental)

One cone `FogVolume` follows each relevant emitter along renderer-child local `-Z`. Its shader projects every froxel sample back toward the aperture before sampling the composed mask, so openings form coherent shafts rather than a texture wrapped around a cone. Open slots use a continuous circular field. Rotation, scale, color, and intensity are parameter updates and do not rebuild topology.

The shader deliberately uses emission with zero contributed density. This is a predictable presentation approximation, not physically authoritative light scattering; it avoids density from overlapping fixture volumes changing how unrelated lights scatter. It consequently does not react to scene shadows. Peraviz enables volumetric processing for this presentation and starts with a conservative `0.0015` environment density while retaining its 64 by 64 froxel settings.

### Vector Gobo Prism (Reference)

The existing cached vectorized prism remains the reference and fallback. It represents the seated mask as geometry and therefore has gobo-dependent primitive counts. Parametric indexed rotation continues to reuse topology. Surface projection still uses the independent projector path.

### Native Fog + Shadow Gobo (Experimental)

This mode uses no visible custom beam mesh. It enables environment volumetric fog and places a small alpha-scissored, shadows-only quad at the aperture. Open texels transmit the real spotlight; closed texels cast a shadow into fog. The light projector remains responsible for the crisp surface image. Stable-engine froxel and shadow resolution can make the fog pattern soft or unstable at distance.

## Coordinates and lifecycle

Renderer children emit along local `-Z`, corresponding to mapped emitter-local `-Y` and official GDTF Beam source-local `-Z`. The Godot cone volume is rotated from its local `+Z` direction to this renderer contract. See [Coordinate system and transform validation](COORDINATE_SYSTEM.md).

Mode changes remove resources owned by the previous backend before applying held authoritative state. Fog volumes, meshes, materials, and mask planes are reused within a mode; dimmer, color, scale, and rotation are parameter-only updates.

## Initial structural comparison

The deterministic comparison below describes resource scaling before GPU-dependent profiling. Expensive benchmark capture is opt-in; use the Godot profiler/Peraviz diagnostics at 1, 16, 64, and 128 active emitters for machine-specific CPU/GPU frame time and draw-call results.

| Mode | Custom nodes at 1 / 16 / 64 / 128 emitters | Gobo-dependent primitives | Shadow-enabled lights with active gobos | Topology rebuild on rotation |
| --- | --- | --- | --- | --- |
| Fog Volume | 1 / 16 / 64 / 128 FogVolumes | None | 1 / 16 / 64 / 128 (surface projector requirement) | No |
| Vector Prism | 1 / 16 / 64 / 128 meshes | Yes, cached per mask | 1 / 16 / 64 / 128 | No |
| Native Shadow | 1 / 16 / 64 / 128 mask quads | Constant two triangles per active gobo | 1 / 16 / 64 / 128 | No |

Peraviz diagnostics expose mesh rebuilds, parametric updates, texture compositions, and shader/material writes. RenderingServer profiler counters provide draw calls, primitives, CPU frame time, and GPU frame time where supported. Fog Volume currently looks most promising for topology stability and coherent shafts; retain all modes until visual quality and 128-emitter GPU measurements are collected on representative hardware.

## Current limitations

- Surface projector correctness depends on real-time shadows in stable Godot 4.7.
- Projector textures do not shape stable Godot volumetric fog.
- Custom Fog Volume emission does not provide physical occlusion.
- Native shadow masks are limited by froxel and shadow-map resolution.
- Focus, Frost, Iris, prism, and shutter semantics remain limited exactly as documented in the [GDTF support matrix](gdtf-support-matrix.md).
