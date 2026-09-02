# Beam presentation experiment

Peraviz resolves GDTF/MVR and live DMX in the native runtime. The modes below consume the same resolved texture, color, dimmer, beam angle, range, index, and rotation state. They are Peraviz presentation choices and do not add or reinterpret GDTF semantics.

## Independent surface projection

An active native gobo selection assigns the cached composed texture to `SpotLight3D.light_projector` in every mode. Godot 4.7 requires shadows for reliable projector output, so Peraviz enables them while a projector is present and restores the prior policy when it is cleared. The projector light rolls around the beam axis by the authoritative physical gobo angle; the Vector Prism child receives the inverse parent-roll compensation, preserving its recovered topology and orientation.

The shadows-only aperture mask is a separate resource. It exists only for an active gobo in Shared Haze + Gobo Shadow and shapes volumetric light through real shadows. It is not the crisp surface-projector path.

## Presentation modes

### Vector Prism

This is the recovered reference renderer. Its cached vectorized prism represents the gobo silhouette as geometry, with gobo-dependent primitive counts. Indexed and continuous rotation remain parametric and reuse topology. The shared haze is hidden and real fixture SpotLights are used only by active surface projectors.

### Shared Haze

One scene-owned box `FogVolume` represents atmospheric haze. It is auto-sized from the loaded scene bounds with a 5 m margin and reused across mode switches. A standard neutral `FogMaterial` starts at density `0.015`, near-white albedo, and zero emission. Active real SpotLights illuminate this common medium; there are no emitter-owned FogVolumes and no physical gobo masks. The independent surface projector remains active for gobo footprints.

### Shared Haze + Gobo Shadow

This reuses the same shared haze and active real SpotLights. Each active gobo output additionally owns one reusable alpha-scissored, shadows-only aperture mask. Open beams have no mask and do not enable shadows unless another independent requirement exists. The mask and crisp projector use the same authoritative texture and physical rotation.

Godot 4.7 does not apply `light_projector` textures directly to volumetric fog. Shadow maps and the fixed froxel grid can make the volumetric gobo softer than the surface footprint, particularly at distance.

## Shared haze and range

The presets keep global Environment fog density at zero; the local shared FogVolume supplies density. Both haze modes enable Environment volumetric fog and use a 110 m fog length. The longer range helps overview cameras see fixtures whose beams commonly reach about 75 m, but distributes the fixed froxel depth over more distance and reduces detail. Froxel resolution remains unchanged.

The shared volume is updated when loaded scene bounds or haze settings change, not for emitter DMX updates. The historical per-emitter FogVolume implementation remains internal for reference but is not selected by any user-facing mode or preset.

## Ownership and diagnostics

Presentation ownership is explicit:

- Vector Prism owns only the vector shaft.
- Shared haze owns one scene-level FogVolume.
- A main realtime SpotLight contributes to haze only when its authoritative physical output is active and the selected haze mode requires it.
- Surface projection owns the crisp projector and its Godot 4.7 shadow dependency.
- The physical mask belongs only to Shared Haze + Gobo Shadow.

`[peraviz-presentation]` reports native target/output/emitter ownership, authoritative active outputs and emitters, cached fixture lights, vector resources, the shared haze, emitter FogVolumes, surface projectors, masks, realtime SpotLights, and shadowed SpotLights. Counts use stable target/emitter identities rather than per-frame SceneTree scans. They distinguish roughly 95 native Dimmer target records from the larger set of physical emitter anchors produced by multi-emitter fixture geometries; the trace shows whether those anchors are unique and authoritatively active rather than assuming either count is a leak.

## Current limitations

- Surface projector correctness depends on real-time shadows in stable Godot 4.7.
- Projector textures do not shape stable Godot volumetric fog.
- Native gobo shadows are limited by froxel and shadow-map resolution.
- A scene with many genuinely active physical emitters can still make native volumetric lighting expensive; future aggregation or culling is outside this experiment.
- The broader live-DMX output/apply CPU bottleneck is separate work and is not solved by changing beam presentation.
- Focus, Frost, Iris, prism, and shutter semantics remain limited exactly as documented in the [GDTF support matrix](gdtf-support-matrix.md).

## Windows validation checklist

1. Load the canonical scene without Art-Net and confirm no fixture output resource is active and no missing-metadata errors appear.
2. Start Art-Net and select Vector Prism. Confirm open beams and vector gobo shafts are unchanged, and an asymmetric surface footprint rotates coherently with the prism.
3. Select Shared Haze without changing DMX. Confirm exactly one shared haze, zero emitter FogVolumes, active open shafts in haze, and a crisp gobo surface footprint.
4. Select Shared Haze + Gobo Shadow. Confirm the same haze is reused, active gobo outputs have masks, open outputs do not, and volumetric light reacts to the mask as Godot's resolution permits.
5. Switch Vector, Shared Haze, Shared Haze + Gobo Shadow, and Vector without a new DMX event; confirm no stale white footprint or missing gobo.
6. Capture diagnostics and at least ten settled `--peraviz-perf-trace` lines in each haze mode.
