# Custom Footprint live rendering audit

Base: `c7f0cc5` (latest main at investigation start). The supplied `scene.mvr`
imports through the production loader as 82 MVR fixtures, 71 runtime fixtures,
1,095 physical outputs, 115 render rows, 20 aggregate shafts covering 1,000
emitters, 95 individual shaft resources, and 1,075 independent Custom Footprints.
The archive is read-only and is not included in this change.

The Windows / Godot 4.7.1 / Forward+ / RTX 3070 observations imply approximately
37.04 ms Full, 35.71 ms with lens writes suppressed, 14.49 ms No-beams, and
13.42 ms transforms-only. Thus Full–No-beams is about **22.55 ms**. These are
reciprocals of reported FPS, not measured CPU/GPU durations. Native evaluation
remaining active in transforms-only rules out blaming that evaluation alone.
The lens comparison does not explain most of the gap. The individual shaft,
footprint, mutation, Vulkan submission and GPU shares remain **unmeasured on
Windows**; no percentage attribution or FPS improvement is claimed here.

## Ownership and evidence

| Stage | Owner / measurement boundary |
| --- | --- |
| Source evaluation | Native compiled runtime, dependency graph and async/serial pipeline; `native_evaluation_us`. Synthetic probe rows deliberately exclude this stage. |
| Physical composition / reduction | Native dense state, canonical physical routes and Render Groups; `native_physical_us`, `native_reduction_us`, `native_compose_us`. |
| Mechanical propagation | Godot registered Pan/Tilt nodes, inherited emitter offsets, `OpticalProjectionState`, volume notifications; new exact work counters below. |
| Renderer mutations | Main-thread native `PresentationMaterialBindings` caches Color/energy per physical material; script optics retain matrix/profile/texture revisions. Setters are not draws or queue submissions. |
| Render preparation / submission | `render_setup_ms`, viewport `cpu_render_ms`, draws, primitives and rendered objects. These do not isolate RenderingServer waits, driver CPU cost or `vkQueueSubmit`. |
| GPU execution | Viewport GPU timer on real hardware. Software-device times only validate the experiment. Present/compositor costs are outside this timer. |

Reading `anchor.global_transform` computes/caches scene transforms on the main
thread. This code does not itself request a GPU fence/readback. Material setters
can still cause rendering-thread/driver work; source inspection cannot establish
whether that work or synchronization dominates. Capture Godot main/render thread
profiles and a RenderDoc/Nsight frame on the target hardware, including queue
submission and GPU passes, before attributing CPU wall time to shader execution.

Each footprint has one material and shares the existing twelve-sided cone mesh
(22 triangles). Camera frustum rejection, conservative receiver AABB rejection,
receiver-depth raster caps, and shader cone/depth/range masks serve different
purposes. `active_custom_footprints` is before camera culling; allocated resources
are not visible draws. Viewport object counts include opaque and transparent
objects; the public API does not expose an exact transparent-only count, so the
probe reports that field as null. Use a graphics capture for pass/object identity,
transparent overlap, fragment coverage and actual Vulkan submissions.

Additive exit faces can overlap substantially. Depth/normal reconstruction and
gobo/profile evaluation are per covered sample. The trivial shader changes
receiver masking, output and possibly prepass requirements: it is a pipeline
bound, not an equivalent-image shader benchmark. Neither its timing nor lit-pixel
union is a hardware overdraw measurement. Projection range comparisons must keep
visible receiver coverage, optical aperture and shader distance fade identical.
No shader, optical profile, bounds/culling policy, material sharing or shaft
aggregation is changed by this audit.

## Demonstrated redundant work and narrow corrections

The same 128-projector, 60-step transform experiment before/after gives:

| Work across all outputs | Before | After |
| --- | ---: | ---: |
| Fixed-origin rotations: inverse matrix setters | 7,680 | 7,680 |
| Fixed-origin rotations: origin setters | 7,680 | 0 |
| Translations: inverse / origin setters | 7,680 / 7,680 | 7,680 / 7,680 |
| Changed explicit optical sync: bounds recomputations | 15,360 | 7,680 |

`_sync_world()` still checks the same approximate world-transform equality and
updates every changed physical inverse immediately. Once that existing gate
admits a change, the origin setter now uses **exact** origin equality. No looser
tolerance, scheduling change or throttle is added. `sync()` uses the returned
world-change result to avoid recomputing bounds that `_sync_world()` just updated.
Unchanged-world Zoom/range/geometry changes still run bounds work.

Queued ancestor notifications can revisit an already-synchronized volume; the
world comparison suppresses duplicate inverse/origin writes. A volume scale change
can also generate a self notification. The audit counts these checks separately
from real changes and retains notifications: removing them broadly could lose
independent emitters, roll, parity or changes outside the registered Pan/Tilt path.
Shared mechanical ancestry must still update each distinct physical projector.
A shared parent inverse cannot replace differing emitter offsets/roll/parity.
No measured evidence here justifies adding a second parent-transform cache.

## Supplied-scene presentation isolation

Godot 4.7.1 Forward+/Vulkan **llvmpipe software**, 320×240, four warm-up/eight
sampled frames per case, imported scene and default fitted camera, synthetic
resolved inputs (not the owner's stream):

| Case | Visible draws | Changed worlds/frame | Projection setters/frame | Physical footprint setters/frame |
| --- | ---: | ---: | ---: | ---: |
| A Full | 2,400 | 1,023 | 2,046 | 2,110 |
| B shafts only | 1,325 | 1,023 | 2,046 | 2,110 |
| C footprints only | 2,305 | 1,023 | 2,046 | 2,110 |
| D scene/motion | 1,230 | 1,023 | 2,046 | 2,110 |
| E static | 2,400 | 0 | 0 | 0 |
| F Dimmer/Color | 2,400 | 0 | 0 | 2,110 |
| G mechanical | 2,400 | 1,023 | 2,046 | 0 |
| H combined | 2,400 | 1,023 | 2,046 | 2,110 |
| I trivial program | 2,400 | 1,023 | 2,046 | 2,110 |
| J shafts, no footprint material writes | 1,325 | 1,023 | 2,046 | 0 |

All 1,075 footprints remain allocated, zero receiver-AABB culls occur, and all
1,075 add a draw in this camera. Shafts add 95 draws while their 20 Wash aggregates
retain 1,000 members. The scene baseline has 1,230 draws and 1,350 rendered objects;
Full has 2,520 rendered objects. A–D preserve identical mutation counts. J removes
only the physical material setters relative to B, retaining projector work.
No footprint creation/retirement occurs inside the cases; all 1,075 are retired
at teardown. Resource counts remain stable, with zero native surface lights.

Each changed origin in this actual mechanical case changes **physically**: all
8,184 changed worlds in eight frames need both inverse and origin setters. Thus
the exact-origin optimization saves no setters in this supplied-scene motion case.
There are 10,246 world checks, including notification revisits, but only 8,184 real
updates and no duplicate matrix submissions. Explicit optical sync calls are zero
in the dynamic matrix; the duplicate-bounds correction does not accelerate that
path either. At 27 frames/sec, 1,023 world groups/frame would be 27,621 logical
increments/sec, consistent in scale with the owner's observation, not proof that
the owner's stream has identical motion. Pure Dimmer/Color here changes no world
uniforms; the new trace can establish which behavior the real stream exercises.

CPU viewport samples vary substantially even with identical work; software-device
results do not attribute the RTX gap. Before/after graphical six-output checks
use the same inputs, coverage, camera and shader. All ten case images are
pixel-identical and draw/material-write counts are unchanged; moving-case origin
setters fall from 48 to zero across eight frames, with all 48 inverse setters kept.
A separate 30-warm-up/120-sample six-output run also keeps all ten images exact
and reduces moving-case origin setters from 720 to zero (720 inverse setters
remain). Full-case viewport CPU samples are 0.118→0.132 ms and callback CPU is
438.8→433.1 µs; the H repeat is 0.120→0.136 ms and 401.3→524.7 µs. These noisy
software samples establish **no CPU frame speedup**, despite fewer API calls.
The shader, culling and physical output count have no performance change to claim.

## Counter contract

The existing `custom_projector_parameter_updates` counts logical update groups:
geometry, profile, texture, softness and world changes each increment once. A world
group previously meant two setters; a profile group means four. **27,000 group
increments/sec is not 27,000 shader writes/sec or draws/sec.**

Opt-in performance tracing now propagates to retained and newly installed volumes.
It adds cumulative counters for `custom_sync_calls`, `custom_transform_notifications`,
`custom_world_checks`, `custom_world_changes`, `custom_inverse_writes`,
`custom_origin_writes`, `custom_bounds_recomputations` and `custom_uniform_writes`.
Take interval differences within one resource generation. Counts are exact API
calls/branches while tracing, not GPU events. Native Color/energy writes remain
separate (`custom_footprint_dynamic_writes` is the last native transaction);
the probe explicitly sums them per transaction. Shutter counters retain their
existing cumulative contract. Diagnostic arrays allocate only when tracing first
turns on (64 bytes of counter payload per volume); no per-frame counter containers
or clocks are added. Counters survive trace toggles and reset when resources retire.

## Reproduction

Extend the existing probe with these opt-in arguments, Forward+ and Vulkan:

```powershell
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --script tests/gdscript/test_custom_surface_footprints.gd -- --render-footprint-probe --bottleneck-probe --live-footprint-probe --footprint-warmup=60 --footprint-samples=240 --footprint-resolution=1920x1080 --footprint-output=C:/Temp/peraviz-live
```

Add `--footprint-count=1095` for generated independent projectors. To use the
actual imported resource graph instead, add `--footprint-scene=C:/path/scene.mvr`.
The imported run retains actual Render Group membership, shared mechanical
ancestry, physical routes and independent fallback. It pauses application input
and drives synthetic resolved Dimmer/Color rows and mechanical motion. It does
**not** replay the owner's Art-Net stream, GDTF source evaluation, selected gobo
sequence or strobe. Those require a separate normal-application capture with the
same external DMX recording. Never label synthetic presentation rows as DMX cost.

`live-bottleneck.json` and PNGs contain the following controlled comparisons:

| Case | Draws / inputs |
| --- | --- |
| A | Full shafts + footprints; combined resolved changes and motion. |
| B | Shafts only; footprint draw layers zero, all mutations retained. |
| C | Footprints only; shaft draw layers zero, all mutations retained. |
| D | Scene geometry and motion; both lighting draw layers zero, mutations retained. |
| E | Full resources, held resolved values and transforms. |
| F | Full resources, changing resolved Dimmer/Color only. |
| G | Full resources, changing mechanical transforms only. |
| H | Full resources, combined changes (repeat of A). |
| I | Combined changes, trivial footprint program, full shaft program. |
| J | Same draws as B, also suppress native footprint Color/energy writes. |

A–D isolate rendering with equivalent input/mutation work; B/J isolates physical
surface material writes without removing resources or mechanical work. E–H isolate
presentation domains. Projection uniform/transform costs remain distinct from
physical material writes; none of these differences alone proves GPU dominance.
There is no production suppression policy or saved preset change. The runner
restores layers/shaders/mechanics/V-Sync/frame cap and retires its scene resources.
The original bottleneck matrix and range/image checks remain available unchanged
by omitting `--live-footprint-probe`.

Readback, PNG writing and pixel analysis happen after timing. `frame_wall_ms`
includes frame scheduling and overlapping CPU/GPU work; `application_us_per_frame`
measures callback CPU work (not notification propagation later in the frame).
Viewport timers and trace scopes overlap. The process-time monitor is a coarse
sample and can include earlier capture overhead; it is explicitly named
`sampled_process_monitor_ms`, not an isolated CPU duration. For hardware runs keep
camera, resolution, V-Sync, scene, profiles, range, input sequence, build and tracing
identical, repeat runs, and report dispersion. Do not sum case differences.

## Validation status

Linux checks establish redundancy removal, physical/resource semantics and probe
operation, not Windows GPU performance. All 13 native CTests and all 44 GDScript CI tests pass, including the new
128-output transform regression. Repository architecture/size checks, CTest
inventory validation and Python CI-script unit tests also pass. Graphical
comparisons and imported-scene evidence are recorded with the PR. Hardware A–J, normal-application DMX hold/Dimmer/Color/Pan/Tilt/
combined replay, graphics capture and before/after RTX viewport times remain the
acceptance gate. Leave the PR open until that evidence explains the Full/No-beams gap.
