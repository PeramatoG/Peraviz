# Temporal presentation audit and regression contract

Reference: merged PR #123, `069ef3b646e3eafdda6c365871425d424589736c`.
The candidate changes diagnostic accounting, makes temporal profiling opt-in, and
compares projector energy at the float precision accepted by Godot. It preserves
GDTF frequency/range interpretation, physical state and renderer admission.

## Ownership and findings

| Stage | Production owner and work boundary |
| --- | --- |
| Receive/filter | Native Art-Net worker, immutable relevant-slot subscription and latest-state mailbox; identical relevant packets do not nominate source work. |
| Source/activation | `CompiledEvaluationPlan` / `EvaluationWorkspace` and native visual runtime; source/ModeMaster caches update only on relevant dependencies. Shutter sampling never calls them. |
| Physical state | `DensePresentationState`, reached directly through serial `DirectPresentationPipeline` or the existing native async coordinator and immutable completed snapshots. No physical buffers round-trip through scripts for semantic evaluation. |
| Temporal authority | Native `ShutterPlayback` on the presentation thread; one active/invalidated authority sample per call, fixture-local identities and deterministic seeds installed from the compiled graph. |
| Envelope distribution | Indexed authority members, physical layer routes and physical-to-render-row membership; one aggregate row nomination, separate physical lens/footprint/projector routes. |
| Renderer mutation | Native main-thread `NativeBeamBindings`, `PresentationMaterialBindings`, `NativeLensBatches`, and weak `Light3D` handles. Existing unsupported shaft paths retain their established fallback. |
| GPU submission | Godot RenderingServer and driver; CPU material setters are not draw calls. Lens `multimesh_set_buffer` calls count API payload bytes, not measured PCIe traffic or GPU time. |

**Confirmed diagnostic/overhead defects:** temporal profiling previously read
clocks even with performance tracing disabled. Timing now follows the existing
snapshot trace flag. Combined material accounting read a previous lens writer's
counter even when that writer was skipped; accumulation now uses this transaction's
actual lens count. New split counters make the distinction reviewable.

**Targeted redundant setter correction:** `Light3D::set_param` accepts float.
Comparing its retained float to an unrounded double product can report a difference
on an otherwise identical held-state replay. Compare the float that will actually
be submitted. A fractional-gain Native projector replay regression requires zero
additional energy setters after invalidation. Physical values are unchanged.

**Acceptable necessary cost:** Custom footprints own independent projection
materials and instance visibility. Shared shutter timing cannot merge their
geometry, color, optical profile or gobo projection. Every changed, nonzero physical
footprint energy needs its own material setter. StandardMaterial lenses already
use setup-time unique-RID bindings; compatible shared RIDs are nominated through
physical routes and unchanged values suppress duplicate setters. GPU lenses keep
independent RGB/base energy and change only custom alpha on a temporal transition.
Aggregate shaft rows and compatible shared shaft materials are already coalesced.
These distinct operations explain why pooling waveforms did not eliminate physical
footprint/material writes in the earlier common-control measurements.

**Opportunities deferred:** material routes can revisit a shared binding, but its
committed-value check suppresses duplicate setters. Footprint culling and hidden
GPU lens slots retain current energy data so visibility recovery is immediate;
zero base energy and disabled resources already suppress unchanged energy writes.
Deferring hidden-resource data updates would need a separate replay/invalidation
contract. No measured submission reduction justifies adding it here. Distinct
footprints must not merge just because their current energy is equal.

The existing bounded 8–64-instance lens buffers and indexed routes are retained.
Each temporal call edits only changed alpha values, then flushes each dirty batch
once. Unchanged batches do not submit. Render Group membership does not veto lens
batching; optical/material/transform/spatial admission still does. Installation
and clear revoke borrowed RIDs before owner resources retire. No new worker,
fixture timer, shader clock, authority cache or resource ownership is introduced.
The pinned Godot 4.7 API exposes full `multimesh_set_buffer`, per-instance setters
and RenderingDevice RID access; the existing full-buffer API has no offset/length
argument. This audit does not infer that device-level partial writes are safe or
faster. Submitted bytes include transforms and all custom data, even if only one
instance alpha changed. Scanning existing batch dirty flags is bounded by installed
batches; measurements do not justify a new dirty-batch scheduler.

## Reproduction and counter interpretation

Use the normal native CMake build and existing GDScript runner. The new
`test_temporal_presentation_guardrails.gd` inherits the production-import shutter
harness and public generated GDTF/MVR fixtures; no private scene is needed:

```sh
cmake --build native/build --parallel 5
ctest --test-dir native/build --output-on-failure --timeout 120
$GODOT_BIN --headless --audio-driver Dummy --rendering-method forward_plus --path . --script tests/gdscript/test_temporal_presentation_guardrails.gd
```

For the reference, copy that test into `069ef3b` with the same inherited harness
and run with `-- --temporal-baseline` (skips candidate-only counter assertions).
Use separate completed builds, identical engine, build configuration and generated
resources. Resource installation and initial parameter publication precede each
measurement. Both sides use 240 explicit timestamps `1.001 + tick/120`; shared
128-output Random uses 7,200 timestamps (60 simulated seconds without sleeping).
A repeated call at each timestamp checks unchanged-envelope suppression. Thus
normal active scenarios contain two presentation calls per timestamp; repeated
identical packets add a third call through the existing snapshot helper. These
are call counts, not a claim that two evaluations occurred inside one sample.
The test reports a deterministic digest of all sampled physical envelopes and
independently checks retained canonical values and consumer energies. Cold stats,
resource inspection and digest formatting stay outside the timed advance call.

The test also covers no shutter, static Open/Closed, ordinary Dimmer/Color edits,
periodic and Random, shared 32/128, four banks/128, independent/128, DMX hold,
identical packets, no resource/capacity growth and unload/reload retirement.
Existing `test_native_shutter` and `test_shutter_authority` retain supported pulse
shapes, independent/co-patched sequences, per-cell colors, gobo PosRotate,
material fallback, held-state renderer replacement, suppression and native
serial/async parity. Native CTest retains relevant-slot filtering, source graph,
mailbox/activation, deterministic waveforms and adaptive worker-policy coverage.

Existing `[peraviz-stability].dense_presentation` / `get_sizes()` exposes the
following generation-local cumulative exact counts (take interval differences):

- `shutter_active_authorities` and `shutter_temporal_authorities` are current
  control gauges, not physical-output counts.
- `shutter_waveform_evaluations` counts numerical authority samples;
  `shutter_envelope_changes` counts changed physical envelopes **including forced
  resource replays**, not just numerical transitions.
- `shutter_beam_writes` counts actual parameter and visibility setters;
  `shutter_lens_material_writes`, `shutter_footprint_material_writes` and
  `shutter_projector_writes` count actual consumer energy setters. Combined
  `shutter_material_writes` is lens plus footprint, excluding instance visibility.
- `shutter_lens_instance_writes` counts changed instance alpha values;
  `shutter_dirty_lens_batches` aliases actual flushed dirty batches;
  `shutter_lens_submissions` counts full-buffer API calls and
  `shutter_lens_transfer_bytes` counts their exact float32 payload bytes.
- `shutter_evaluation_us` and `shutter_mutation_us` measure two nonoverlapping
  stages only while tracing; `shutter_presentation_us` includes both. Each duration
  truncates to integer microseconds, so sums can differ. These are sampled CPU
  wall times, including preemption, not GPU measurements.

Existing renderer resource revisions, shaft/lens/Custom volume creation and
retirement counters measure structural work. `shutter_cpu_bytes_estimate` estimates
retained vector/map storage; it excludes allocator, Godot and driver memory and is
not RSS. Existing `gpu_lens_transfer_bytes/submissions` describe only the last
flush and must not be summed from unchanged observations; temporal cumulative
counters avoid losing flushes between reports. Trace-off uses scalar accounting
and existing indexed routing, with no diagnostic clocks, per-output dictionaries,
formatting or scene scans. Its one steady-clock read for active waveform time is
functional sampling, independent of profiling. No-shutter returns before it.

## Baseline/candidate measurements

Linux Debug, pinned Godot 4.7.1 headless Forward+ admission with the dummy
render server, sequential reference then candidate. All 25 scenario rows have
identical sampled envelope digests, canonical correctness assertions, resource
counts, waveform/envelope/write counts and submission bytes. Full values are in
[the bounded CSV](measurements/temporal-presentation-guardrails.csv). Counts below
are **baseline = candidate**; CPU wall totals are baseline → candidate µs.

| Layout / scenario | Authorities; aggregate/individual shafts; GPU instances/batches | Waveforms | Beam / lens-material / footprint setters | Submissions / bytes | CPU µs |
| --- | --- | ---: | --- | --- | --- |
| 32 / shared / periodic | 1; 1/0; 26/1 | 480 | 39 / 39 / 1,248 | 39 / 64,896 | 798 → 933 |
| 32 / shared / random | 1; 1/0; 26/1 | 480 | 38 / 38 / 1,216 | 38 / 63,232 | 729 → 1,785 |
| 128 / shared / periodic | 1; 1/0; 128/3 | 480 | 39 / 0 / 4,992 | 117 / 319,488 | 3,114 → 3,524 |
| 128 / shared / random | 1; 1/0; 128/3 | 14,400 | 1,198 / 0 / 153,344 | 3,594 / 9,814,016 | 89,130 → 107,814 |
| 128 / four banks / periodic | 4; 4/0; 104/4 | 1,920 | 156 / 156 / 4,992 | 156 / 259,584 | 3,679 → 3,530 |
| 128 / four banks / random | 4; 4/0; 104/4 | 1,920 | 152 / 152 / 4,864 | 152 / 252,928 | 3,456 → 4,039 |
| 128 / independent / periodic | 128; 0/128; 128/3 | 61,440 | 4,992 / 0 / 4,992 | 117 / 319,488 | 11,739 → 9,830 |
| 128 / independent / random | 128; 0/128; 128/3 | 61,440 | 4,864 / 0 / 4,864 | 528 / 1,482,240 | 55,389 → 13,941 |

All held/identical-packet scenarios add **zero physical source evaluations**,
renderer rebuilds, material growth or temporal capacity growth. Static Open,
Closed and no shutter add zero ongoing waveform/envelope/setter/submission work.
The shared 128 Random row uses 7,200 timestamps; all others use 240. Resource
counts above are unchanged before/after playback and across builds. Native
projectors are absent in this Custom-footprint matrix; the separate fractional
Native-projector regression exercises real energy setters and equivalent replay.

Ordinary Color/Dimmer uses 479 actual source evaluations on both sides and zero
waveform evaluations. Its temporal row replays are necessary because the normal
physical shaft writer changes the same owned renderer resource. The CSV's
material/submission counts cover temporal overrides only; ordinary physical RGB/
energy submissions belong to the existing material/lens counters. In this case
physical material writers already commit the current open envelope, so the
subsequent temporal lens/footprint mutation count is zero. Repeated identical DMX
preserves periodic digests and source counts while sampling three calls per
explicit timestamp; it does not restart phases.

These single-run timings include sub-microsecond truncation and scheduler noise
(the independent Random reference had a large outlier). They establish no CPU
speedup, FPS target or GPU performance change. Stage timing is opt-in and adds a
clock boundary in the candidate. A separate trace-off check asserts no timing
accumulation while numerical sampling continues; no-shutter returns before clocks.
The deterministic acceptance evidence is unchanged work/resources plus removal of
unconditional profiling clocks and equivalent float projector replay setters.

Native binaries used for these measurements (Debug, SHA-256):

- Reference: `c8cf01746306617ed69724385e9b7dc789eb68b71b2941619741710f90a82eda`.
- Candidate: `aeb97a0f3789e0cc536bb5114f4e3569d05f80318f05cbbfc1efcab79cd8cf28`.

Validation: native CTest **13/13**; existing/new GDScript **43/43**; runtime
architecture, no-large-files and whitespace checks pass (existing unrelated
large-file warnings remain). No CI timing thresholds were added. The PR records
its exact tested source commit and remote CI status separately from local checks.


## Owner observations: zero GPU lenses and apparent strobe speed

The owner reports **1,095 physical outputs, 20 accepted aggregate shafts for
1,000 emitters, and zero GPU lens instances** on Windows. This is owner-provided
setup evidence. After the owner supplied the archive privately, a production-import
headless Forward+ / full / Custom-footprint probe reproduced **1,095 physical outputs,
20 accepted aggregate shafts, 115 renderer rows and zero GPU lens instances**.
`gpu_lens_policy=eligible`, but all 1,095 source lenses fail the first mesh-type gate:
**1,083 `CylinderMesh` and 12 `BoxMesh`**, while the admitted slice requires
`ArrayMesh`. The shared Wash
members additionally retain material overrides and nonconformal thin-lens transforms;
converting only the mesh type would not establish safe admission. This is a confirmed
compatibility fallback, not an aggregation veto or temporal regression. No private
archive, vendor asset/XML, fixture identifier or production filename is committed.
The headless result does not prove Windows rendering speed or every owner setting.

Existing `--peraviz-perf-trace` now retains a **setup-only**, bounded first-rejection
summary in `dense_presentation`: `gpu_lens_policy`, `gpu_lens_rejections`,
`gpu_lens_material_option_rejections`, `gpu_lens_mesh_type_rejections`, `gpu_lens_candidate_partitions` and
`gpu_lens_admission_trace_enabled`. Enable tracing **before scene import**; enabling
it afterward cannot reconstruct a previous admission transaction. These summaries
reset on reinstall and run through the already required admission loop. There is
no per-frame discovery, per-output diagnostic record or new automatic inspection.
`gpu_lens_policy` distinguishes backend, physical-light-units, explicit disable,
presentation mode, diagnostic surface lights, debug optics and realtime-light
policy. An eligible policy can still reject every source. Rejections distinguish
resource/target counts, mesh class/topology, visual children, mesh ownership (including
material overrides), visibility/render policy, nonconformal/reflected transforms,
spatial extent, projector dependency and groups below eight instances. Partitions
retain the same mechanical ancestor, **mesh resource identity** and 4 m spatial
cell key; 20 accepted shaft aggregates do not prove compatible lens meshes or an
eight-instance aperture partition. Counts describe first rejection per visited
physical output, not all possible reasons; source/fallback counts concern outputs
that actually own lens materials. Material detail names only the first mismatched
stored StandardMaterial option, from the fixed prototype property set.

Public shared-128 tests reproduce 128 lenses/3 batches under eligible resources,
zero/zero when their shared material's roughness differs (128 `material_options`
rejections naming `roughness`), geometry fallback for a nonconformal transform,
and zero/zero with `explicit_disabled`. A public `CylinderMesh` replacement also
reports its exact rejected class and retains individual rendering. Restoring
resources/policy restores 128/3 from held state. No eligibility rule, material
ownership or geometry is relaxed. The owner's Windows trace can now confirm this
reason using `gpu_lens_rejections.mesh_type` and the exact class counts in
`gpu_lens_mesh_type_rejections`, rather than interpreting zero as a
failed batch submission. Expanding primitive/override/nonuniform lens support would
be a separate renderer compatibility task, not a change justified by this audit.

The existing opt-in **Copy shutter diagnostic** is regression-checked against
public default/descending/narrow/fixed/single-value ranges. Active rows expose raw
DMX and resolution, exact ChannelFunction/ChannelSet names, effective inclusive
DMX boundaries, effective PhysicalFrom/To, resolved Hz, duration, waveform and
cached source identity. Optional source names remain empty when unnamed/absent; compare the effective range and source ID with the archive rather than inventing a set name. Native trace tests also cover ordered 8/16/24/32-bit values.
Inspection creates no source evaluation. The button now includes current lens
admission information; detailed reasons require the performance trace at setup.

A confirmed **diagnostic labeling ambiguity**, not a waveform defect, was found:
`sampling_probe.event_window_seconds` is a legacy sum across 20 reference events.
It remains compatible, with explicit `total_event_window_seconds` and
`single_event_window_seconds` aliases and a `frame_sampling_note`. For a 25 ms
square flash, these distinguish 0.5 s total from 0.025 s per event. The existing
15/30/60/120 FPS frozen-parameter probe reports reference/visible/missed event
windows. It is hypothetical uniform sampling relative to activation, not measured
runtime FPS or a guarantee at every frame phase. Actual cadence/phase can miss
short windows or make a high rate appear slower. At durations as long as the
period, supported square windows can overlap and appear continuously open.

The supplied shared-Wash GDTF also exposed a **reproducible source-data/mapping
discontinuity**. Its named marker ChannelSets omit physical endpoints. Under the
existing inherited endpoint and local-range contract, a one-value marker uses
PhysicalFrom, so the label “Fast” does not by itself establish a high frequency:

| Raw 8-bit DMX | Selected effective set range | Resolved Hz / waveform |
| ---: | --- | --- |
| 124 | unnamed 51–124 | 20 / Strobe |
| 125 | named middle marker 125–125 | 1 / Strobe |
| 199 | unnamed 126–199 | 20 / Strobe |
| 200 | named fast marker 200–200 | 1 / Strobe |
| 201 | Open 201–210 | 0 / Open |
| 254 | unnamed 234–254 | 20 / RandomStrobe |
| 255 | named fast marker 255–255 | 1 / RandomStrobe |

The parent periodic function spans 50–200 and 1–20 Hz; the active effective set
has its own inclusive boundaries and inherited 1–20 endpoints. Actual square
Duration remains 0.025 s. The diagnostic now exposes parent
`channel_function_dmx_from/to` and `channel_function_physical_from/to` alongside
the effective set fields, so a copied report shows the distinction directly.
These values came from actual production archive import and native evaluation,
not an assumption based on a UI rate slider. A public test with different generic
ranges characterizes the same label-only single-value behavior without vendor data.

[Published GDTF Table 61](https://github.com/mvrdevelopment/spec/blob/main/gdtf-spec.md#channel-set)
defaults omitted set PhysicalFrom/To to the corresponding parent endpoints.
The observed result matches the current documented interpretation; it does **not**
confirm a native semantic defect or justify silently interpolating the whole parent
range instead. It does demonstrate that slower apparent “maximum” may originate
before frame sampling: the chosen raw marker can resolve to 1 Hz. Recommend a
separate focused review of source marker metadata, manufacturer intent and the
other visualizer's actual raw input/profile. Any confirmed semantic correction
belongs in that separate change with public source-data regressions. This PR
changes no frequency mapping, waveform, duration or original MVR/GDTF data.

For owner comparison, capture low/mid/max **raw** values in the same fixture/mode
with exact archive identity, function/set boundaries, physical endpoints,
Hz/duration/waveform and normal trace-off frame rate. Use
`PERAVIZ_NATIVE_EVALUATION=serial` and `PERAVIZ_SHUTTER_TRACE=<fixture UUID>` before
import (optional `PERAVIZ_SHUTTER_TRACE_TARGET=<target ID>`), then Debug → Copy
shutter diagnostic. Compare resolved Hz first; use the hypothetical sampling
probe and actual frame cadence only after confirming the same physical rate.

A supplemental shared-128 transaction probe also found that a simultaneous Color
change and flash edge can submit the same three batches twice: physical publication
8,192 bytes, then temporal 8,192 bytes, in **both** reference and candidate. Reproduce
by activating 10 Hz at 1.0 s, then setting primary Dimmer=128 and Green=255 at 1.08 s
before advancing presentation. Per-dirty-batch coalescing is per temporal transaction,
not across these two publication phases in a rendered frame. Cross-phase scheduling
would change sampling/publication/replay ordering; no measured GPU or meaningful CPU
benefit justifies changing that contract in this PR. It remains an optimization
opportunity for Windows attribution, not an increase introduced by this audit.

## Windows owner validation

On Windows 10, use Godot 4.7.1 stable console runtime, Forward+ and RTX 3070.
Build baseline `069ef3b` and the candidate separately with the same Release native
configuration. For each record `git rev-parse HEAD`, native DLL SHA-256/build
configuration, engine `--version`, NVIDIA driver and scene SHA-256. Use the same
MVR file (or generated public fixture), exact camera, window resolution, optical
settings, lens policy, Fake Smoke, V-Sync and frame cap. Close the editor and other
Peraviz processes. Run the project normally without `--editor` or debugger.

```powershell
$godot = 'C:\Tools\Godot_v4.7.1-stable_win64_console.exe'
git rev-parse HEAD
Get-FileHash .\bin\peraviz_native.dll -Algorithm SHA256
& $godot --version
# Normal FPS; tracing absent. Use a fresh label for each build/scenario.
& $godot --path . --print-fps --log-file .\temporal-off.log -- --peraviz-render-diagnostic=full
# Separate diagnostic run, same workload/configuration.
& $godot --path . --print-fps --log-file .\temporal-on.log -- --peraviz-perf-trace --peraviz-render-diagnostic=full
# Optional built-in GPU timing pass; no new profiling installation required.
& $godot --path . --print-fps --gpu-profile --log-file .\temporal-gpu.log -- --peraviz-perf-trace --peraviz-render-diagnostic=full
```

Use an identical recorded/reproducible DMX sequence for both builds: 30 s warmup,
60 s no input/held Open, 60 s repeated unchanged relevant packets, 60 s held Closed,
60 s periodic strobe, 60 s shared Random, and 60 s independent Random. Separate
ordinary Color/Dimmer changes from temporal-only hold. Hold shared Random for ten
minutes once to check stable resource/capacity counts. Repeat in reverse build
order. Record normal trace-off FPS ranges and CPU process/frame time separately
from trace-on mutations/submissions/resources. Compare viewport CPU and
`viewport_gpu_ms` from the existing trace; CPU setup, process and GPU times overlap
and must not be added. Treat unavailable/zero GPU samples as unavailable.

After steady-state runs, replace the renderer and return, blackout/restore, stop
DMX, and unload/reload the same scene; check current sequence/energy restoration
and resource counts settling. Do not include those transitions in playback timing.
Tracing changes CPU cost: use it for attribution, never as normal FPS evidence.
Windows visual/GPU validation remains owner work; Linux headless CPU times cannot
predict RTX 3070 frame rates, driver submission cost or missed visible flashes.
