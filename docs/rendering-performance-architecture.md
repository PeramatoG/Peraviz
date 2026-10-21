# Rendering and performance architecture decisions

**Status:** Native Control Groups and first AGGREGATED/INDIVIDUAL Render Emitter Groups implemented

**Date:** 2026-09-03

**Scope:** GDTF/MVR semantics, physical emitter ownership, render aggregation, batching, beam rendering, and the short-term performance roadmap.

This document records presentation and performance decisions that complement the active [runtime architecture](architecture.md). The runtime architecture remains authoritative for the implemented data path; proposed grouping and batching work in this document is not current capability unless stated otherwise.

## Current roadmap and evidence

The owner’s newer controlled Windows chase isolates the immediate bottleneck:

| Same chase; Pan/Tilt continuously moving | Owner-observed FPS |
| --- | ---: |
| Pan/Tilt + Color + Dimmer effects | ~24 |
| Pan/Tilt + Dimmer, Color effects stopped | ~46 |
| Pan/Tilt, Color and Wash Dimmer effects stopped | ~75 |

These are owner observations, not CI guarantees. The owner subsequently measured
no appreciable FPS improvement with the shared Control Group branch. This is not
a proven performance win: sharing one ShaderMaterial reduces parameter writes,
but does not batch 50 MeshInstance3D objects, submissions, overlapping transparent
surfaces or fragment workloads. The old fixture-wide wheel/gobo veto could also
suppress otherwise valid groups. It is now exact-output scoped; unresolved
ownership remains conservative. The real-import regression also exposed a second
veto: static per-Beam profile routes were being compared as independent Zoom
controls. Registry setup now separates those routes from actual selected-mode
Zoom authority. A normal MVR import proves the 50-member Control Group forms. Actual production membership is reported in one
startup summary. Pan/Tilt retains main’s normal transform ownership.

## Implemented first Control Group layer

`presentation/control_groups.*` derives setup-generation groups from the compiled
selected DMXMode. Immutable source-program identity proves Color input, DMX-byte,
ChannelFunction/ModeMaster and emitter/filter ownership; Color target IDs and
instantaneous values never establish equivalence. Dimmer/Zoom property ownership,
input order, optical profile, projected/emission scales and fixture scope must
match. Only open projected Wash/Spot outputs are eligible. Unproven wheel effects,
gobo ownership, ambiguous controls, unsupported profiles or missing actual renderer routes fall
back to individual presentation. Explicit realtime spotlights and debug beams
also retain the individual renderer path.

All canonical physical outputs and native values remain exact. Control Groups
still share dynamic shaft materials and source-compatible lens materials, but
are distinct from optical Render Groups. A separated two-cell source can share
one Control Group while retaining two INDIVIDUAL shafts. A compact pixel head can
have many Control Groups and one AGGREGATED shaft.

## First production Render Emitter Groups

Typed native `RenderEmitterGroup` records preserve inverse physical IDs and Control
Group IDs. `INDIVIDUAL` keeps existing presentation, `AGGREGATED` owns one Vector
Prism shaft, and `INSTANCED` is reserved. No aggregation is written into GDTF/MVR,
no physical IDs change and no selected DMXMode changes. Physical lenses remain
separate, including independently controlled pixels; lens glow is a later task.

Setup descriptors derive origins, directions, static local transforms and Axis
lineage from SceneModel. The anchor is the nearest mechanical ancestor, so normal
Pan/Tilt inheritance carries the aggregate. Reliable explicit BeamRadius, rigid
transforms, open Wash/Spot type, matching optical family/angle provenance and Zoom
authority, proven uniform Color-wheel transmission where present, and no relevant
gobo/spatial/temporal shaping dependency are required. Ambiguous
geometry, non-rigid scales, unsupported profiles/backends, explicit realtime
spotlights and debug beams use INDIVIDUAL presentation.

Centralized Peraviz heuristics in `AggregationPolicy` require at least 3 members,
direction spread at most 2 degrees, Beam/Field-angle differences at most 0.25
degrees, source-area/enclosing-aperture-area density at least 0.45, enclosing radius
at most 12 times the largest member radius, and axial depth within one member
radius. The area ratio uses the sum of squared reliable member radii divided by
the squared enclosing radius. Long bars, widely separated two-cell sources,
divergent emitters and different mechanical lineages stay individual. These are
presentation approximation thresholds, not GDTF rules; false negatives are safe.

Nominal projected flux fixes the static centroid and mean direction. The aperture
radius encloses every member origin plus its radius; nominal flux sums, while
BeamAngle/FieldAngle remain the compatible common profile. Origins never move
with animated pixel values. At setup all member shafts are made non-rendering;
only the aggregate shaft follows live visibility. Member anchors retain zero
open-light RID ownership, and the aggregate's anchor light has zero light energy
and cull mask. Surface footprint backends are not changed.

`RenderGroupProjection` retains POD member contributions and contiguous row sums.
Each changed member subtracts its previous contribution and adds its new one;
there is no per-frame membership rescan, allocation or SceneTree access. Physical
beam energy already includes projected flux scaling, Dimmer and physical Color
gain, so it supplies the color weight without applying flux/gain twice. Decode
boundary sRGB to linear light, accumulate `linear_rgb * physical_beam_energy`,
divide by total positive energy, then encode once for the existing shader API.
Sum existing perceptually scaled physical beam intensities and clamp to the
existing 0..50 visual range. Dark pixels add zero energy and cannot erase active
members. This is an explicit realtime optical approximation, not a change to
physical pixel state or photometry semantics.

The Godot boundary publishes exactly one renderer-sized PackedInt32Array of
row-index/mask pairs, one renderer-sized PackedFloat32Array of 12 scalars and one
valid count. Physical/group duplicate packed arrays are removed; borrowed arrays
are released before native writes, with no per-frame slices or per-row
Dictionaries. Prepared rows contain AGGREGATED or INDIVIDUAL render sources only.
For 20 compact 50-member heads, native state retains 1,000 physical outputs while
there are 20 shaft rows and 20 dirty rows for a shared dynamic tick.

Prepared lens material RIDs are separately bound at setup. Native **Godot boundary
code on the main thread** coalesces those cached RIDs and applies their exact
physical Color/emission values, avoiding physical lens rows in the shaft payload.
It never discovers nodes. Source-identical, single-pass lens appearances with
matching emission scale share a RID; different, overridden, multipass or unknown
static materials remain separate. Independent pixel lenses remain independent.
The native core itself remains Godot-free and trivially copyable where practical.

One `[peraviz-render-groups]` startup line separates native optical classification
from Godot binding rejection, with bounded reason counts. It reports canonical and
projected outputs, candidate buckets (at least three compatible members), native
accepted groups, Godot accepted/rejected aggregates, final rows, aggregated members,
allocated/visible shafts, unique lens RIDs, renderer/settings, compact payload bytes,
`presentation_contract_revision=4` and the extension compilation timestamp.
`native_rejected_physical` counts disjoint physical fallback outcomes; Godot rejection
counts measure groups. `compatible_peers` includes singleton/undersized compatibility
buckets; specific lineage/Zoom/profile/direction splits are reported when observed
while classifying siblings. These are outcomes, not counts of every failed pairwise
comparison. Initial visible counts may be zero before DMX; the existing trace samples
current visibility at its report boundary, without a per-frame resource scan.

### Dynamic Color instrumentation

Opt-in tracing separates native Color input evaluation/cooking and final composition
(cumulative native stats), physical presentation, aggregate reduction, lens RID
submission, payload conversion and GDScript application (interval counters). Work
counts include physical Color candidates, affected/unchanged unique lens RIDs, actual
setters and shaft mutations. Existing viewport CPU/GPU measurements remain separate;
API submission timing does not measure asynchronous GPU completion, and overlapping
stage times must not be added together.

Earlier Linux Debug/headless generated tests measured about 2.142 ms/tick for Color
evaluation/cooking, 1.473 ms composition, 0.316 ms physical presentation, 0.246 ms
reduction and 0.430 ms GDScript application. A 60-tick lens-only comparison issued
1,200 versus 60,000 setters for 20 shared versus 1,000 independent RIDs. These are
illustrative synthetic CPU results, not Windows or GPU performance claims. The
trace-gated `PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES=1` option remains available for
other workloads; it preserves physical state, is inactive trace-off and replays held
lens values on exit. The production evidence below has zero lens RIDs, so that
isolation is not the next owner test.

### Production wheel eligibility and efficient default

The owner's Windows revision-3 run confirmed 1,095 physical outputs, 1,075 projected
outputs, 1,095 control/render groups and zero native candidates. Native fallback
counts were 1,000 wheel dependencies, 23 projector dependencies, 20 emission-only,
16 axis-lineage and 36 compatible peers; Godot rejected no aggregates. During Color
activity the owner measured ~24–25 FPS, ~1,032 Color rows/applied frame, ~23,000 shaft
setters/s and ~12 ms GDScript application/frame; stopping Color gave ~74–75 FPS.
Native lens RID bindings/writes were zero. The all-wheel veto was an upstream blocker;
these measurements do not establish the entire CPU/GPU split or a new FPS improvement.

The subsequent revision-4 Windows run at `bd902d1` still had zero aggregates,
1,095 rows, and exactly 1,000 `wheel_missing_palette` rejections (~23 FPS with Color
active). Native compilation had incorrectly treated Base-level ColorMixReset and
ColorCalibrationMode as wheel owners through a broad Color-prefix check. The focused
correction uses parsed Color selection/motion identity and explicit Wheel references;
unlinked unsupported ColorEffects remains approximate. Missing references take priority
over approximation regardless of channel order. A generic 37-slot Basic-style regression
includes both Base controls, Spin, and unlinked FX, with a matching broken-link fallback
case. Geometry safeguards and live presentation policy are unchanged.

**Default policy:** compatible compact emitters contribute to one combined volumetric
shaft through their resolved physical Color/energy, even when colors differ. An
unsupported macro does not justify retaining fifty shafts when those shafts cannot
render it faithfully either. Classification is static selected-mode/setup data; entering
Spin/FX ranges never reclassifies groups or rebuilds their resources.

Keep four contracts distinct: canonical GDTF/DMX capabilities and physical identity;
implemented native evaluation; implemented visual presentation; and explicitly labeled
approximation. Canonical physical state, source programs, activation/ModeMaster, resource
ownership and inverse membership remain independent of shaft resolution. No grouping
or presentation approximation is written into GDTF/MVR.

The replacement native proof accepts exact fixture/output ownership, immutable source
and activation, valid uniform palette data and unambiguous function/slot mappings.
Control signatures include wheel source/palette/mode, snap/placement, exact ChannelSets
and retained unsupported FX source identity. Different RGB, pixel, ring or FX authority
splits Control Groups. Render Groups can still combine those independent contributions.
Media, unrecognized Slot payload, missing resources/ownership, gobo/projector dependencies
and genuine optical incompatibilities retain individual fallback. Known uniform Color-
wheel modes use the currently implemented resolved-color contract:

| Capability | Current native/display behavior | Compatible optical aggregation |
| --- | --- | --- |
| Seated Color selection | Exact supported slot transmission composed into physical RGB/gain | Allowed |
| Color-wheel Index | Existing adjacent-slot uniform color approximation; no spatial split display | Allowed as approximation |
| Spin / Random / Audio / other unsupported wheel modes | Existing deterministic first-palette-slot display; no faithful temporal phase | Allowed as approximation |
| ColorEffects without an evaluator | Preserve source bytes/ranges/activation; first-slot Color when linked, otherwise unchanged base Color | Allowed as approximation |
| Supported spatial/gobo/projector presentation | Existing distinct spatial resource/ownership contract | Individual fallback |

Unsupported effects remain unsupported: sharing their resolved approximation neither
implements animation nor claims phase/FX fidelity. NoFeature removes the wheel layer
and restores held base Color. Native diagnostics retain explicit unsupported-effect
messages; the startup summary adds `native_approximate_projected_color_outputs` and
presentation revision 4. Uniform-slot proof is setup-only Peraviz data, defaults absent
after semantic-only decoding, and does not expand GDTF capability coverage.

Normal-import tests verify twenty generated Basic-style sources with selection plus
potentially active Spin/FX ranges: **1,000 physical outputs → 20 render rows and actual
combined shafts**, with member shafts hidden. Independently authored 14/16/20-ring
geometry resolves through native SceneModel transforms to ~0.142 m enclosure, ~0.80
density and ~7.89 radius ratio while retaining 28°/43.75° Beam/Field angles. Tests cover
live supported selection, exact Color/gain and slot metadata, independently addressed
pixels/rings, real existing lens-material bindings, Dimmer/wheel blackout, CTC, Zoom,
Pan/Tilt, mode/renderer replacement and persistent aggregate resources across Spin/FX.
No private assets or fixture-model conditions are included.

Physical lens detail and volumetric shaft resolution remain independent. Existing
compatible lens sharing and independent material state are preserved; a future lens
visualizer may expose each LED while one shaft combines their contributions. A future
spatial fidelity renderer can be more expensive and use a separate capability contract.
This PR adds neither lens visualization nor a quality UI, missing effect evaluation,
threads, MultiMesh or GPU compute.

Owner validation requires one rebuilt normal trace-off GUI run of the reference MVR
and chase: copy `[peraviz-render-groups]` (revision 4), record Color-active and stopped
FPS, and compare native candidates/accepted groups with actual final rows. If all twenty
eligible heads aggregate and other outputs remain individual, ~115 rows is a conditional
expectation, not a guarantee or a policy threshold. Real activation and Windows FPS
still require owner measurement; automated tests qualify this change for GUI validation.

MultiMesh, LOD and C++ threading remain deferred. Future high-count INSTANCED
buffer generation can use contiguous native buffers, optionally prepared in C++,
then one `RenderingServer.multimesh_set_buffer()` submission. No worker thread
may access SceneTree nodes. The broader Render Group proposals below remain
future work beyond this first compact-source implementation.

## Core rule: authoritative semantics and presentation

Peraviz must keep the selected GDTF DMXMode, MVR scene data, and live DMX state authoritative. Rendering optimizations may use a coarser representation than the physical GDTF geometry only when they preserve the observable result for the current control topology. These optimizations are Peraviz presentation logic, not part of GDTF or MVR, and must remain clearly separated and documented.

> Semantic granularity is determined by the selected GDTF DMXMode. Render granularity may be coarser when the result is equivalent and the underlying physical and control identities are preserved.

Peraviz must never delete or reinterpret independently controllable GDTF emitters merely to improve performance.

## Historical evidence before foundation stabilization

The canonical Windows test uses:

- Godot 4.7.1 stable with Forward+;
- an NVIDIA RTX 3070;
- 82 fixtures;
- live Art-Net from grandMA3 on the same computer; and
- Vector Gobo Prism as the visual reference.

Before live DMX, the scene can reach roughly 75 FPS despite containing several million primitives. Under live DMX, the application can fall to roughly 2–5 FPS with process times in the hundreds of milliseconds. The visible sub-second DMX latency therefore appears mainly as main-thread/application throughput collapse rather than intentional buffering.

Important observations are:

- Vector Prism can remain very slow with only about seven real-time `SpotLight3D` nodes.
- Steady-state beam topology rebuilds are frequently zero.
- Removing expensive performance tracing does not remove the visible latency.
- Raw polygon count, native volumetric spotlights, and diagnostic tracing are therefore not sufficient explanations for the current bottleneck.

The investigation has found approximately:

- 95 native Dimmer targets;
- 1,095 physical output records;
- 1,095 unique emitter anchors;
- fan-out with a minimum of 1, median of 1, and maximum of 51; and
- 1,032 `EmitterColor` rows per applied visual frame in the canonical live test.

The investigation at that point aimed to prove whether the approximately 1,032 color updates genuinely result from shared controls fanning out to many physical Beam geometries or from an over-dirty, identity, or indexing defect.

## MAC Quantum Wash: why 51 outputs appear

The MAC Quantum Wash case is a useful architectural reference. The tested GDTF appears to expose 50 projected `Beam` geometries for the wash LEDs and one additional `AuraPlate` geometry. The Aura is emission-only (`BeamType=None`) and is not a master or combined projected wash Beam. This explains why Peraviz can discover 51 physical output records for one fixture.

The number of physical GDTF geometries is not necessarily the number of independent dynamic states that should be calculated or the number of expensive optical presentations that must be rendered. The selected DMXMode remains authoritative:

- In a simple or global mode, many physical LED or Beam geometries may share the same Dimmer, Color, Zoom, and transform authority.
- In a more detailed mode, subsets such as rings or zones may have independent control.
- In a truly pixel-addressable mode, individual emitters may have independent controls.

No fixture-name-specific exception should be required.

## Proposed native architecture

Peraviz should add an explicit grouping layer in native C++:

```text
GDTF physical emitters
        |
        v
Control Groups
        |
        v
Render Groups
        |
        +--> AGGREGATED
        +--> INSTANCED
        +--> INDIVIDUAL
```

### Physical outputs

Physical outputs preserve complete GDTF identity and geometry. They remain available for correct GDTF interpretation, independently addressable modes, lens appearance, diagnostics, picking if required, and reverting an optimized representation to detailed presentation.

Physical outputs are never discarded merely because several currently share the same controls.

### Control Groups

Control Groups should be calculated for the selected DMXMode from control authority, not from instantaneous DMX values. Two physical Beam outputs may share a Control Group only when their relevant dynamic authorities are equivalent. The control signature should eventually include, where implemented:

- Dimmer authority and source;
- Color sources and color wheels;
- Zoom;
- Focus;
- Frost;
- Iris;
- shutter and strobe;
- gobo selection;
- gobo indexed and continuous rotation;
- prism;
- Pan, Tilt, and Axis transform lineage; and
- other beam-shaping controls.

Equal current RGB values are insufficient. Equivalent control topology in the selected DMXMode is the relevant fact.

### Render Groups

A Control Group may still be unsuitable for one aggregate optical source if its members are spatially distributed. Render Groups use one of these presentation classes:

- **AGGREGATED:** Several physical emitters are represented by one optical source. A typical case is a compact multi-LED moving-head wash with near-parallel directions, the same Pan/Tilt ancestry, compatible optics, and the same control signature.
- **INSTANCED:** Several physical emitters share state but must remain spatially separate. A long pixel bar with global control is a typical case and a candidate for MultiMesh or RenderingServer batching.
- **INDIVIDUAL:** Emitters have genuinely independent controls or incompatible presentation.

## Quantum Wash target behavior

For a Quantum Wash-like fixture in a simple or global mode, the desired presentation is approximately:

```text
50 physical wash Beam geometries
        |
        +--> preserve 50 physical lens appearances
        |
        +--> one shared main control state
        |
        +--> one aggregated optical presentation
                - one volumetric shaft
                - one surface-light approximation
                - one aggregate optical aperture
```

The Aura remains independent and emission-only. In a more detailed mode, the same physical fixture may naturally resolve to several groups, such as Outer ring, Middle ring, Center ring, and Aura. The selected GDTF DMXMode control graph, not the fixture model name, must determine the exact grouping. Groups remain individual in a truly individual pixel mode.

## Aggregate optical approximation

The aggregate source is a deterministic Peraviz presentation approximation. For physical emitters `i`, the aggregate origin is the luminous-flux-weighted centroid:

```text
origin = sum(position_i * flux_i) / sum(flux_i)
```

The aggregate direction is:

```text
direction = normalize(sum(direction_i * flux_i))
```

Aggregation requires sufficiently compatible directions. Aggregate luminous flux is:

```text
aggregate_flux = sum(flux_i)
```

Emitter count increases total flux; it does not multiply Beam Angle. The effective aperture is:

```text
effective_aperture_radius =
    max(distance(lens_center_i, aggregate_center) + lens_radius_i)
```

If all members share a compatible profile, the aggregate uses the common Beam and Field angles. It does not multiply either angle by emitter count.

Aggregation is stricter for gobos and shaping. Members may share one aggregate optical presentation only when relevant state is compatible, including gobo selection and asset, index or rotation, Zoom, Focus, direction, aperture, Prism, Frost, Iris, and shaping where implemented. Otherwise, the group must split.

## Grouping before MultiMesh

MultiMesh optimizes how instances are submitted and rendered. It does not determine whether every expensive optical source is necessary. The preferred order is:

```text
GROUPING FIRST
    |
reduce about 1,000 physical projected outputs to perhaps tens of optical presentations
    |
BATCHING SECOND
    |
use MultiMesh or RenderingServer for remaining real instances
```

If twenty Quantum Wash fixtures each expose 50 projected LEDs, grouping could theoretically reduce about 1,000 projected wash shafts to about 20 main aggregate shafts in a simple or global mode.

## Long-term presentation pipeline

The preferred target architecture is:

```text
Art-Net / sACN
      |
native C++ GDTF/DMX semantic runtime
      |
resolved physical state
      |
Control Groups / Render Groups
      |
compact contiguous presentation state
      |
RenderingServer / MultiMesh / batched GPU resources
      |
Godot rendering
```

Avoid this high-volume path where practical:

```text
C++ -> GDScript -> Dictionary -> Node/meta -> shader/light mutation x1000
```

C++ owns high-volume semantic and state computation. Godot owns visual presentation.

## Renderer conclusions

### Vector Gobo Prism

Vector Gobo Prism remains the current visual and reference implementation. It produces the best current gobo shaft, but shaft and footprint mapping remain misaligned. The eventual correction must establish one coordinate contract for the optical centerline, static orientation, X/Y mirror and parity, and physical gobo angle. It must not use fixture-specific offsets.

### Shader Beam Proxy

The current experimental proxy is not yet the intended Unreal-style solution. It uses transverse geometric slices or disks and changes quality by discarding some slices, which is not equivalent to volumetric shader ray integration.

The intended replacement uses:

- one closed low-poly proxy volume;
- camera-ray integration or raymarching through it;
- bounded samples adaptive to Zoom and beam width;
- stable jitter or dither;
- scene-depth clipping;
- gobo sampling in the volume; and
- no gobo-shaped topology generation.

### Open and wash fast path

The CC0 Godot Spatial Light Shaft cone and depth-fade technique is worth evaluating as an inexpensive open-beam or wash renderer, distant LOD, or fallback when volumetric gobo detail is unnecessary.

### Shared Haze

Godot-native haze approaches remain diagnostic and research modes. At the current scale, they are unsuitable as the primary architecture because native fog resolution is insufficient for crisp shafts at large ranges without high cost, and roughly 1,000 real spotlights can exceed the normal Forward+ clustered-light budget. Grouping may later make native haze viable for a much smaller number of aggregate lights.

### Shaft, footprint, and lens separation

Preserve independent responsibilities:

```text
shaft presentation
surface footprint/projector
lens appearance
```

## Lens rendering

Physical lens appearance remains independent from shaft aggregation. A fixture may show all physical lenses while using one aggregate shaft. For a multi-LED wash, the target is:

```text
50 physical LED/lens appearances
1 aggregate volumetric wash shaft
1 aggregate surface-light approximation
```

Future lens presentation should apply the correct texture or mask, color, and Dimmer intensity without requiring one expensive projected light per visible lens.

## Color fan-out investigation

The native runtime already contains relevant-byte dirty tracking, affected-target evaluation, final-state comparison, and dirty-only visual-frame emission. The unexpected result is about 1,032 `EmitterColor` rows per applied visual frame. Before changing semantics, determine whether these are:

1. legitimate shared-control changes fanning out to many physical Beam targets;
2. incorrect dirty dependency or fan-out;
3. duplicate native target registration;
4. unstable color composition or epsilon behavior; or
5. a mixture of these causes.

If the fan-out is legitimate, physical GDTF targets must not be collapsed semantically. The optimization belongs in grouped and batched presentation.

## Performance trace policy

`--peraviz-perf-trace` remains opt-in. Trace-off measures actual product performance, including visible latency, FPS, responsiveness, and cheap process metrics. Trace-on diagnoses causes through section and domain rows, native dirty fan-out, physical-output commits, signature skips, beam, light, and material writes, and presentation ownership.

Tracing must never participate in renderer correctness. Diagnostic counters, SceneTree scans, temporary Dictionaries, and per-row clocks do not belong in the production hot path unless required. See [Live render latency diagnostics](live-render-latency-diagnostics.md) for the current trace contract and reproduction procedure.

## Historical phase labels and deferred proposals

These original phase labels are retained as investigation history, not the current
execution order. The consolidated roadmap above supersedes their numbering:
independent-output aperture batching must be proven before beam batching and
later grouping. The next active workstream is visual correctness.


### Historical Phase 1: live apply and dirty investigation

The earlier `codex/optimize-live-dmx-render-apply-path` investigation used these merge conditions:

- CI is green.
- Godot is warning-clean.
- Trace-off uses the true production fast path.
- Renderer correctness does not depend on diagnostic counters.
- The approximately 1,032 `EmitterColor` rows per frame are explained.
- Whether 95 controls fanning out to 1,095 physical outputs is legitimate is established.
- GDTF and MVR semantics remain intact.

### Historical Phase A2: sustained-playback stability baseline

Before implementing grouping, audit progressive growth, retire stale lifecycle
state, and compare bounded interval latency with CPU/GPU render times on the
canonical machine. The [Phase A2 audit](phase-a2-stability-audit.md) records the
bounded structures, concrete diagnostic/lifecycle fixes and deterministic soak
regressions. The [latency diagnostics](live-render-latency-diagnostics.md) define
the trace and exact production/diagnostic A/B commands. That investigation did not attribute the slowdown to a proven cause. The later
dense foundation eliminates the progressive collapse in the current owner-run
baseline; it does not solve renderer scalability.

### Deferred historical Phase 2 proposal: RenderEmitterGrouping

If the high fan-out is legitimate:

- derive Control Groups from selected GDTF DMXMode authority;
- derive Render Groups from control, spatial, and optical compatibility;
- implement `AGGREGATED`, `INSTANCED`, and `INDIVIDUAL` classes;
- preserve inverse mapping from render-group IDs to physical-output IDs;
- begin with projected wash and open-beam cases;
- do not hard-code fixture names; and
- repeat the canonical Quantum Wash benchmark immediately.

### Deferred historical Phase 3 proposal: batch instances

For `INSTANCED` groups and truly independent outputs:

- publish compact C++ presentation buffers;
- use RenderingServer or MultiMesh;
- avoid per-output GDScript and Node mutation where practical;
- batch open beams aggressively; and
- group gobo beams by a compatible texture and resource strategy.

### Deferred historical Phase 4 proposal: Shader Beam Proxy

Replace the slice or disk proxy with the intended Unreal-style volume integration.

### Deferred historical Phase 5 proposal: LOD and quality

- screen-size and distance LOD;
- a cheap open-beam shell at distance;
- adaptive volumetric samples;
- a useful maximum beam length;
- frustum and visibility culling;
- Focus, Frost, and soft edges; and
- lens texture and mask improvements.

### Separate visual correction

Correct Vector Prism beam and footprint coordinate alignment after the performance work is stable unless it becomes a prerequisite for the new presentation architecture.

## Merge criteria for the performance work

A reasonable merge checkpoint does not require solving every renderer issue. The work is mergeable when:

- GitHub Actions is green;
- startup has no new warnings or errors;
- trace-off remains the production default;
- performance changes do not alter GDTF or DMX semantic behavior;
- native target ownership remains correct;
- held state rehydrates correctly after presentation changes;
- diagnostic counters are separated from correctness;
- observed high fan-out is explained and documented; and
- larger remaining architecture work is explicitly deferred.

## Decisions to preserve

1. Never hard-code Quantum Wash or another fixture model for performance.
2. Use the selected GDTF DMXMode to determine semantic control granularity.
3. Preserve every physical GDTF emitter internally.
4. Allow Peraviz-specific render aggregation only when presentation-equivalent.
5. Prefer Control Group to Render Group over instantaneous-value grouping.
6. Require spatial and optical compatibility before reducing several emitters to one optical source.
7. Keep physical lens appearance independent from expensive shaft count.
8. Prove batching with about 1,000 genuinely independent outputs before using grouping as an additional optimization.
9. Prefer MultiMesh or RenderingServer for remaining high-count instances.
10. Keep high-volume computation in C++ and presentation in Godot.
11. Keep Vector Prism as the reference until a replacement proves better.
12. Use real shader ray integration, not geometric slices, for the future Shader Beam Proxy.
13. Keep Shared Haze diagnostic until aggregate real-light counts become reasonable.
14. Use trace-off to measure product performance and trace-on to diagnose causes.
15. Never silently change official GDTF, MVR, or DMX behavior for performance.

## Quantum Wash acceptance case

Use the tested Quantum Wash scene as the first end-to-end acceptance case for `RenderEmitterGrouping`. The test must prove that:

- all 50 physical wash Beam geometries remain known internally;
- the Aura remains a separate emission-only output;
- a simple or global mode resolves to the minimum safe optical Render Groups;
- detailed modes split according to the selected GDTF DMXMode control graph;
- no fixture-name exception is used;
- lens appearance can remain physically detailed;
- aggregate flux, aperture, and direction are deterministic;
- changing to an independently controlled mode does not lose physical capability; and
- live DMX latency and FPS improve measurably.

Then generalize with fixtures whose emitters are spatially distributed and must remain `INSTANCED` rather than `AGGREGATED`.
