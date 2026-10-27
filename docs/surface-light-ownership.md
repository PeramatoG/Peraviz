# Surface profile capability and realtime-light ownership

Every projected physical output can resolve a surface profile. That capability
**does not imply one active Godot realtime light per output**. Vector Prism keeps
its smooth radial profiles, shared Optical Projection State, dynamic FieldAngle,
axial decay, gobo energy normalization and cached footprint softness.

## Independent footprint backend

New sessions use **Vector Prism + Custom Footprints**: `beam_presentation=1`,
`footprint_backend="custom"`, `enable_realtime_spotlights=false`. **Vector Prism +
Native Footprints** keeps presentation 1 and selects `footprint_backend="native"`.
The shaft renderer is unchanged. The unmatched quick-preset entry is labelled
**Modified settings**; it never selects a backend. A status line always identifies
the active backend and Native's gobo-only coverage. Programmatic control updates
emit no intermediate settings, so a preset commits once. Experimental numeric IDs 0/2/3 remain available
in advanced settings and retain their saved meaning; the quick menu shows the two
Vector Prism presets. PVZ archives without a backend migrate to native, while
explicit backend choices round-trip. Partial live settings never apply archive
migration. New MVR documents select the preferred custom route; opening a PVZ instead
restores its explicit or migrated backend.

New sessions and both presets use `footprint_multiplier=0.6` and
`footprint_softness=0.10`; explicit PVZ values remain intact. The surface shader
applies native Color/energy once, then this visual gain. Reliable Beam/Field radial
anchors stay primary. Unanchored type fallbacks use one broad Wash terminal
feather and a moderate Spot feather; gobo artwork is never blurred. These are
Peraviz visual defaults, not physical calibration or new GDTF attributes.

The custom backend owns conservative twelve-sided cone meshes and surface materials,
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
normal. Vertices cache view-to-projector rows and the view-space optical origin,
so fragments avoid repeated world/view matrix work. Common exact radial exponents
2/8 use multiplication; general profiles retain `pow`. Exactly zero artwork
transmission rejects work early without dropping faint detail. This avoids
the CC0 shader's additional depth samples and preserves normal-map detail. It may
require a normal prepass attachment: fewer samples alone do not prove a GPU win.
The diagnostic derivative variant removes that sampler and is confined to tests.

`footprint_max_range` defaults to 40 m, independently of shaft length; a radial
80–100% distance fade avoids a hard end. This is a presentation limit, not GDTF
photometry. Imported scene bounds plus the application Ground conservatively reject empty volume AABBs;
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

## Live settings, held replay and measured CPU cost

Gains change presentation values, never the renderer installation. The native
main-thread cache retains final displayed render rows, not another physical/DMX
state. Shaft replay covers individual, Control Group and aggregate resources,
including zero recovery. Surface replay retains unscaled physical energy separately
from gain, so restoring a zero gain is exact. Neither replay consumes or retires an
in-flight native snapshot; subsequent completion applies the newest gain. Scalar
changes do not advance renderer compatibility revisions or gobo phase/topology.
Footprint softness writes existing uniforms; range edits update existing volume
bounds. Actual radial support changes can refresh their optical geometry. Preset
matching uses an explicit optical key contract including profile, softness and range;
independent environment controls do not select another optical preset/backend.

One focused before/after run used the same generated production-imported MVR:
1,000 physical outputs, 20 aggregate shafts and 1,000 independent Custom footprints,
Linux Debug, Godot 4.7.1 headless Forward+. These are **CPU main-thread settings
costs, not GPU/frame rates**. DMX was held or changed/submitted for the indicated
case; the corrected active case also starts native consumption before the edit.

| Settings transaction | Before ms | After ms | Native gain replay µs |
| --- | ---: | ---: | ---: |
| Shaft gain, held DMX | 4,970.065 | 0.636 | 20 |
| Shaft gain, changing DMX | 4,973.251 | 0.518 | 15 |
| Footprint gain | 127.307 | 0.253 | 49 |
| Footprint softness | 4,937.729 | 5.827 | — |
| Custom → Native | 119.996 | 118.375 | — |
| Native → Custom | 150.732 | 155.054 | — |

Previously each scalar transaction recreated 20 aggregate shafts and reinstalled
dense/lens/footprint associations; shaft/softness refresh also called a global
resource rebind for every emitter. Corrected scalar cases created/retired **zero**
shafts, lens batches or footprint volumes, installed zero bindings and made zero
registry calls/scans. Shaft edits issued 20 script beam parameter writes; surface
gain issued 1,000 native material writes; softness issued no beam writes. Backend
changes intentionally still replace 20 aggregate shafts and retire/create the
1,000 footprint volumes, with two batched indexed registry calls and no full scan.
The aggregate workload has no admitted GPU lens batches; the independent 1,000-row
regression additionally checks that its existing GPU lens batches remain identical
through scalar edits. Timings are individual trace samples, not CI thresholds.

Reproduce via `test_render_emitter_groups.gd -- --live-settings-probe` using Forward+.
Normal runtime tracing is opt-in and reports settings duration, native replay,
actual writes and constant-time resource deltas. Regression coverage also checks
both serial aggregate and completed-async independent paths, pending DMX, original
gobo image/roll preservation, no-op settings and renderer/reload fallbacks. The small
Forward+/Vulkan graphical check now changes gain/softness through the shared live
update helper; opaque floor/wall/incline imagery and zero native projectors remain.
Its Custom, held-rotation/Zoom and camera-inside captures are pixel-identical to
the preceding committed captures on the same software Vulkan device.

This fixes interactive settings reconstruction. The remaining full-coverage GPU
projection cost is the next performance milestone; the owner's 55/95 FPS figures
still compare different coverage and cannot establish relative renderer speed.

## Bounded graphical validation

The owner's Windows RTX 3070 / Godot 4.7.1 Forward+ observations (V-Sync off,
same MVR/chase) were initially about 60 FPS (latest report: 55 FPS) with all Custom footprints and 95 FPS with
Native's gobos only. The former generic “Custom” quick entry also showed Native
coverage. **Those are unequal workloads, not a Custom-vs-Native speed comparison.**

The generated scene covers PNG/BMP gobos, Spot/Wash together, floor/wall/incline,
held DMX, preset/renderer changes, mirror/rotation, camera-inside, range and blackout.
[Previous defaults](images/custom-footprints/previous-defaults.png) and
[softer 0.6-gain defaults](images/custom-footprints/custom.png) use the same physical
inputs. The isolated scene peak fell from 215 to 171 (8-bit output); neither clipped
highlights. Dense overlapping footprints
still saturate additively. There is no nonlinear clamp or second Dimmer/Color gain.

One equal-coverage 1,095-output comparison, Linux Debug, Godot 4.7.1 Forward+/Vulkan,
Mesa llvmpipe LLVM 19.1.7, 960×640, no MSAA, eight warm-up/six measured frames,
identical textures, range (8 m for the generated floor), 0.6 gain and 0.10 softness:

| Custom variant | CPU render ms | Software device ms | Draws | Lit pixels (>0.15) |
| --- | ---: | ---: | ---: | ---: |
| Square volume, original fragment math | 1.381 | 195.637 | 1,100 | 58,075 |
| Circumscribed cone, original math | 1.372 | 179.634 | 1,100 | 58,075 |
| Cone + vertex-cached transforms / exact fast powers | 1.329 | 169.676 | 1,100 | 58,076 |
| Blackout | 0.122 | 9.857 | 5 | 0 |

The cone changed **zero pixels**; optimized math changed ten pixels by one 8-bit
level maximum (one crossed the reporting threshold). All 1,095 emitters and original
image details remain. Native surface lights / shadowed projectors were 0/0 in all
variants. A twelve-sided circumscribed cone bounds the entire circular support,
removing square-corner coverage (19.6% less axial cross-section), at the cost of
22 rather than 6 triangles per footprint: viewport primitives rose 6,630→24,150.
Actual fragment-invocation/overdraw counters are unavailable. This shows a software
rendering cost reduction, **not an RTX FPS prediction**; vertex/bandwidth tradeoffs
still need Windows validation. Overlap and one draw/material per physical footprint
remain. Engine/driver memory was not measured.

Render Group acceptance proves shaft aggregation, not identical surface distributions.
The existing compact generator has distinct emitter offsets and potentially separate
RGB authorities. Those project different patterns on inclined/depth-varying receivers;
no approximate member collapse is applied. Immutable mesh/texture sharing is retained.

```sh
$GODOT --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --script tests/gdscript/test_custom_surface_footprints.gd -- --render-footprint-probe
```

`--footprint-count=1095` runs the controlled Custom-only comparison; the optional
`--footprint-output=PATH` selects captures/JSON. Clean-cache CI retains Native/Legacy
lifecycle checks and adds the normal Custom path, including gobo→open while hidden.
Selection invalidates shared shaft geometry; cold renderer replacement publishes
final registry handles in one batch; newly bound lenses inherit diagnostic suppression.
No readiness checks are weakened. Fixture-space occlusion remains deferred.

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
ordinary DMX frames, camera movement and gain-only edits. Zoom/roll reuse their static textures.
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

## GPU/photometry follow-up: conservative fragment rejection

The PR #114 geometry and independent resource ownership remain. The custom shader
now rejects the existing zero-fade Euclidean range region before artwork/normal
sampling and shares squared distance/inverse length across incidence, fade and
attenuation. Depth remains necessary to reconstruct the receiver; no projector,
normal or artwork detail is dropped. No draw batching, receiver-index expansion,
material replacement or worker changes are introduced.

Same corrected profiles, camera, geometry, native values, gain 0.6, softness 0.10,
960×640, eight warm-up/six captured frames, generated 1,095-output workload:

| Case | Previous fragment | New fragment |
| --- | ---: | ---: |
| Projector draws / scene draws | 1,095 / 1,100 | 1,095 / 1,100 |
| Volume triangles including scene | 24,150 | 24,150 |
| Range-bound case (4.1 m): lit pixels | 52,443 | 52,443 |
| Range-bound case: saturated pixels | 1,568 | 1,568 |
| CPU renderer submission ms, one sample | 1.332 | 1.297 |
| Ordinary 8 m case: lit pixels | 58,076 | 58,076 |
| Native projector / shadow lights | 0 / 0 | 0 / 0 |

All 1,095 eligible volume resources remain; conservative scene-bound culling is
unchanged. Range-bound images differ at eight pixels by at most 1/255; ordinary
range images are identical. A test-only receiver-position diagnostic measured a
48,556-pixel union of **open** opaque receivers whose normal lookup is now skipped.
That union is a conservative lower bound on logical texture lookups avoided, not
a hardware fragment-invocation/overdraw counter. Original gobos also avoid artwork
sampling in that zero-contribution region. Production allocates no new resources;
setup/native material routing and held writes are unchanged. Driver memory bytes
and real GPU frame times are unavailable here.

Validation used Godot 4.7.1 Forward+/Vulkan on llvmpipe solely for fidelity and the
lookup-rejection image. Software device times (range case 80.5→84.3 ms, ordinary
range 178.3→171.9 ms) are **not evidence of GPU speedup**. No RTX FPS gain is claimed.
The owner’s 55 FPS full-coverage reference remains separate from Native’s seven-gobo
90 FPS workload. Real hardware acceptance remains required. One draw/material per
projector and overlap remain the next measured bottlenecks; no unsafe source
collapse was made.

Run the existing graphical test with `--render-footprint-probe --gpu-cost-probe`
and optionally `--footprint-count=1095`. It uses the previous fragment algorithm
with identical corrected profiles, not the obsolete square/planar geometry. The
small scene includes authored and defaulted Wash, Spot, PNG/BMP artwork, wall,
floor/incline, held Zoom/rotation/parity, range, camera-inside and blackout.
