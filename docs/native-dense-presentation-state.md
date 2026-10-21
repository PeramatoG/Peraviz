# Native dense presentation state (milestone 1)

**Milestone 1 / performance foundation is stable.** The current roadmap, owner-reported
24–25 FPS reference and deferred scalability work are consolidated in
[performance foundation](performance-foundation.md). The native ownership details
below remain current; regression measurements and acceptance plans are historical.
Earlier mode runs were all full because user arguments were not consumed. They
do not establish a no-beams/transforms-only A/B. Compact-source aggregation is now implemented; independent-output batching remains open.

The main-thread presentation service in `native/src/presentation/` stores one
independent state per canonical physical renderer output. This is internal
Peraviz runtime data. It does not change MVR, GDTF, selected DMXMode, channel
ownership, geometry keys, or canonical output IDs. Compatible open Wash/Spot outputs now share dynamic presentation Control Groups;
physical state remains exact. Compact optical Render Emitter Groups now reduce shaft resources; independent-output batching is not implemented. The existing sectioned semantic visual-frame protocol remains the
input contract; the dense render-value buffer is a presentation boundary, not a
revival of the removed universal fixture row.

Control Groups prove immutable selected-mode authority. A separate native optical
classifier builds AGGREGATED/INDIVIDUAL Render Emitter Groups from retained
SceneModel geometry, reliable apertures and mechanical lineage. See the compact
[Render Group contract](rendering-performance-architecture.md#first-production-render-emitter-groups)
for thresholds, radiometric approximation, conservative fallbacks and diagnostics.

## Ownership and lifetime

`NativeRendererTargetRegistry.get_dense_presentation_bindings()` sorts canonical
numeric output IDs during setup and assigns indices `0..N-1`. It also binds
physical outputs with no scalar contributor. Static section/target-to-index
routes preserve canonical control fan-out; two equal colors never merge outputs.
Static native bindings contain IDs and projected photometric scales. Realtime
AoS state contains only numeric scalars, masks and previous render signatures.
The AoS keeps each output's values together for the dirty-output composition and
adapter-copy passes. This is an access-pattern choice, not a claimed hardware
benchmark advantage over SoA.

`FixtureLightApplyService` owns the `dense_presentation_adapter.gd` bridge; the
bridge owns `PeravizPresentationState`. It weakly references the service to avoid
a cycle. Each native installation/clear receives a process-unique generation.
Every update, compose and snapshot reset checks its generation. Scene/runtime
replacement clears native buffers, borrowed snapshots and all renderer handles.
Stale section-schema generations are rejected before adapter application.
Renderer/settings refreshes rebind objects and force a replay of native held
values without resetting semantic ownership or requiring fresh DMX. Gobo
callbacks rebind changed resources at their control boundary.

Native workers still never mutate scene nodes. The bounded DMX mailbox and
native semantic evaluation are unchanged.

## Snapshot work

Previously, `FixtureLightApplyService.apply_emitter_intensity_fast()` and
`apply_emitter_color_fast()` fetched target-record dictionaries and traversed
`beam_output_records`. Each output updated `_target_states` and allocated an
entry in `_snapshot_output_commits`. `end_visual_snapshot()` rediscovered the
fixture/output/state, composed gains, compared dictionary signatures, and
allocated per-output result dictionaries.

The installed dense path handles Intensity, Color and BeamOptics in one native
`compose()` call over the existing packed section buffers. Native immutable
integer routes fan out each semantic row; per-output access uses only dense
indices. The first update appends an index to a reserved dirty vector. Its
nonzero pending mask is the membership bit. Later updates OR masks and replace
held values. Physical state and dirty capacities remain bounded by physical-output count.
Render row and published packed capacities follow renderer-source count. Clearing dirty
state visits only touched indices and does not release capacity.

Native composition preserves physical color gain for beam/spot energy and lens
emission, the existing perceptual wheel gain for beam intensity, and the existing
double intensity clamp around projected-output scaling. `RenderGroupProjection` incrementally subtracts/adds changed POD member
contributions, mixes in linear light and emits one row per dirty renderer source.
The adapter receives one reused row-index/mask array and one 12-scalar array sized
to render rows, never physical outputs. There is one count and no duplicated
physical/control payload. Borrowed arrays are released before native writes;
no live slices, COW churn or per-member visibility visits are needed by aggregates.
Cached prepared lens RIDs are updated separately by main-thread native Godot glue
from exact physical values, including independent pixels, without physical lens
rows or SceneTree traversal. Core accumulation remains Godot-independent.

There is one fixed-shape result Dictionary per snapshot. No per-output result
Dictionary, pending commit Dictionary, target-state Dictionary, fixture UUID
lookup, output-record lookup, or emitter-array scan is required by normal dense
lighting composition/application. Invalid dense batches do not fall back to a
second state owner. Unresolved renderer control rows produce a bounded warning.

## Temporary renderer boundary and remaining allocations

Setup allocates native route maps/vectors, contiguous buffers, typed output,
light and material handles, and the existing renderer resources. The adapter
binds lights, light RIDs, beam nodes, materials, material RIDs, emission scales,
debug axes and renderer references once. It mutates existing light/material
properties and calls the existing beam renderer through `update_bound_intensity`.
Vector Prism and Lightweight Prism use bound beam resources for this entry.

Existing renderer parameter Dictionaries are retained as static binding objects
because the renderer API and gobo code still use them. Their scalar fields are
updated in place; they are not authoritative composition state or rebuilt for
each output. Cold gobo projector callbacks use a cached compatibility Dictionary
and delegate visibility to the same RID authority. Renderer optics/topology initialization, gobo
resource changes, and optional fog/shadow/proxy backends retain their existing
resource/metadata and diagnostic-result behavior. These operations are part of
the temporarily retained renderer, not a new beam implementation. Setup/rebind,
changed optics and lazy renderer initialization may allocate resources. The
existing sectioned-frame conversion and non-lighting section paths also retain
their current allocations. Constant-size snapshot/result payloads still allocate.

The compatibility helpers for direct legacy/test callers remain in the light
service, but production installs the dense owner before native playback. The
section applier explicitly bypasses those helpers for the three dense lighting
sections. Architecture checks guard that bypass. Delete the bridge, its bound
parameter objects and the obsolete dictionary commit helpers when milestone 2
replaces their corresponding presentation backend. Do not expand the legacy
helpers to support the dense path.

## Corrective renderer audit after 06a13f5

The supplied canonical Windows measurements exposed a severe regression, despite
bounded native composition: no-beams fell progressively from baseline ~12 FPS /
75–90 ms to ~2 FPS / 450–490 ms process time and >400 ms renderer setup CPU.
Full fell from the historically observed ~2–5 FPS to ~1–2 FPS / 700–800 ms
process time and ~700+ ms renderer setup. Transforms-only stayed around 54–58 FPS
(baseline 58–66 FPS / 60–65 pump Hz). GPU time remained tens of milliseconds.
These are user-supplied observations for 82 MVR fixtures, 71 live fixtures,
95 dimmer targets and 1,095 outputs on Godot 4.7.1 Forward+ / RTX 3070.
They are not measurements of this corrective candidate.

The [Godot 4.7.1 Node3D setter](https://github.com/godotengine/godot/blob/4.7.1-stable/scene/3d/node_3d.cpp#L1120)
returns immediately for equal values: merely repeating `visible = true` does not
prove renderer invalidation. A real transition does propagate visibility
notifications. [VisualInstance3D](https://github.com/godotengine/godot/blob/4.7.1-stable/scene/3d/visual_instance_3d.cpp#L48)
then writes instance visibility before emitting the Node signal. Thus the old
blackout/active Node transition could reactivate a light whose separate RID cache
still said false, suppressing the correcting RID write. The old projector-required
policy could also enable lights in no-beams. This establishes concrete correctness
bugs, not a quantitative attribution of all the measured renderer setup cost.

The dense adapter now owns SpotLight RID visibility, including cold gobo helpers.
During full playback, the light Node stays structurally visible for its beam
children; DMX blackout/color/intensity never changes that Node property. Entering
no-beams or transforms-only hides beam/debug children and the light Node once,
then disables its RID. Hiding the structural Node also prevents Godot's
`NOTIFICATION_TRANSFORM_CHANGED` handler from forwarding ancestor transforms to
suppressed light instances (`_is_vi_visible()` in VisualInstance3D). Returning
full restores held native state without a new DMX packet. Node visibility/tree
signals repair a conflicting Godot RID write immediately; ordinary playback uses
only the guarded RID setter. Binding and explicit renderer refresh are replay
boundaries. Scene clear disconnects callbacks and breaks their handle references.

MeshInstance beams and debug axes use their own guarded Node visibility setters.
Both prism bound paths cache only effective applied dynamic values in one typed,
resource-bound presentation signature; equal values return `INTENSITY_UNCHANGED`.
Hidden beams do not receive color/intensity shader writes. Legacy response uniforms
are updated only when their effective response changes; vector color/intensity
remains packed. Cold intensity entry points share the same applied cache. Optics
and resource replacement invalidate it explicitly and remain separate operations.

After no-beams transition cleanup, changing DMX snapshots compose native state and
update changed emissive aperture values only. They do not update light properties,
visibility, beam uniforms, optics, or projector callbacks. Gobo selection and motion
references are retained while renderer application/local motion are suppressed;
returning full rehydrates the latest selection and current phase. Diagnostic mode
is applied before dense binding, including a transforms-only launch. Material color
and emission energy have independent effective-value guards, including replay.

## Trace contract

Trace OFF reads no presentation clocks or diagnostic size/counter payloads.
Actual renderer API calls update only constant-size aggregate bookkeeping;
trace dictionaries and interval reporting are enabled only by the trace flag.
Trace ON adds `dense_presentation` to `[peraviz-stability]`:

| Field | Boundary / unit |
| --- | --- |
| `native_compose_us` | Interval total for native row fan-out, dirty tracking, gain/scaling, and render signature preparation |
| `semantic_payload_conversion_us` | Interval total for the preceding native semantic section-to-packed conversion |
| `payload_conversion_us` | Interval total for copying prepared native deltas into reused packed buffers, including any buffer detachment |
| `compatibility_adapter_us` | Interval inclusive adapter/apply time, including final object mutation |
| `renderer_mutation_us` | Interval total of cached native lens RID updates plus the Godot shaft/light mutation loop; not GPU submission completion |
| `native_material_us` | Native main-thread lens RID mutation time, already included in renderer mutation time |
| `native_dirty_outputs` | Interval sum of unique dirty physical outputs per snapshot, before signature filtering |
| `spot_node_visibility_writes`, `spot_rid_visibility_writes` | Interval actual adapter Node/RID visibility setter calls, separately counted; Godot-internal inherited notifications are not API calls by the adapter |
| `beam_visibility_writes`, `debug_axis_visibility_writes` | Interval actual beam/debug Node visibility setter calls |
| `beam_shader_parameter_writes` | Interval actual beam instance/material shader setters through retained renderer/proxy helpers, including optics and initialization |
| `material_parameter_writes` | Interval actual aperture emission color/energy RenderingServer setter calls |
| `renderer_outputs_processed`, `renderer_outputs_changed`, `renderer_outputs_unchanged` | Emitted shaft-row visits versus rows causing Godot mutations; native no-ops emit zero rows, while native lens writes have separate actual counters |
| `forced_replays`, `mode_transition_replays` | Explicit renderer/settings and diagnostic-mode replay counts |
| `visibility_resyncs`, `projector_refresh_calls`, `optics_apply_calls`, `beam_initializations`, `spot_property_writes` | Auxiliary interval boundary and mutation counts |
| `last_dirty_outputs` | Unique dirty physical outputs in the latest traced snapshot |
| `physical_outputs`, `state_capacity`, `dirty_capacity` | Current generation counts/capacities |
| `dirty_high_water` | Exact generation dirty-list peak |
| `native_buffer_bytes` | Retained native bindings, raw/previous state, dirty indices and prepared deltas; excludes immutable route-map allocator overhead |
| `packed_buffer_bytes` | Fixed packed adapter-buffer storage |

The trace sampler resets interval stage counters only at the report boundary;
size queries do not retain history. `emitter_commits`, coalesced candidates,
signature skips, physical outputs considered and `emitter_commit_us` remain
comparable. Renderer submission/setup, viewport CPU and GPU remain the existing
RenderingServer measurements. Adapter/mutation times are nested and must not be
added together or equated with GPU time. Native semantic evaluation remains a
separate preceding stage.

## Deterministic validation

`peraviz_native_dense_presentation_tests` covers dense identity, generation
replacement, dirty deduplication/masks, latest values, signature no-ops, reset,
renderer replay, duplicate-ID rejection, malformed-batch rejection, representative
physical/perceptual gain parity, and 1,095 independent color/intensity outputs
through 400 snapshots. It checks stable capacities and uses an allocation probe
to reject any warmed native snapshot allocation. It has no timing threshold.
The headless adapter test exercises the section applier with empty UUID maps,
checks legacy dictionary state remains empty, verifies light/beam/zoom behavior,
replays renderer state, rejects stale schemas, and checks fixed bridge capacities.
`test_dense_renderer_mutations.gd` separately installs 1,095 independent outputs,
checks identical replay has zero visibility/shader/material writes, changes one
output independently, runs 30 changing no-beams snapshots, restores full without
fresh DMX, checks transforms-only suppression and a real Node notification repair,
and verifies both bound prism implementations return UNCHANGED. It also checks
cold/bound cache agreement and fixed capacities. The gobo lifecycle test checks
suppressed motion leaves transform/uniform state untouched and resumes at the
current phase. Headless notification and instrumented-setter tests cannot query
actual GPU culling state or establish visual/performance equivalence on Windows.

## Historical canonical Windows A/B plan

Use the same `testSENTIDOS(2).pvz` MVR/reference scene, grandMA3 chase, camera,
window/resolution, Forward+, RTX 3070, Vector Gobo Prism, visual settings,
V-Sync/frame cap, Release build configuration and driver for both revisions.
Record commit, engine and driver versions. Build and run each revision separately;
close each process before changing revision or mode. Baseline is
`bd354a5635174855e0537347230d93eb52e4bd1e`; the candidate is the reviewed dense
presentation commit. Use a fresh process for each run and repeat in reverse order.

From PowerShell, with the configured `cmake --preset windows-release-static` toolchain:

```powershell
Set-Location C:\codigoscpp\peraviz
$godot = 'C:\Tools\Godot_v4.7.1-stable_win64.exe'
& $godot --version
Push-Location native
cmake --preset windows-release-static
cmake --build --preset windows-release-static
Pop-Location
New-Item -ItemType Directory -Force .\logs | Out-Null

# Set to 'before' or 'after' for the checked-out revision.
$label = 'after'
foreach ($mode in @('no-beams', 'transforms-only', 'full')) {
    & $godot --path C:\codigoscpp\peraviz --print-fps --log-file ".\logs\dense-$label-off-$mode.log" -- --peraviz-render-diagnostic=$mode
    & $godot --path C:\codigoscpp\peraviz --print-fps --log-file ".\logs\dense-$label-on-$mode.log" -- --peraviz-perf-trace --peraviz-render-diagnostic=$mode
}
```

The baseline does not contain dense-stage fields; mark those **unavailable**.
For each fresh process load the reference project, confirm about 71 live
fixtures/95 Dimmer targets/1,095 physical outputs/three relevant universes, settle
with static Art-Net for 60 seconds, then run the identical chase for ten minutes.
Retain early, minute-5 and minute-10 samples. Follow the lifecycle checks in
[live latency diagnostics](live-render-latency-diagnostics.md): stop/restart DMX,
reload the scene, change presentation and return. Confirm state/buffer sizes
settle and independently controlled outputs remain independent.

| Metric | Supplied baseline observation | Candidate measurement |
| --- | --- | --- |
| FPS, no-beams | about 12 | Not established in that investigation |
| apply CPU, no-beams | about 75–90 ms | Not established in that investigation |
| emitter commit time, no-beams | 400,000+ us/second | Not established in that investigation |
| outputs/snapshot | about 1,000–1,095 | Not established in that investigation |
| FPS / pump Hz, transforms-only | 58–66 / about 60–65 | Not established in that investigation |
| process_ms; pump_hz, no-beams/full; coalesced states | Record from matched baseline logs | Not established in that investigation |
| native compose; payload conversion; adapter; mutation | Dense-stage fields unavailable on baseline | Not established in that investigation |
| RX-to-apply p50/p95/max; GPU/viewport CPU; render setup | Record from matched baseline logs | Not established in that investigation |

This archived plan predates foundation closure. PR #100 has merged; the current
owner-reported full result is stable at 24–25 FPS. The corrected application
argument boundary still needs new mode-specific hardware measurements. Use the
[current acceptance sequence](performance-foundation.md#exact-windows-acceptance-commands)
and its explicit startup diagnostics rather than treating historical rows as a
valid A/B. Native/headless results do not establish Windows GPU performance.
Independent-output batching remains deferred; the first compact-source optical
aggregation is now implemented without MultiMesh or worker threads.

### Deferred performance acceptance commands (corrected argument syntax)

Historical command set, with syntax corrected. The current acceptance order is
maintained in performance-foundation.md:

```powershell
$godot = "C:\Users\Peramato\Desktop\Programas\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=no-beams
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=transforms-only
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=full
```

Record FPS, process/setup CPU, GPU, pump rate, native composition, actual mutation
counts and stable capacities over sustained playback, plus trace-off comparison.
Repeat full -> no-beams -> full without new DMX and renderer/settings refresh.
No wall-clock CI threshold substitutes for this test. Milestone 2 is outside this
corrective pass.
