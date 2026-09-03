# Live render latency diagnostics

## Measurement boundary

`--peraviz-perf-trace` emits one compact `[peraviz-perf]` line approximately once per second. `rx_apply_us` measures relevant ArtDmx receipt through completion of Godot scene/resource mutation on the CPU. It does not include render submission, GPU execution, frame queueing, or display presentation. `pump_hz` counts production pumps from the render `_process` path; the 125 ms status refresh only updates UI.

Tracing is explicitly opt-in. Use `godot --path .` for the production baseline and `godot --path . -- --peraviz-perf-trace` for a diagnostic benchmark. Trace-off avoids rich row categorization, per-row clocks, native stats payloads, and presentation SceneTree sampling. Compare settled runs because trace-on accounting still has measurable cost.

With tracing disabled, playback performs no `Performance` monitor reads, trace formatting, interval diagnostic retention, per-row result dictionaries for Transform/Intensity/Color, renderer-counter mutation, or per-frame deep diagnostic copy. The one-time bootstrap diagnostic remains. Enabling tracing retains interval row/timing summaries, snapshots cumulative counters once per applied frame, reads Godot monitors, and formats only at the one-second report boundary.

## Trace fields

The line reports mode; FPS/process time/draw calls/rendered objects/primitives/node and resource counts; accepted, relevant, irrelevant, rejected, and coalesced packets; pump calls and submitted native states; RX-to-native, native-to-apply, and RX-to-apply p50/p95/max; visual frames and generated/applied/no-op/failed rows; per-section row and CPU-time maps; physical outputs and beams considered; actual Light3D property writes, light visibility RID calls, beam parameter writes, beam visibility transitions, topology rebuilds, material parameter writes, gobo topology/parametric updates; current visible beam/realtime-light counts; and `emitter_commits=candidates/executed/signature_skipped/coalesced` plus total commit time (`emitter_commit_us`). The paired `[peraviz-color-dirty]` line separates changed color source offsets, offset-to-target fan-out candidates, unique dirty physical targets, final emitted rows, composition no-ops, and bounded useful-delta bands. `beam_topology` remains the compatibility count of calls to the broad topology helper; it does not prove that a mesh was built. `beam_full`, `beam_full_init`, and `beam_full_mask` identify all broad state applications and whether initialization or an explicit topology mask caused them. `beam_dynamic=changed/unchanged/unresolved` classifies fast-path results. Deferred semantic rows are counted as applied rather than renderer no-ops; final physical mutations remain represented by the emitter commit counters. Section IDs follow the visual protocol: Transform 1, Intensity 2, Color 3, BeamOptics 4, WheelSelection 5, WheelMotion 6, Temporal 8, GoboSelection 14, and GoboRotation 15.

`rows=2348` in the bootstrap diagnostic is a section-row count, not a fixture count. The canonical project has 71 live renderer fixtures, 95 independent Dimmer control targets, and approximately 1,095 physical Beam geometries. One inherited control can legitimately consider many physical outputs. The trace distinguishes that fan-out from actual renderer writes.

## Diagnostic modes

The modes are command-line-only and never modify saved visual settings:

- `full` applies normal production output.
- `transforms-only` retains the complete network/native pipeline but applies only Transform rows; lighting sections remain represented and are counted as diagnostically suppressed.
- `no-beams` applies normal transforms, lighting state, and emissive geometry while hiding existing beam instances and suppressing beam shader/topology work. Returning to `full` reapplies held state without rebuilding the scene.

## Windows reproduction

From the Peraviz project directory with Godot 4.7.1:

```powershell
godot.exe --path . --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=full
godot.exe --path . --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=transforms-only
godot.exe --path . --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=no-beams
godot.exe --path . --print-fps --gpu-profile -- --peraviz-perf-trace --peraviz-render-diagnostic=full
```

For each mode, load `testSENTIDOS(2).pvz`, start Art-Net from grandMA3, move Pan/Tilt continuously for about ten seconds, and retain at least ten trace lines. Repeat with a Dimmer chase if useful. Compare RX-to-apply p95, pump rate versus FPS, frame stability, actual writes, and full versus transforms-only/no-beams behavior. A physical GPU trace remains required before attributing the offset to beams, Forward+, V-Sync, or the GPU.

## Next-phase batching boundary

If the trace confirms that roughly one thousand distinct physical Beam outputs genuinely change color every visual frame, the retained per-output GDScript and Node mutation path has reached its architectural scaling limit. The next phase should keep semantic resolution in native C++ and publish a compact contiguous renderer batch keyed by stable output ID. Transform, color, intensity, visibility/active state, beam angle/zoom, and presentation custom data can be carried in parallel packed buffers and applied through RenderingServer or MultiMesh-oriented presentation with minimal GDScript dispatch.

Gobo texture identity still needs batching by compatible texture/material set, topology-changing fallback renderers still require separate lifecycle handling, and surface projector lights remain individual renderer resources. This phase must preserve distinct GDTF Beam geometries and only changes how their already-resolved states reach presentation.
