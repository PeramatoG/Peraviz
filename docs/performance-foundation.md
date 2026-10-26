# Performance foundation: stable; scalability remains open

**Status: PERFORMANCE FOUNDATION STABLE — 19 October 2026.**

This closes the performance-foundation milestone, not performance work. Native
dense state, bounded dirty tracking and guarded renderer compatibility mutations
provide a stable base for later rendering changes. Vector Gobo Prism remains the
reference renderer. The subsequent shared dynamic Control Group correction is documented in
[rendering-performance architecture](rendering-performance-architecture.md);
this historical closure implements none of the visual follow-ups below.

Latest owner evidence after PR #105: 82 fixtures, 1,095 canonical physical outputs,
20 actual aggregate shafts for 1,000 compact Wash emitters, 115 renderer rows and
approximately 40 FPS during active Color (previously approximately 23 FPS).
Loading work and its bounded synthetic comparison are recorded in
[setup measurements](rendering-performance-architecture.md#scene-setup-and-loading).

## Compiled Evaluation Graph, phase 1

The production serial evaluator now uses `CompiledEvaluationPlan`: relevant DMX
offset → source handle → existing property/Color/wheel consumer or gobo layer.
Master edges reach gobo consumers even when the dependent bytes are unchanged.
`EvaluationWorkspace` owns cached numeric source results and generation-stamped
activation results; it owns no canonical physical output state. Setup hashes and
adjacency builders are released after compaction. Source/consumer work lists and
optical target ordering retain deterministic domain visitation.

Identical selected-mode scalar mappings share immutable definitions keyed by exact
mapping content, source layout and selected-mode identity. The pool is scene-local;
content changes or scene replacement cannot retain an old definition. Patches,
component/Beam identities, diagnostics, activation and temporal state remain local.
The existing GDTF template compiler continues to own shared parsed definitions.
Whole instance binding graphs are not interned across patches: their numeric target
routes remain scene-specific. This phase shares the safe scalar mapping unit and
borrowed gobo definition views instead of changing setup serialization.

Properties retain existing declaration-order range arbitration and weighted
contributors; Color and wheels retain their established input/range semantics.
Gobo activation uses the existing cycle-safe ModeMaster evaluator, now once per
shared source context/update. Physical gobo scalar interpretation is shared with
the reference entry point; held phase and velocity ownership are unchanged.
This optimization adds no GDTF capability. In particular, it does not introduce
ModeMaster interpretation into additional domains, Relations or new optical effects.
Ordered wheel composition uses exact target-local setup indexes rather than scanning
unrelated wheels. The PR #108 direct native presentation boundary remains unchanged.

Plans expose dense source/cache ranges and explicit consumer/target ownership for a
future native partitioner. Shared source dependencies must complete before their
consumers, target writers must own exclusive ranges, ordered optical composition
must remain deterministic, and all tasks must join before compact publication.
The serial reference remains available; the adaptive extension below uses these ownership boundaries without per-source locks or Godot workers.

### Bounded reference comparison

The existing 1,000-output native workload now represents 20 × 50 distinct physical
properties sharing controls, or 1,000 independently patched Dimmer/RGB/Zoom sources.
Both retain one selected-mode mapping layout and five shared scalar definitions.
A temporary build of the evaluator from merged PR #108 (`6ae6e2c`) ran the same
96-update deterministic sequence, followed by 32 single-source sparse updates.
Reference code stays outside the production tree. Both runs used Linux Debug,
identical inputs and opt-in tracing; numbers below are summed CPU microseconds.

| Metric | Shared-control compact source | Independent emitters |
| --- | --- | --- |
| Fixture instances / distinct selected-mode source layouts | 20 / 1 | 1,000 / 1 |
| Source nodes / consumers / dependencies | 100 / 3,000 / 5,100 | 5,000 / 3,000 / 10,000 |
| Shared immutable scalar definitions | 5 | 5 |
| Actual source evaluations, 96 updates (before → graph) | 239,950 → 4,799 | 239,980 → 239,980 |
| Actual source evaluations, 32 sparse updates (before → graph) | 1,600 → 32 | 32 → 32 |
| Native evaluation CPU, 96 updates (µs, before → graph) | 181,711 → 118,091 | 286,349 → 196,542 |
| Native evaluation CPU, 32 sparse updates (µs, before → graph) | 1,273 → 1,034 | 163 → 163 |
| Consumers avoided, sparse submitted universes | 94,400 | 7,648 |
| Dirty physical outputs / renderer rows per full update | 1,000 / 20 | 1,000 / 1,000 |
| Produced renderer rows, 96 updates including forced replay | 980 | 49,000 |
| Retained graph / workspace buffer bytes | 96,296 / 17,900 | 325,000 / 160,000 |
| Correctness failures | 0 | 0 |

Source/consumer counts refer to existing semantic programs and optical layers,
not a new node per physical member downstream of a shared route. Avoided-consumer
counters count unvisited consumers within submitted universes; untouched universes
are skipped separately. Plan/workspace byte counts cover retained contiguous graph,
shared mapping and cache/work-list buffers. They exclude existing domain records,
binding-handle vectors, container/control-block overhead and Godot resources; they
are not process RSS or net memory savings. Setup scratch is retired.

The comparison checks exact canonical identities, masks, dirty order, numeric
physical values and render deltas; the same reference/graph workload digests match.
Additional focused tests cover changed masters, activation/deactivation, shared
activation caching, independent patches, content/mode separation, invalid/cyclic
edges, no-change suppression and retirement. Existing native regressions retain
multi-byte/weighted/calibrated Color and gobo temporal coverage. The existing Godot
render-group test exercises actual compact/independent output resources and replay.

These are bounded synthetic CPU observations, not a Windows/GPU or FPS measurement.
Small sparse timings are close to clock/scheduling noise. No timing threshold is
asserted in CI. Existing core trace adds `source_programs_evaluated`,
`source_cache_hits`, `activation_programs_evaluated`, `activation_cache_hits`,
`evaluation_consumers_scheduled` and `evaluation_consumers_avoided`; state-size
sampling reports `evaluation_*` plan counts and bytes. Normal playback keeps
tracing off. Pending semantic row and transform staging still use existing serial
scratch; broader immutable binding-template sharing remains subsequent work.

## Adaptive native parallel evaluation

After merged PR #109 the owner observed approximately **75 FPS with active DMX**
on the existing Windows workload. This may be V-Sync limited and establishes no
unbounded scalability claim. The 82-fixture / 1,095-output / 20 aggregate Wash shafts /
115-row reference topology is unchanged.

Production selects a native asynchronous coordinator for sufficiently independent
non-gobo graphs (initial eligibility: at least 3,072 sources and 512 Color targets).
Shared-control graphs retain cached serial work. Hardware capacity respects process
affinity and Linux cgroup quota, reserves three CPUs for main/render/coordinator
activity and caps reusable workers at four. Fewer than two available workers keeps
the original synchronous serial path. These are conservative admission bounds,
not an optimal worker-count claim. Eligible phases additionally consider dirty
work, estimated useful kernel cost and observed dispatch cost. Whole-evaluation
serial probes compare native commit cost; slower parallel observations trigger a
bounded serial cooldown, with periodic rechecks and baseline refresh. Small/sparse
updates run serially on the coordinator without worker dispatch.

Eligible pure batches evaluate source programs and exact Color input/resource
cooking; no-wheel final Color normalization also runs in exclusive target slots.
Shared sources are decoded once before their consumers. The coordinator retains
ModeMaster resolution, weighted/range arbitration, all canonical maps, transforms,
ordered optical layers, physical composition and Render Group reduction. Gobo
scenes remain fully serial, preserving temporal transitions and held phase without
adding another mailbox between those transitions and their evaluator. No supported
GDTF capability or aggregation rule changes.

`PERAVIZ_NATIVE_EVALUATION=serial|parallel|auto` is sampled at renderer installation;
`parallel` is an explicit diagnostic override (two workers), not the default and
still excludes gobo scenes. Opt-in existing performance tracing reports task count,
workers used, actual aggregate worker CPU, task wall, coordination residual,
serial fallback/probe/backoff, native evaluation/physical/reduction wall, main-thread
publication, completed and consumed latency. Worker CPU overlaps wall time and
must not be added to it. Coordinator residual includes scheduling/preemption, not
just lock overhead. State sizes expose scratch, input/snapshot banks, derived display
cache and worker capacity separately; estimates exclude platform thread stacks,
container overhead and Godot allocations. There is no per-scalar timing.

Run `peraviz_native_visual_runtime_tests --parallel-pipeline` for the bounded exact
comparison and ownership/lifecycle checks. It uses 20 deterministic updates with
full, unchanged and sparse input, calibrated Color, duplicate targets within/across
universes and ordered wheel layers. It also holds workers behind a test gate,
injects a recoverable pure-kernel exception, coalesces unrelated universe packets,
checks automatic serial probes plus actual parallel dispatch, and cancels/reloads
while workers are active. Existing gobo ModeMaster/continuous-rotation tests run in
the same focused command. The existing Godot render-group integration test forces
the production async path for independent emitters, polls without new packets and
replaces the renderer with held input. No FPS or timing threshold is asserted.

The local runner has a two-CPU quota. Forced parallel measurements therefore do
not establish a wall-time gain, and automatic policy keeps this host serial.
Linux Release, 20-update deterministic sequence (summed microseconds, opt-in
trace, forced two workers; shared case includes one intentional failure/retry):

| Metric | Small serial | Shared-control forced | Independent forced |
| --- | ---: | ---: | ---: |
| Serial evaluation wall | 21 | 3,705 | 4,683 |
| Parallel evaluation wall | — | 4,910 | 4,793 |
| Native physical + reduction wall | 3 | 1,028 | 889 |
| Aggregate worker CPU | 0 | 1,348 | 1,772 |
| Coordination residual wall | 0 | 445 | 632 |
| Actual parallel tasks / serial updates | 0 / 20 | 40 / 10 | 40 / 10 |
| Produced dirty physical / render rows | 20 / 20 | 10,250 / 205 | 10,005 / 10,005 |
| Snapshot buffers / worker scratch bytes | 0 / 0 | 138,536 / 177,956 | 272,296 / 457,128 |

A separate headless Godot Debug integration sample published two 1,000-row
independent snapshots with six actual parallel tasks: 290 µs summed native
main-thread publication, 6,468 µs background evaluation, 1,769 µs physical
composition, 581 µs reduction and 959 µs aggregate worker CPU. Task wall was 660 µs
(two-worker phase capacity: 1,320 µs; approximately 73% CPU utilization during
those phases). One post-activation submission recorded 2,429 µs completion and
8,857 µs consumption latency; the initial already-held batch has no submission
latency timestamp. These separately collected Debug/Release samples must not be
combined into a total. Other repeated forced runs varied around parity on this
quota-limited host. They establish exact useful native work and offloading, not a
scalability/FPS improvement. Windows GPU/DMX validation is still required. The supported subset is useful CPU parallelism in the production
path, while optical map commits and reduction remain ordered native work.

## Independent emitter render application, phase 1

This delivers native **CPU renderer-apply batching**, not GPU instancing. The
Godot 4.7 API exposes `RenderingServer.multimesh_set_buffer(RID, PackedFloat32Array)`
for contiguous transforms/colors/custom data. MultiMesh's shared visibility bounds
lack individual spatial culling, and its per-instance color/custom data cannot
replace all the current Vector Prism instance uniforms unchanged (profile, cone,
attenuation and optical resources). A faithful GPU path would need a shader/data
contract and optical/spatial partitioning with independent transform ownership.
This phase keeps exact existing geometry, shader, transparent blending/sorting and
per-node culling, and moves the costly independent dynamic apply loop into native
main-thread code. MultiMesh is not enabled and no draw-call reduction is claimed.
See [MultiMesh's documented limits](https://docs.godotengine.org/en/stable/classes/class_multimesh.html).

The existing generated production-import workload runs 1,000 independently patched
Dimmer/RGB emitters, with six measured warm updates after resource initialization.
Every primary changes per pixel and Dimmer varies independently. Blackout/restore,
actual instance uniforms, mesh/local transform identity, inherited transforms,
diagnostic replay, renderer replacement and weak-resource retirement are checked.
A small synchronous native-boundary probe checks generation rejection, exact
non-integer presentation scaling and freed-handle fallback. Grouped-source and
project-loading regressions remain in existing tests. No new benchmark framework
or hardware threshold is added.

One sequential Linux Debug / Godot 4.7.1 headless comparison, same deterministic
sequence and PR #110 async evaluator in both runs. The reference uses
`PERAVIZ_NATIVE_BEAM_APPLY=0`; normal production enables cold-compatible batches.
Times below sum **six** updates, except scene setup (one import each).

| Metric | Reference script loop | Native batch |
| --- | ---: | ---: |
| Canonical physical outputs / renderer rows / shaft nodes | 1,000 / 1,000 / 1,000 | 1,000 / 1,000 / 1,000 |
| GDScript apply/handle loop, inclusive CPU µs | 54,474 | 46 |
| Renderer mutation pass, inclusive CPU µs | 54,639 | 1,658 |
| Native beam apply CPU µs | 36 (fallback nomination) | 1,503 |
| Native payload packing/transfer CPU µs | 507 | 523 |
| Native main-thread publication CPU µs | 734 | 2,175 |
| Actual dynamic uniform writes / topology rebuilds | 6,000 / 0 | 6,000 / 0 |
| Changed / unchanged renderer outputs in measured updates | 6,000 / 0 | 6,000 / 0 |
| Native-handled / script fallback rows | 0 / 6,000 | 6,000 / 0 |
| Render payload / binding+fallback table bytes | 56,000 / 4,000 | 56,000 / 44,000 |
| Scene setup elapsed µs | 1,898,733 | 1,919,873 |
| Draw calls / GPU frame time | unavailable (dummy renderer) | unavailable (dummy renderer) |
| Native handles after scene teardown | 0 | 0 |

Timers are inclusive: mutation time includes native beam/material work plus the
script mutation loop. Native publication includes beam apply, lens apply and
packing. Do not add overlapping columns. The difference establishes lower CPU
script/property/handle overhead, not fewer engine uniform calls. Godot API call
cost is not isolated from native iteration; actual calls are counted separately.
Render submission/draw and transparent fragment costs cannot be measured with the
dummy renderer; resource topology and shader work are unchanged. These are bounded
headless observations, not Windows/GPU/FPS evidence. Setup includes loading and
frame-budget yields and establishes no setup improvement. Cache bytes exclude
engine wrapper/container overhead, not RSS. Held/no-new-input updates publish no
changed rows; no-beams/full replay and exact fallback remain covered.

The following milestone changes compact aggregate-member allocation only;
independent emitter resources and the native apply comparison above are unchanged.

## Lazy aggregate member shafts

Accepted standard open Vector Prism groups now defer member shaft nodes and
materials. Setup uses a renderer identity/revision/shader/priority description
rather than temporary full resources. Native membership, projected output,
mechanical anchor, optical/resource exclusions and exact Zoom authority still gate
final acceptance. Unsupported/custom resources remain eager and use the reliable
individual fallback. Physical identities, lenses and Control Groups survive with
no shaft resource; no GDTF interpretation, shader or native evaluation changes.

The existing generated test covers 50 compatible members (plus an unrelated Glow),
1,000 aggregate members, and 1,000 independent Dimmer/RGB emitters using #111's
native apply path. It checks actual missing shaft children and creation counters,
not just visibility. Configured realtime fallback creates 1,000 individuals from
held native values; re-aggregation frees them and repairs canonical/semantic
resource views. Actual Legacy → Vector Prism replacement, diagnostic replay,
scene reload and teardown remain covered. No stream packet is required for cold
rehydration. Import-budget cancellation gates remain before final publication.

One sequential Linux Debug / Godot 4.7.1 headless comparison, identical generated
1,000-member workload. `PERAVIZ_LAZY_AGGREGATE_SHAFTS=0` selects the retained eager
reference at setup/control boundaries. Timings include frame-budget yields and
are observations, not CI thresholds or a Windows/GPU/FPS claim.

| Metric | Eager reference | Lazy default |
| --- | ---: | ---: |
| Canonical physical outputs / aggregate groups / members | 1,000 / 20 / 1,000 | 1,000 / 20 / 1,000 |
| Actually allocated member shaft nodes | 1,000 | 0 |
| Actually allocated aggregate shaft nodes | 20 | 20 |
| Individual node/material constructions during setup | 1,000 | 0 |
| Unique attached shaft materials, active | 40 | 20 |
| Unique attached shaft mesh resources, active | 1 | 1 |
| Nominal attached position/index array bytes, active | 2,592 | 2,592 |
| Scene setup elapsed µs | 1,804,323 | 1,742,813 |
| Registry target setup ms | 328.871 | 310.983 |
| Aggregate/material binding ms | 47.051 | 48.504 |
| Layout/resource/control binding CPU µs (subset of previous row) | 21,194 | 25,732 |
| Individuals rehydrated / retired in forced fallback cycle | 0 / 0 | 1,000 / 1,000 |
| Member nodes allocated again after re-acceptance | 1,000 | 0 |

The material count includes attached member/aggregate overrides, including shared
Control Group materials, and excludes the renderer template and physical lens
materials. Meshes may share cached normalized geometry; removing member nodes does
not imply freeing cached mesh buffers. The byte estimate counts nominal float32
positions and uint32 indices exposed by attached ArrayMesh surfaces. It excludes
normals/UVs/compression, unbound provider caches, nodes, material/shader overhead,
CPU wrappers and driver/GPU allocations; it is neither RSS nor total graphics
memory. No invented per-node/material byte saving is reported. Event counters
count real renderer construction/rehydration/immediate aggregate retirement since
scene reset, not inferred row counts or arbitrary external node destruction.

The deterministic saving is 1,000 unnecessary shaft-node allocations and their
initial material duplication. Overall setup improved modestly in this sample;
resource binding itself became slightly slower. Draw/GPU/fragment performance was
not measured by the dummy renderer. The 82-fixture owner's canonical 1,095 outputs
and 115 render rows retain their existing semantics; one normal Windows GPU/DMX
validation follows full CI. True GPU instancing remains a subsequent milestone.

## Foundation reference evidence (before Render Groups)

The owner reports approximately **24–25 FPS / 40–42 ms per frame after warmup**,
stable for several minutes in normal full presentation. The previous progressive
collapse toward 2–3 FPS did not recur, and live interaction felt substantially
more responsive. This is the current reference result, **not the final performance
target** and not evidence that rendering scalability is solved.

The matched machine/workload is Windows, Godot 4.7.1 stable, Vulkan Forward+,
RTX 3070, V-Sync enabled, the reference MVR and grandMA3 live chase: 82 MVR
fixtures, 71 live renderer fixtures, 95 Dimmer targets, 1,095 physical outputs,
1,055 color outputs and maximum fan-out 51. These are owner-supplied observations,
not measurements made in CI or this Linux/headless environment.

Earlier full/no-beams/transforms-only commands using application arguments after
`--` were not consumed by the controller, which read engine arguments instead.
Those runs all used full presentation and **are not a diagnostic-mode A/B**.
Separately, the older `832882d` Windows runs with script compilation failures
remain invalid performance measurements. Preserve both investigations as history;
neither establishes current no-beams or transforms-only performance.

## One current roadmap

Completed / stable foundation:

- Bounded latest-state DMX mailbox and coalescing.
- Sustained-playback stability investigation and removal of progressive collapse.
- Native dense physical-output state, stable indices, generation safety and
  bounded dirty tracking.
- Guarded renderer mutations, held-state restoration and actual mutation counts.
- Cold-cache/runtime correctness, tested diagnostic modes and explicit resource
  retirement during scene replacement and application exit.

Newer owner-controlled Windows measurements (~24 FPS all effects, ~46 with Color
stopped, ~75 with Color/Wash Dimmer stopped while Pan/Tilt continues) establish
dynamic Color/Dimmer presentation fan-out as the immediate bottleneck. The shared Control Group branch alone produced no appreciable owner-measured FPS
improvement. Exact-output fallback auditing and first compact-source AGGREGATED /
INDIVIDUAL Render Emitter Groups now target actual transparent shaft count.
MultiMesh, broader RenderEmitterGrouping, independent-output batching, LOD and
renderer replacement remain future work. The historical
foundation closure itself did not implement these changes.

The first batching benchmark must sustain about **1,000 genuinely independent
color/intensity outputs**. Grouping cannot substitute for that result. Every
physical GDTF output remains known internally:

```text
GDTF/MVR canonical physical semantics != renderer object count
```

Future aggregation is Peraviz presentation logic; it must preserve selected
DMXMode/control topology and independent identities. Equal instantaneous RGB is
never sufficient to merge outputs. Detailed future proposals remain in
[rendering-performance architecture](rendering-performance-architecture.md).
Historical "Phase A2" numbering identifies an investigation, not a competing
current milestone order.

## Application argument and mode contract

Use **`godot [engine arguments] -- [Peraviz arguments]`**.
`application_arguments.gd` is the only production command-line reader. User args
are authoritative. Engine-side Peraviz trace/mode flags are deliberately ignored
with a warning; there is no silent compatibility fallback. With repeated user
mode flags the last value wins, with a warning. An unknown mode warns and selects
full. Defaults are full and trace off.

Any explicit mode or trace flag emits exactly one controller startup line:

```text
[peraviz-diagnostic] perf_trace=true render_mode=no-beams
```

| Mode | Transform/control path | Aperture emission | Shafts | Real/projector lights and local gobo rendering |
| --- | --- | --- | --- | --- |
| full | Applied | Applied | Applied | Normal supported presentation |
| no-beams | Applied | Changed held values applied | Suppressed | Suppressed |
| transforms-only | Applied | Suppressed | Suppressed | Suppressed |

Diagnostic policy never edits saved Visual Settings or native/GDTF semantics.
Native dense composition can continue holding lighting values in suppressed modes.
Transitions perform one cleanup/replay; full restores current held state without
fresh DMX. Transforms-only explicitly zeros aperture emission at its boundary.

## Current telemetry

`[peraviz-perf]` reports FPS, process/render inventory, transport/pump/row outcomes,
`output_visits` (interval visits, not physical scene count), and current visible
beam/light gauges. `[peraviz-presentation]` names `beam_renderer` (0 volumetric,
1 legacy) and `beam_presentation` (0 fog, 1 vector, 2 native shadow, 3 proxy)
separately from the diagnostic mode. Both sample visibility from the dense owner **before**
printing the same report, rather than reading stale zeroed legacy sets.

`[peraviz-stability]` retains current mode, dense-active status, physical-output
count, dirty count/capacity, native composition, payload/compatibility/mutation
costs, actual setter counts, initialization/rebind/mesh-replacement counts,
CPU/GPU frame information, bounded sizes, latency intervals, and mailbox/coalescing.
The dense block also names its diagnostic mode. Legacy compatibility collection
sizes and their snapshot peak live under an explicit `legacy_compatibility`
category, marked inactive for production dense playback. Old `beam_full*` and
broad-helper topology counts no longer masquerade as production renderer work.
Useful initialization and genuine mesh changes remain in dense telemetry.
Boundary/cache events are counted separately from actual renderer mutation results,
and renderer lifetime counters are baselined at each scene binding. Dense setter
counts cover the adapter/compatibility-renderer calls, not all internal Godot work.
Latency triples and their explicit interval/lifetime names are in stability JSON,
not duplicated in the compact line. See [live diagnostics](live-render-latency-diagnostics.md).

## Active visual follow-ups — record only

1. One optical/geometry source for shaft and footprint centerline, orientation,
   Zoom and gobo transform. Current alignment can drift during optics changes;
   camera movement can reveal the mismatch.
2. Surface footprints for all projected outputs, including open spots and washes.
3. Independent user control of shaft and footprint/surface strength, or both.
4. A softer continuous radial profile instead of visible concentric hard layers.
5. Plausible longitudinal attenuation along beam distance.
6. Audit which Visual Settings affect Vector Gobo Prism, which are obsolete or
   ineffective, and which controls are missing.
7. Keep Shared Haze and experimental proxy modes secondary until Vector Gobo
   Prism has a coherent, stable visual contract.

The owner's qualitative comparison with grandMA3 on the same workstation found
its simpler presentation smoother at about 60 FPS, with less discretized edges
and gradients. Peraviz white/gobo shafts appear layered, overlapping white shafts
can become overbright, and dynamic footprint alignment remains inconsistent.
These observations motivate later work only: no pixel-matching requirement or
claim about grandMA3's architecture, aggregation, settings or approximations is
supported by that comparison.

## Exact Windows acceptance commands

```powershell
$godot = "C:\Users\Peramato\Desktop\Programas\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-render-diagnostic=full

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=full

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=no-beams

& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=transforms-only
```

The startup line must name each requested mode/trace value. Full shows shafts;
no-beams preserves aperture emission while suppressing shafts/lights;
transforms-only suppresses lighting. Identical visual behavior across all three
fails acceptance. Compare settled runs with the same scene/chase/camera/settings,
and distinguish trace-off product behavior from trace-on diagnostics. No new
mode-specific FPS target or result is claimed here.

Clean-cache/CLI/lifecycle verification is run by:

```bash
python3 .github/scripts/check_clean_runtime.py --godot "$GODOT_BIN" --project . --output /tmp/peraviz-clean-runtime
```

This uses pinned Godot 4.7.1, removes the project's generated cache for the test,
then exercises normal startup, both prism lifecycles, nine real command-line
cases and negative installation/initialization contracts. Exit ObjectDB warnings
fail the checker. See the [closure ownership audit](performance-foundation-ownership.md).
