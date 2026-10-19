# Native dense presentation state (milestone 1)

The main-thread presentation service in `native/src/presentation/` stores one
independent state per canonical physical renderer output. This is internal
Peraviz runtime data. It does not change MVR, GDTF, selected DMXMode, channel
ownership, geometry keys, or canonical output IDs. No grouping or batching is
implemented. The existing sectioned semantic visual-frame protocol remains the
input contract; the dense render-value buffer is a presentation boundary, not a
revival of the removed universal fixture row.

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
held values. Dirty, prepared-render, state and packed-output capacities are
bounded by physical-output count and reused after each snapshot. Clearing dirty
state visits only touched indices and does not release capacity.

Native composition preserves physical color gain for beam/spot energy and lens
emission, the existing perceptual wheel gain for beam intensity, and the existing
double intensity clamp around projected-output scaling. Signature filtering
publishes a mask and render-ready scalars. The adapter receives two reused
physical-output-sized packed arrays with a valid prefix count: index/mask pairs
and 12 render floats (dimmer, RGB, beam/spot energy, beam intensity, material
energy, half/full angles, physical gain, projected visibility). It releases its
shared packed views after application and before the next native write, avoiding
copy-on-write allocations proportional to output count.

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
and synchronize visibility. Renderer optics/topology initialization, gobo
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

## Trace contract

Trace OFF reads no presentation clocks or diagnostic size/counter payloads.
Trace ON adds `dense_presentation` to `[peraviz-stability]`:

| Field | Boundary / unit |
| --- | --- |
| `native_compose_us` | Interval total for native row fan-out, dirty tracking, gain/scaling, and render signature preparation |
| `semantic_payload_conversion_us` | Interval total for the preceding native semantic section-to-packed conversion |
| `payload_conversion_us` | Interval total for copying prepared native deltas into reused packed buffers, including any buffer detachment |
| `compatibility_adapter_us` | Interval inclusive adapter/apply time, including final object mutation |
| `renderer_mutation_us` | Interval subset spent applying each output's existing Godot objects/renderer methods; not GPU submission completion |
| `native_dirty_outputs` | Interval sum of unique dirty physical outputs per snapshot, before signature filtering |
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
These tests do not establish GPU visual equivalence on the canonical machine.

## Exact canonical Windows A/B

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
| FPS, no-beams | about 12 | Hardware run pending |
| apply CPU, no-beams | about 75–90 ms | Hardware run pending |
| emitter commit time, no-beams | 400,000+ us/second | Hardware run pending |
| outputs/snapshot | about 1,000–1,095 | Hardware run pending |
| FPS / pump Hz, transforms-only | 58–66 / about 60–65 | Hardware run pending |
| process_ms; pump_hz, no-beams/full; coalesced states | Record from matched baseline logs | Hardware run pending |
| native compose; payload conversion; adapter; mutation | Dense-stage fields unavailable on baseline | Hardware run pending |
| RX-to-apply p50/p95/max; GPU/viewport CPU; render setup | Record from matched baseline logs | Hardware run pending |

This environment can run native/headless correctness tests but cannot reproduce
the canonical Windows GPU/Art-Net workload. No before/after FPS or millisecond
improvement is claimed. No new measured remaining bottleneck is available yet.
If native composition is small but the compatibility adapter dominates, record
that result explicitly with these fields. It supports the next planned milestone:
batched aperture presentation with approximately 1,000 independently controlled
color/intensity outputs. Beam batching, new renderers and grouping remain separate
work. Rendering scalability is not established by this milestone.
