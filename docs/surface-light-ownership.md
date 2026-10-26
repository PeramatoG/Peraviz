# Surface profile capability and realtime-light ownership

Every projected physical output can resolve a surface profile. That capability
**does not imply one active Godot realtime light per output**. Vector Prism keeps
its smooth radial profiles, shared Optical Projection State, dynamic FieldAngle,
axial decay, gobo energy normalization and cached footprint softness.

## Independent footprint backend

New sessions use **Vector Prism + Custom Footprints**: `beam_presentation=1`,
`footprint_backend="custom"`, `enable_realtime_spotlights=false`. **Vector Prism +
Native Footprints** keeps presentation 1 and selects `footprint_backend="native"`.
The shaft renderer is unchanged. Experimental numeric IDs 0/2/3 remain available
in advanced settings and retain their saved meaning; the quick menu shows the two
Vector Prism presets. PVZ archives without a backend migrate to native, while
explicit backend choices round-trip. Partial live settings never apply archive
migration. MVR imports use the current session settings, initially custom.

The custom backend owns bounded square-pyramid meshes and surface materials,
independently of shafts and GPU lenses. Both consume `OpticalProjectionState`;
its resolved anchor already includes lens offset, hierarchy, aperture, roll and
parity. A cached inverse of that world transform supplies perspective coordinates
`local.xy / (-local.z * tan(half_angle))`. Original cached PNG/BMP or supported
composed gobo textures supply artwork, including alpha and aspect ratio. Open
Spot/Wash use the established radial profile analytically, without textures.
No vectorized shaft geometry supplies the footprint image.

Native main-thread glue applies dirty **physical** Color/surface energy directly
to material RIDs in both serial and completed-async paths, independently of shaft
aggregation and gain. Blackout suppresses mesh instance RIDs too. Custom selection
clears native projector textures, gobo-required shadows and shadow masks; a gobo
cannot grant realtime-light ownership. Explicit realtime lighting and experimental
atmospheric lighting retain their separate policies. Resources survive unrelated
renderer rebinding; backend/scene retirement revokes borrowed RIDs before freeing
volumes. Held native state replays on selection and diagnostic changes.

Forward+ reconstructs the camera-visible opaque position using Vulkan NDC Z in
[0,1], rejecting Reverse-Z background depth 0. Exit faces bound raster coverage,
including cameras inside a volume. One normal-buffer sample gives a view-space
normal; the incident direction uses `VIEW_MATRIX` with no translation. This avoids
the CC0 shader's additional depth samples and preserves normal-map detail. It may
require a normal prepass attachment: fewer samples alone do not prove a GPU win.
The diagnostic derivative variant removes that sampler and is confined to tests.

`footprint_max_range` defaults to 40 m, independently of shaft length; a radial
80–100% distance fade avoids a hard end. This is a presentation limit, not GDTF
photometry. Imported scene bounds conservatively reject empty volume AABBs;
scenic transform subscriptions coalesce bounds growth without per-fixture scene
searches or colliders. Camera frustum culling and shader cone/depth masks finish
selection. New/remeshed receivers require scene setup again; bounds are deliberately
conservative. Transform/range/Zoom changes update geometry; Color/Dimmer and camera
motion do not search receivers. Gobo roll only updates the shared transform.

This is an additive, unshaded **Peraviz approximation**, with profile, inverse-square
attenuation and incidence, rather than native material/BRDF lighting equivalence.
The legacy cone renderer is outside this prototype. Only shared Vector Prism
optics and Forward+ opaque depth/normal receivers are supported; no automatic native
substitution occurs on other renderers. Transparent transmission is unsupported.
Camera depth is **not fixture-space occlusion**: hidden-from-fixture surfaces may
still receive light. Silhouettes, depth/normal prepass coverage and MSAA edges can
show screen-space artifacts. Selective low-resolution projector depth or bounded
geometric occlusion remains a follow-up; no new shadow maps are rendered here.

Mechanisms were adapted from [BluntBSE's CC0 projection shader](https://godotshaders.com/shader/compatibility-friendly-texture-projection/)
and [Rytelier's MIT normal-buffer shader](https://godotshaders.com/shader/fake-light-projection/).
Their published licences were verified; the [source notice](../scripts/shaders/custom_footprint.LICENSE.txt)
retains MIT terms. Neither upstream planar UVs nor per-pixel inverse/axis assumptions
were copied into the optical contract.

Custom trace keys are `custom_projector_resources`, `active_custom_footprints`
(before camera culling), `culled_custom_footprints`, `custom_projector_parameter_updates`
and `custom_footprint_dynamic_writes` (last native batch). Existing native projector,
shadow and cache-build gauges keep their original meanings; custom footprints do
not increase them. Counters use retained handles, never live SceneTree enumeration.

## Bounded graphical validation

The focused generated scene exercises original PNG/BMP floor/wall projection,
Spot/Wash, inclined scenery, held rotation/Zoom, camera-inside-volume, finite range,
and actual blackout draw suppression. [Custom image](images/custom-footprints/custom.png),
[Native comparison](images/custom-footprints/native.png),
[held rotation/Zoom](images/custom-footprints/held-rotation-zoom.png) and
[camera inside](images/custom-footprints/camera-inside.png) are actual viewport captures.
The six-output native comparison enables the existing open-light diagnostic for
matching open patterns; the production native preset retains its previous policy.

Godot 4.7.1 Forward+/Vulkan, Linux Debug extension, Mesa llvmpipe LLVM 19.1.7,
960×640, no MSAA, six measured frames after eight warm-up frames:

| Workload | CPU render ms | Software device ms | Draws | Native lights / shadowed projectors |
| --- | ---: | ---: | ---: | ---: |
| 6 custom, normal buffer | 0.168 | 32.709 | 11 | 0 / 0 |
| 6 native reference (open diagnostic) | 0.162 | 23.207 | 5 | 6 / 2 |
| 6 custom, depth derivatives (test only) | 0.157 | 31.276 | 11 | 0 / 0 |
| 1,095 custom | 1.352 | 190.113 | 1,100 | 0 / 0 |
| 1,095 custom, blackout | 0.116 | 13.679 | 5 | 0 / 0 |

Custom lit-pixel coverage (>0.15) was 29,505 pixels versus 23,289 native and 29,445
with depth derivatives. Coverage includes brightness/profile differences, not a
texture-fidelity score. Buffered normals avoid derivative discontinuities and use
normal-map detail, but these noisy software timings **do not establish a GPU speed
advantage** over derivatives or native rendering. The large scene uses a generated
projector grid, no native mass-light benchmark. It retains 1,095 surface materials
and instances with one shared volume mesh/shader; engine/driver memory is not
measured. Inclusive six-update CPU averages were 0.160 ms (six outputs) and
14.040 ms (1,095); they include the harness's existing shaft fallback and physical
adapter work with shaft gain zero, not just footprint writes.

Run the focused headless test with Forward+, then opt into actual graphics:

```sh
$GODOT --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --script tests/gdscript/test_custom_surface_footprints.gd -- --render-footprint-probe
```

`--footprint-count=1095` runs the custom-only large scene; `--footprint-output=PATH`
selects the capture/JSON directory (default `user://footprint-probe`). Hardware GPU
and normal-buffer bandwidth/quality measurements still need the owner's Windows
RTX 3070 / Godot 4.7.1 Forward+ run after CI. No Windows FPS gain is claimed.

## Regression and restored native-reference policy

Commit `f0e954d` accidentally made `smooth_profile_enabled && projected` sufficient
to enable every existing SpotLight RID. On the user's canonical scene this changed
a small surface-light set into potentially hundreds or 1,095 large overlapping
Forward+ lights. The reported result was approximately 1 FPS instead of 24–25 FPS.
Native angular falloff without shadows is cheaper than a projector, but is not a
scalable backend for thousands of independent theatrical surface lights.

The native reference grants realtime surface ownership only to:

- A currently assigned, genuine gobo/projector texture.
- Explicitly requested realtime lighting.
- Existing experimental presentation modes that already own realtime-light cost.

Open Spot/Wash/Fresnel/PC profile capability alone never grants ownership. Open
Rectangle likewise retains rectangular profile data without manufacturing a
projector or enabling shadows. Its required derived mask is attached only when
realtime presentation is explicitly requested. Existing SpotLight anchor Nodes
remain beam parents; the existing adapter suppresses their light RIDs independently.
This correction does not delete physical outputs or replace Vector Prism geometry.
There is no arbitrary numerical cap that silently drops valid gobos: the bounded
policy restores the pre-regression set of justified lights. A scene containing
many actual gobos can still be expensive.

`OpticalProjectionState.has_projected_surface_profile` reports optical capability.
The cached dense light handle separately records `owns_realtime_surface_light`.
Active visibility additionally depends on DMX/output visibility, ancestor visibility,
positive surface gain and diagnostic mode. In Vector Prism, zero `footprint_multiplier` disables
surface ownership and effect without hiding the atmospheric shaft. Zero shaft gain
does not remove profile data or a genuine gobo footprint.

The compatibility/manual-control path uses the same ownership policy; its desired
light state records ownership separately. It gates explicit footprint gain without
reinterpreting legacy experimental `spot_multiplier` callers. Saved settings still
use the existing migration. No GDTF/MVR values, selected mode or Zoom semantics change.

## Modes and counters

The existing diagnostic suppression contract remains:

| Mode | Native state / transforms | Atmospheric shafts | Realtime surface lights |
| --- | --- | --- | --- |
| `full` | Active | Vector Prism | Bounded policy |
| `no-beams` | Lighting held state, transforms and lens emission | Suppressed | Zero; bounded surface policy suppressed during this diagnostic |
| `transforms-only` | DMX/transforms | Suppressed | Zero; emissive materials suppressed too |

No-beams retains held gobo/control state and does no local gobo renderer work after
cleanup. Returning to full replays held state, including projectors, without fresh
DMX. This preserves the previous mode lifecycle rather than introducing another
surface rendering backend inside the diagnostic.

`[peraviz-surfaces]` logs startup inventory and, with trace enabled, each report.
The same current gauges appear in `[peraviz-stability].dense_presentation.surface_lights`:

| Key | Meaning |
| --- | --- |
| `projected_outputs` | Unique bound physical projected output IDs |
| `surface_profiles` | Unique outputs with at least one resolved surface profile |
| `owned_surface_lights` | Peraviz-bound SpotLight handles currently assigned realtime surface ownership |
| `active_surface_lights` | Actual requested-visible SpotLight RIDs after Node visibility gating |
| `active_open_surface_lights` | Active lights without a projector texture |
| `active_open_shadowless_lights` | Active open lights with shadows disabled |
| `active_projector_lights` | Active gobo/projector lights, including experimental native shadow masks |
| `shadowed_projector_lights` | Active gobo/projector lights with shadows enabled |
| `active_projector_textures` | Active projector bindings, not unique texture resources |
| `surface_light_activations` / `surface_light_deactivations` | Visibility transitions in the report interval |

Counts cover the existing Peraviz dense handles, not unrelated scene lights.
Output/profile counts deduplicate multiple anchors. Fixed-size bitsets update
inventory when existing handles change; reading the gauges does not enumerate the
scene tree or scan every light per frame. Current gauges survive interval resets.
The established once-per-report beam visibility sampling remains unchanged.

Trace also reports lifetime `presentation_cache_builds`: per-renderer footprint
texture creations and gobo energy builds. An energy build comprises the static
transmission analysis and coverage/chord lookup. These counts should settle after
setup/selection/settings changes. They must stay flat through dimmer/color updates,
ordinary DMX frames and camera movement. Zoom/roll reuse their static textures.
Caches remain bounded; no filtering or transmission analysis moved into playback.

## Diagnostic open realtime lights: small scenes only

Only the explicit **application user argument**
`--peraviz-open-footprint-lights=on` grants open Vector Prism profiles realtime
ownership for development A/B. Default, `off` and invalid values are off. This is
not a normal UI option, saved visual setting or production scalability solution.
It can deliberately reproduce the light explosion; do not enable it on the
1,095-output reference scene as a default.

On a small fixture/gallery, open circular types use their already-resolved native
SpotLight angular attenuation and inverse-square-like distance attenuation with
no projector texture or added shadows. A real gobo continues using its shadowed,
softened radial projector. Explicit Rectangle presentation needs its mask.

The gallery obeys this switch and logs `profile`, `owns_light`, `projector` and
`shadow` for each case. Existing published open-footprint captures demonstrate the
**diagnostic capability**, not an automatically active production footprint per
physical output.

## Exact Windows validation

Use the same camera, scene, DMX stream, visual settings, window size and warm-up.
Load the canonical 82-MVR-fixture / 71-live-renderer-fixture / 1,095-output scene.
Record stable FPS and trace `viewport_gpu_ms`, draw count and the surface inventory.

```powershell
$godot = "C:\Users\Peramato\Desktop\Programas\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-render-diagnostic=full

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=full

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=no-beams

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=transforms-only
```

For the **small automated gallery only**, compare the same command with and without
the final `on` argument (it captures seven cases and exits):

```powershell
& $godot --path C:\codigoscpp\peraviz --script tests/manual/vector_light_profile_gallery.gd -- --peraviz-open-footprint-lights=on
```

The user-reported pre-regression references remain full trace OFF 24–25 FPS,
full trace ON 22–23 FPS, no-beams 30–32 FPS and transforms-only 50–59 FPS. The broken
`f0e954d` result is about 1 FPS. **Post-fix canonical FPS and GPU time are unmeasured
here**: this Linux environment lacks the canonical MVR/live DMX and Windows RTX
3070. Deterministic 1,000-output ownership tests and software Forward+ A/B captures
prove the policy, not performance recovery on that hardware. Improvement merely
to 5–10 FPS does not meet the user's acceptance target.

The gobo energy shader is unchanged in this correction. Open shafts avoid its
gobo lookup/atan branch. Gobos use a coverage lookup and orientation atan per
fragment; camera-inside source-mask classification is in the vertex stage. First
repeat the canonical benchmark with bounded surfaces. If a substantial GPU gap
remains, compare open versus heavy-gobo shafts with identical camera/DMX/profile
settings and `footprint_multiplier=0` to isolate atmospheric shader cost. Record
`viewport_gpu_ms` against the pre-corrective baseline before optimizing; do not
remove topology energy normalization speculatively.

## Reported broad Spot photometry

The user-reported MAC Axiom Hybrid source is explicitly Spot with BeamAngle 14.5°,
FieldAngle 51.7857°, LuminousFlux 16,000 lm and Zoom 44° to 2°. Its description says
“Official Martin Professional File (no measurements)”. That pair produces an
unusually broad tangent-space shoulder and exponent below 1. These supplied
numeric values are regression-tested; the actual GDTF archive is not present in
this workspace, so no new archive audit is claimed.

Generic opt-in optical diagnostics mark an independently authored Spot tangent
Field/Beam ratio above 3 as `photometry_review=suspicious-spot-shoulder`. This is a
review hint, not rejection, a fixture-name exception or a silent fallback. Spot,
original angles, source flux and native Zoom remain canonical. A later dedicated
policy may define overrides for unreliable/non-measured input; this correction
adds none and does not treat those values as the performance blocker.

## Deferred scalable surface presentation

```text
physical outputs
    -> shared optical/surface state
    -> Control/Render Groups
    -> bounded/batched surface presentation
```

The last two presentation stages are a future milestone. This branch implements
neither RenderEmitterGrouping nor a batched footprint renderer. Generic open
profiles are ready as data; scalable visible open footprints remain deferred.
