# Beam presentation and footprint backends

Peraviz resolves GDTF/MVR and live DMX in the native runtime. The modes below consume the same resolved texture, color, dimmer, beam angle, range, index, and rotation state. They are Peraviz presentation choices and do not add or reinterpret GDTF semantics.

## Production defaults and lens emission

New sessions, new MVR imports and Reset use Vector Gobo Prism (serialized ID 1),
Custom footprints on Forward+ opaque receivers, 0.6 surface gain, 0.10 softness,
and 0.5 m Wash intersection. The existing adjustable intersection applies only to
open Wash/Fresnel/PC shafts; Spot and selected gobo artwork remain sharp.
Realtime surface lights stay off.

The normal Quick Preset list contains the Custom production preset. Advanced
controls retain a clearly labeled Native gobo-only diagnostic/reference backend.
Shared Haze (0), Shared Haze + Gobo Shadow (2) and Shader Beam Proxy (3) remain
implemented for restoration/tests. A restored selection is displayed as active
but disabled for new selection. Internal sessions can expose these IDs with
`PERAVIZ_DIAGNOSTIC_RENDERERS=1`; no serialized IDs are reassigned.

PVZ restoration preserves every explicit value, including zero intersection,
zero lens gain and diagnostic renderer IDs. Missing values use production defaults,
including Custom footprints and 0.5 m intersection. Older archives without those
keys therefore adopt the new defaults; there is no historical-default inference.
Restoration starts from defaults, avoiding leakage from the previously open document.

**Lens Emission Intensity** defaults to 1.0 (the existing canonical native emission
energy, typically up to 4 before per-output optical scaling). It is independent
of Beam/Shaft and Footprint/Surface gains. All three are presentation multipliers:
GDTF values, native physical state and DMX output remain unchanged. Native Color,
Dimmer and color blackout drive each physical lens even behind grouped shafts.
The gain replays displayed material/instance energy during hold and pending native
work, including recovery from zero, without retiring workers or rebuilding resources.
No SpotLight/OmniLight, mandatory glow, flare or tone-mapping change is introduced.

Verified GDTF Beam models bind their own visual meshes, even with generic mesh
names. Other geometry owners, fixture housing, missing-model placeholders and
runtime optical meshes are excluded. Conservative lens/glass name hints remain
for legacy setup without verified model ownership. Prepared BaseMaterial3D copies
retain textures, UVs and geometry; unknown shaders/passes keep authored materials.
Shared Control Group materials and compatible GPU lens batches remain supported,
with native exact per-output fallback and material restoration on retirement.

## Independent surface projection

With `footprint_backend="native"`, an active gobo selection assigns the cached composed texture to `SpotLight3D.light_projector`. With `footprint_backend="custom"`, a bounded GPU volume samples the original cached image instead, without a native projector. Godot 4.7 requires shadows for reliable projector output, so Peraviz enables them while a projector is present and restores the prior policy when it is cleared. Projector roll is composed into the saved local optical basis around local `-Z`; it does not rewrite Euler angles, the emitter origin, or the beam direction. The Vector Prism child receives an explicit inverse presentation roll around its documented longitudinal axis, preserving its recovered topology and centerline.

The shadows-only aperture mask is a separate native-reference resource. It exists only for an active gobo in Shared Haze + Gobo Shadow and shapes volumetric light through real shadows. It is not the crisp surface-projector path.

## Presentation modes

### Vector Prism

This is the production renderer. Its cached vectorized prism represents the gobo silhouette as geometry, with gobo-dependent primitive counts. Indexed and continuous rotation remain parametric and reuse topology. The shared haze is hidden and surface projection selects the independent Custom or Native backend. Custom is the new-session default and requires no realtime surface light. See [surface ownership](surface-light-ownership.md) for legacy migration and limitations.

### Shared Haze

One scene-owned box `FogVolume` represents atmospheric haze. It is auto-sized from the loaded scene bounds with a 5 m margin and reused across mode switches. A standard neutral `FogMaterial` starts at density `0.015`, near-white albedo, and zero emission. Active real SpotLights illuminate this common medium; there are no emitter-owned FogVolumes and no physical gobo masks. The independent surface projector remains active for gobo footprints.

### Shared Haze + Gobo Shadow

This reuses the same shared haze and active real SpotLights. Each active gobo output additionally owns one reusable alpha-scissored, shadows-only aperture mask. Open beams have no mask and do not enable shadows unless another independent requirement exists. The mask and crisp projector use the same authoritative texture and physical rotation.

Godot 4.7 does not apply `light_projector` textures directly to volumetric fog. Shadow maps and the fixed froxel grid can make the volumetric gobo softer than the surface footprint, particularly at distance.

### Shader Beam Proxy

This experimental Peraviz presentation is inspired by established real-time DMX-previsualization architecture, but is not an Unreal Engine dependency and is not part of GDTF or MVR. It uses one shared normalized low-poly stack of frustum slices and a per-instance additive shader. Length, aperture, angle, color, intensity, composed gobo texture, scale, and rotation are uniforms or instance transforms; gobo motion never vectorizes or rebuilds topology.

The proxy selects a bounded 4, 8, or 12 slice tier: wide beams use fewer visible slices and narrow beams use more. A Forward+ scene-depth texture softly clips fragments behind the closest opaque surface. Transparent-depth ordering and unusual camera projections can still expose clipping artifacts, so this remains an experimental approximation rather than physical volumetric scattering.

## Shared haze and range

The presets keep global Environment fog density at zero; the local shared FogVolume supplies density. Both haze modes enable Environment volumetric fog and use a 110 m fog length. The longer range helps overview cameras see fixtures whose beams commonly reach about 75 m, but distributes the fixed froxel depth over more distance and reduces detail. Froxel resolution remains unchanged.

The shared volume is updated when loaded scene bounds or haze settings change, not for emitter DMX updates. The historical per-emitter FogVolume implementation remains internal for reference but is not selected by any user-facing mode or preset.

## Ownership and diagnostics

Presentation ownership is explicit:

- Vector Prism owns only the vector shaft.
- Shared haze owns one scene-level FogVolume.
- A main realtime SpotLight contributes to haze only when its authoritative physical output is active and the selected haze mode requires it.
- Custom surface projection owns bounded Forward+ meshes/materials; the Native reference owns the crisp projector and its existing Godot 4.7 shadow dependency.
- The physical mask belongs only to Shared Haze + Gobo Shadow.
- Shader Beam Proxy owns one cached proxy instance per relevant emitter and requires neither shared haze nor a realtime SpotLight for its shaft.

`[peraviz-presentation]` reports native target/output/emitter ownership, authoritative active outputs and emitters, cached fixture lights, vector resources, proxy visibility/creation/parameter/texture counters, the shared haze, emitter FogVolumes, surface projectors, masks, realtime SpotLights, and shadowed SpotLights. Counts use stable target/emitter identities rather than per-frame SceneTree scans.

| Mode | Shaft resource scaling | Gobo motion | Native SpotLight for shaft |
| --- | --- | --- | --- |
| Vector Prism | One cached gobo-dependent mesh per emitter | Parametric rotation; texture selection can change topology | No |
| Shared Haze | One scene FogVolume plus active native lights | Surface projector only | Yes |
| Shared Haze + Gobo Shadow | Same scene FogVolume plus one mask per active gobo | Parametric mask/projector roll | Yes |
| Shader Beam Proxy | One instance of shared normalized topology per active/reused emitter | Texture/uniform only | No |

## Current limitations

- Surface projector correctness depends on real-time shadows in stable Godot 4.7.
- Projector textures do not shape stable Godot volumetric fog.
- Native gobo shadows are limited by froxel and shadow-map resolution.
- Shader proxy depth clipping is screen-space and does not provide physical shadowing or robust transparent-object occlusion.
- Authored lens textures are retained; additional optical lens-mask interpretation is outside this presentation feature.
- A scene with many genuinely active physical emitters can still make native volumetric lighting expensive; future aggregation or culling is outside this experiment.
- The broader live-DMX output/apply CPU bottleneck is separate work and is not solved by changing beam presentation.
- Focus, Frost, Iris, prism, and shutter semantics remain limited exactly as documented in the [GDTF support matrix](gdtf-support-matrix.md).

## Windows validation checklist

1. Load the canonical scene without Art-Net and confirm no fixture output resource is active and no missing-metadata errors appear.
2. Start Art-Net and select Vector Prism. Confirm open beams and vector gobo shafts are unchanged, and an asymmetric surface footprint rotates coherently with the prism.
3. Select Shared Haze without changing DMX. Confirm exactly one shared haze, zero emitter FogVolumes, active open shafts in haze, and a crisp gobo surface footprint.
4. Select Shared Haze + Gobo Shadow. Confirm the same haze is reused, active gobo outputs have masks, open outputs do not, and volumetric light reacts to the mask as Godot's resolution permits.
5. Select Shader Beam Proxy and confirm open/gobo shafts use the same surface centerline at two Pan/Tilt orientations and four indexed angles.
6. Switch all four modes repeatedly without a new DMX event; confirm no accumulated drift, stale white footprint, or missing gobo.
7. Capture diagnostics and at least ten settled `--peraviz-perf-trace` lines per experimental mode.
