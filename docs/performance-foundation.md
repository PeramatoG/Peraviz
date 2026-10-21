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
