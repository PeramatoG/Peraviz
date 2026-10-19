# Live render latency diagnostics

## Measurement boundary

`--peraviz-perf-trace` emits one compact `[peraviz-perf]` line approximately once per second. `rx_apply_us` measures relevant ArtDmx receipt through completion of Godot scene/resource mutation on the CPU. It does not include render submission, GPU execution, frame queueing, or display presentation. `pump_hz` counts production pumps from the render `_process` path; the 125 ms status refresh only updates UI.

Tracing is explicitly opt-in. Use `godot --path .` for the production baseline and `godot --path . -- --peraviz-perf-trace` for a diagnostic benchmark. Trace-off avoids rich row categorization, per-row clocks, native stats payloads, and presentation SceneTree sampling. Compare settled runs because trace-on accounting still has measurable cost.

With tracing disabled, playback performs no `Performance` monitor reads, trace formatting, interval diagnostic retention, per-row result dictionaries for Transform/Intensity/Color, renderer-counter mutation, or per-frame deep diagnostic copy. The one-time bootstrap diagnostic remains. Enabling tracing retains interval row/timing summaries, snapshots cumulative counters once per applied frame, reads Godot monitors, and formats only at the one-second report boundary. Viewport render-time measurement is enabled only for tracing and disabled when its trace owner is released.

## Trace fields

The line reports mode; FPS/process time/draw calls/rendered objects/primitives/node and resource counts; accepted, relevant, irrelevant, rejected, and coalesced packets; pump calls and submitted native states; interval RX-to-native, native-to-apply, and RX-to-apply p50/p95/max; visual frames and generated/applied/no-op/failed rows; per-section row and CPU-time maps; physical outputs and beams considered; actual Light3D property writes, light visibility RID calls, beam parameter writes, beam visibility transitions, topology rebuilds, material parameter writes, gobo topology/parametric updates; current visible beam/realtime-light counts; and `emitter_commits=candidates/executed/signature_skipped/coalesced` plus total commit time (`emitter_commit_us`). The paired `[peraviz-color-dirty]` line separates changed color source offsets, offset-to-target fan-out candidates, unique dirty physical targets, final emitted rows, composition no-ops, and bounded useful-delta bands. `beam_topology` remains the compatibility count of calls to the broad topology helper; it does not prove that a mesh was built. `beam_full`, `beam_full_init`, and `beam_full_mask` identify all broad state applications and whether initialization or an explicit topology mask caused them. `beam_dynamic=changed/unchanged/unresolved` classifies fast-path results. Deferred semantic rows are counted as applied rather than renderer no-ops; final physical mutations remain represented by the emitter commit counters. Section IDs follow the visual protocol: Transform 1, Intensity 2, Color 3, BeamOptics 4, WheelSelection 5, WheelMotion 6, Temporal 8, GoboSelection 14, and GoboRotation 15.

`rows=2348` in the bootstrap diagnostic is a section-row count, not a fixture count. The canonical project has 71 live renderer fixtures, 95 independent Dimmer control targets, and approximately 1,095 physical Beam geometries. One inherited control can legitimately consider many physical outputs. The trace distinguishes that fan-out from actual renderer writes.

## Diagnostic modes

The modes are command-line-only and never modify saved visual settings:

- `full` applies normal production output.
- `transforms-only` retains the complete network/native pipeline but applies only Transform rows; lighting sections remain represented and are counted as diagnostically suppressed.
- `no-beams` applies normal transforms, lighting state, and emissive geometry while hiding existing beam instances and suppressing beam shader/topology work. Returning to `full` reapplies held state without rebuilding the scene.

## Interval latency and stability schema

`[peraviz-perf]` now names the three latency triples `rx_native_interval_us`,
`native_apply_interval_us`, and `rx_apply_interval_us` (p50/p95/max). These replace
that line's ambiguous `rx_native_us`, `native_apply_us`, and `rx_apply_us` labels.
They describe samples completed since the last report, approximately one second;
at low FPS the interval can be longer. The paired `[peraviz-stability]` JSON
object reports the actual `interval_ms`, explicit `*_interval_p50_us`,
`*_interval_p95_us`, `*_interval_max_us`, and `*_interval_samples` for
`rx_to_native`, `native_to_apply`, and `rx_to_apply`.

Three fixed pairs of 32-bucket power-of-two histograms retain no individual
samples. Percentiles approximate bucket upper edges, clamped to the observed
maximum; the last bucket saturates. Maxima are exact. Empty intervals report
zero values and zero samples. RX-to-native samples represent a pumped batch's
oldest relevant held receive timestamp; apply samples represent completed native
batches, not every UDP packet. A consumed state requiring no renderer rows also
completes its apply measurement. Receive timestamps remain the current mailbox
held-state timestamps, including refreshes from unchanged relevant packets.

Only `consume_interval_latency()` resets intervals. Technical Monitor/status
`get_stats()` reads leave them intact. `get_stats()` retains the old unqualified
latency keys as **lifetime compatibility aliases**. With tracing enabled, it also
exposes `*_lifetime_p50_us/p95_us/max_us/samples`; the stability report prints
those explicit lifetime fields. Lifetime means since the most recent receiver
start, while interval means since the last trace report in that session. The
main-thread wrapper owns these statistics; no RX-thread lock is added. Trace
OFF keeps the existing fixed lifetime accounting and skips interval observation.

The stability JSON also reports:

| Fields | Meaning |
| --- | --- |
| `static_bytes`, `objects_total`, `nodes`, `orphan_nodes`, `resources` | Godot Performance memory/object monitors. `objects` in the older compact line remains **rendered objects**, not total Objects. |
| `message_buffer_max_bytes` | Godot's message queue buffer high-water allocation, not current pending-call count. It need not shrink after draining. |
| `render_setup_cpu_ms`, `viewport_cpu_ms`, `viewport_gpu_ms` | RenderingServer frame setup and measured root viewport render times in milliseconds. These concern rendered frames, not each DMX packet or the entire reporting interval. They may overlap CPU apply/other timings and are not additive. Zero/unavailable headless timings do not affect correctness. |
| `mailbox_pending_dirty`, `mailbox_subscribed_universes` | Current pending universe tokens versus the current scene subscription bound. A concurrent receiver may refill tokens after a drain. |
| `mailbox_pending_high_water`, `mailbox_allocated_slots`, `mailbox_approx_bytes` | Receiver-lifetime token high-water and retained held-slot count/approximate bytes including fixed ring/table storage; excludes allocator/shared subscription overhead. |
| `mailbox_coalesced_states`, `mailbox_overwrites` | Identical **interval deltas**: changed state replaced another pending state for the same universe. This is not an expanding packet queue. Compact-line `overwrites` remains compatible. |
| `scene_dirty_states_consumed`, `relevant_state_updates` | Interval dirty states consumed and relevant changed publications. Rehydration is represented separately by existing submitted-state counters. |
| `active_universes`, `active_slot_count`, `approx_cache_bytes` | Active network universes in the last two seconds; lifetime metadata slots; approximate existing metadata/monitor-payload cache bytes. Mailbox storage is reported separately. |
| `sizes`, `sampled_high_water` | Current and reporting-boundary peak counts for apply state, warnings/info, registry/lens/gobo resources, renderer mesh/proxy caches and native state/payload capacity. Fixed keys, no history. `snapshot_commit_high_water` is sampled exactly once before each traced snapshot drains; `apply_snapshot_output_commits` should be zero at the report boundary. |

All Godot monitor/renderer queries, collection-size reporting, high-water maps,
and JSON payloads run only in the trace reporting path. The snapshot-commit peak
adds one trace-guarded size check per snapshot, never per row. Existing native
stats and renderer mutation diagnostics remain opt-in. The helper retains one
high-water scalar per fixed collection name, never one record per report. See
the [Phase A2 audit](phase-a2-stability-audit.md) for ownership, fixes and tests.

## Canonical Windows reproduction (Godot 4.7.1 / Forward+ / RTX 3070)

Use one Release native build and the same project, camera, window size, Vector
Gobo Prism settings, resolution, V-Sync/frame-cap settings and grandMA3 chase for
all runs. Record the Git SHA, Godot version and NVIDIA driver version. From the
Peraviz project directory in PowerShell, set the installed console executable:

```powershell
$godot = 'C:\Tools\Godot_v4.7.1-stable_win64_console.exe'
& $godot --version
New-Item -ItemType Directory -Force .\logs | Out-Null

# Production measurements: tracing and viewport render measurement OFF.
& $godot --path . --print-fps --log-file .\logs\a2-off-full.log -- --peraviz-render-diagnostic=full
& $godot --path . --print-fps --log-file .\logs\a2-off-transforms.log -- --peraviz-render-diagnostic=transforms-only
& $godot --path . --print-fps --log-file .\logs\a2-off-no-beams.log -- --peraviz-render-diagnostic=no-beams

# Diagnosis: identical inputs with tracing ON.
& $godot --path . --print-fps --log-file .\logs\a2-on-full.log -- --peraviz-perf-trace --peraviz-render-diagnostic=full
& $godot --path . --print-fps --log-file .\logs\a2-on-transforms.log -- --peraviz-perf-trace --peraviz-render-diagnostic=transforms-only
& $godot --path . --print-fps --log-file .\logs\a2-on-no-beams.log -- --peraviz-perf-trace --peraviz-render-diagnostic=no-beams
```

Close each process before starting the next. In each fresh process load
`testSENTIDOS(2).pvz` and confirm approximately 82 MVR / 71 live fixtures,
95 Dimmer targets, 1,095 physical output records and three relevant universes.
Enable DMX with the console initially static: record 60 seconds before the chase,
then run the **same** chase for ten minutes. Compare the first 30 seconds with
minutes 5 and 10. Stop the chase while continuing static Art-Net for 60 seconds,
then stop/restart DMX and replay. Separately reload the same scene and change
presentation and back, checking that state/cache counts settle again rather than
retaining each generation. Do not mix these lifecycle transitions into the
fixed-scene sustained-playback slope.

Retain the trace files and compare repeated fresh-process runs in reverse order
to reduce warmup/thermal bias. Trace-OFF `--print-fps`, visible latency and normal
Godot process monitoring establish production behavior; trace-ON diagnoses it.
Trace overhead is not zero. Keep GPU power/temperature/clocks/VRAM observations
with the run, and use a GPU profiler if timing suggests saturation/synchronization.
For an additional full-mode GPU-profile run:

```powershell
& $godot --path . --print-fps --gpu-profile --log-file .\logs\a2-gpu-full.log -- --peraviz-perf-trace --peraviz-render-diagnostic=full
```

Interpret the A/B evidence as follows:

- Growing current state/cache counts, Objects/orphans, native diagnostics or
  repeated resource creations under a fixed chase indicate CPU/resource growth;
  correlate with the responsible ownership table before attributing a cause.
- Stable sizes with rising message-buffer high-water suggest deferred activity
  to investigate; high-water alone does not prove an undrained queue.
- `transforms-only` preserves native DMX work and isolates it from lighting apply.
  Compare interval RX-to-native age, native dirty/color counts and domain timing.
- `no-beams` retains logical lighting and emissive geometry; compare with `full`
  to separate beam apply and rendering cost. Use emitter commit/domain times for
  per-output CPU mutation, not the outputs-considered count alone.
- Stable rows/commits with increasing render setup/viewport CPU points toward
  RenderingServer work; rising viewport GPU time points toward GPU cost. Stable
  engine measurements with rising CPU frame time requires main-thread profiling
  outside the existing apply buckets, not an automatic GPU conclusion.
- A problem present only with trace ON suggests diagnostic cost; compare fresh
  processes with tracing OFF. Neither headless zeros nor this audit proves
  steady GPU saturation or excludes driver queues/synchronization.

The hardware run remains outstanding. Grouping and batching are still future
work; this baseline must establish whether time/counters actually grow first.

## Next-phase batching boundary

If the trace confirms that roughly one thousand distinct physical Beam outputs genuinely change color every visual frame, the retained per-output GDScript and Node mutation path has reached its architectural scaling limit. The next phase should keep semantic resolution in native C++ and publish a compact contiguous renderer batch keyed by stable output ID. Transform, color, intensity, visibility/active state, beam angle/zoom, and presentation custom data can be carried in parallel packed buffers and applied through RenderingServer or MultiMesh-oriented presentation with minimal GDScript dispatch.

Gobo texture identity still needs batching by compatible texture/material set, topology-changing fallback renderers still require separate lifecycle handling, and surface projector lights remain individual renderer resources. This phase must preserve distinct GDTF Beam geometries and only changes how their already-resolved states reach presentation.
