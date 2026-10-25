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
Current execution remains serial, with no per-attribute locks or Godot workers.

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
scratch; a general scheduler and broader immutable binding-template sharing remain
subsequent work.

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
