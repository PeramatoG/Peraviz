# Rendering and performance architecture decisions

**Status:** Working technical reference

**Date:** 2026-09-03

**Scope:** GDTF/MVR semantics, physical emitter ownership, render aggregation, batching, beam rendering, and the short-term performance roadmap.

This document records presentation and performance decisions that complement the active [runtime architecture](architecture.md). The runtime architecture remains authoritative for the implemented data path; proposed grouping and batching work in this document is not current capability unless stated otherwise.

## Core rule: authoritative semantics and presentation

Peraviz must keep the selected GDTF DMXMode, MVR scene data, and live DMX state authoritative. Rendering optimizations may use a coarser representation than the physical GDTF geometry only when they preserve the observable result for the current control topology. These optimizations are Peraviz presentation logic, not part of GDTF or MVR, and must remain clearly separated and documented.

> Semantic granularity is determined by the selected GDTF DMXMode. Render granularity may be coarser when the result is equivalent and the underlying physical and control identities are preserved.

Peraviz must never delete or reinterpret independently controllable GDTF emitters merely to improve performance.

## Current performance evidence

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

The immediate task is to prove whether the approximately 1,032 color updates genuinely result from shared controls fanning out to many physical Beam geometries or from an over-dirty, identity, or indexing defect.

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

## Short-term roadmap

### Phase 1: finish the live apply and dirty investigation

The `codex/optimize-live-dmx-render-apply-path` performance work must reach these conditions before merge:

- CI is green.
- Godot is warning-clean.
- Trace-off uses the true production fast path.
- Renderer correctness does not depend on diagnostic counters.
- The approximately 1,032 `EmitterColor` rows per frame are explained.
- Whether 95 controls fanning out to 1,095 physical outputs is legitimate is established.
- GDTF and MVR semantics remain intact.

### Phase 2: native mode-aware RenderEmitterGrouping

If the high fan-out is legitimate:

- derive Control Groups from selected GDTF DMXMode authority;
- derive Render Groups from control, spatial, and optical compatibility;
- implement `AGGREGATED`, `INSTANCED`, and `INDIVIDUAL` classes;
- preserve inverse mapping from render-group IDs to physical-output IDs;
- begin with projected wash and open-beam cases;
- do not hard-code fixture names; and
- repeat the canonical Quantum Wash benchmark immediately.

### Phase 3: batch remaining instances

For `INSTANCED` groups and truly independent outputs:

- publish compact C++ presentation buffers;
- use RenderingServer or MultiMesh;
- avoid per-output GDScript and Node mutation where practical;
- batch open beams aggressively; and
- group gobo beams by a compatible texture and resource strategy.

### Phase 4: true Shader Beam Proxy

Replace the slice or disk proxy with the intended Unreal-style volume integration.

### Phase 5: LOD and final quality

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
8. Apply grouping before MultiMesh.
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
