# Gobo hot path and rendering isolation

Base: latest main `6f0f38d` (includes PR #125), rather than the older `c7f0cc5`.
No private MVR/PVZ/GDTF assets are included. The
[recorded evidence](performance/gobo-hotpath-and-render-isolation.json) separates
counter results, application-only CPU samples and software graphics validation.

## Confirmed correction

The gobo registry distinguishes resource selection (`NAN` angular argument) from
angular presentation (finite argument). Both previously entered
`load_scene._present_native_gobo()` and unconditionally called `rebind_dense_light`.
That invalidated the native beam bindings. Completing the next presentation
transaction installed beam/shutter resources and invalidated retained shutters,
even with held DMX. The extracted `native_gobo_presentation.gd` retains the optical
callback, profile, projection, original artwork and shaft roll. Only selection,
changed beam/mesh/material or changed optical geometry enters cold rebinding.

Baseline and candidate use deterministic 30°/s rotation, 320 frames per scenario,
a shared Random Strobe and the same timestamps. The mixed standard generated MVR
has 32 independent gobo outputs beside a separate 32-member aggregate Wash shaft.
Each scenario runs held DMX and then unrelated changing Dimmer/Color:

| Work per 320-frame scenario | One gobo, before → after | Mixed scene, before → after |
| --- | ---: | ---: |
| Light rebind calls | 320 → 0 | 10,240 → 0 |
| Beam binding passes | 320 → 0 | 320 → 0 |
| Shutter resource installs | 320 → 0 | 320 → 0 |
| Shutter invalidations | 320 → 0 | 320 → 0 |
| Renderer refreshes / group rebuilds | 0 → 0 | 0 → 0 |
| Held-DMX source evaluations | 0 → 0 | 0 → 0 |

Random envelope digests and changing-DMX source work remain identical. Candidate
coverage additionally exercises Native Footprints, original texture/rolled inverse,
real selection, resource replacement, legacy/Vector renderer switches, held-state
rehydration and unload. Angular presentation skips only the surface bridge's final
photometric replay: replaying unmodulated energy there would overwrite retained
native shutter energy. All optical work still runs. Selection and changed resources
retain photometric ownership refresh. Native projector energy is checked immediately
after rotation, before another shutter tick could conceal an overwrite. An initial
blackout→lit Native ownership regression also reproduced missing borrowed shutter
light routes; actual light-ownership transitions now invalidate those cold bindings.
Stable angular callbacks do not.

Mode replay testing also found physical emitter parents remained hidden behind
aggregate rows after returning to Full. Full now restores those parents at the
cold mode boundary; member shafts retain their own suppression and independent
footprints recover without a new DMX packet. No per-frame traversal is added.

New bounded counters are `dense_light_rebind_calls`, `dense_renderer_refreshes`,
`render_group_binding_installs`, `native_beam_binding_passes`,
`shutter_resource_install_calls`, `native_beam_eligible_candidates`, and
`shutter_invalidations`. Script event counters accumulate while tracing is enabled;
take differences within one adapter lifetime. The candidate count is a setup-time
gauge. Native invalidations count cold calls, including calls without active
shutters, and reset with native installation. It adds no clock or scan. Existing
shutter waveform, envelope, setter and resource counters keep their meanings.

## Startup-only consumer controls

Both controls leave diagnostic mode **Full**, normal native source evaluation,
physical composition, Pan/Tilt and lens emission enabled. They never enter visual
settings, presets or PVZ serialization. Restart without the flag to restore normal
presentation. They survive resource/renderer replacement and scene reload:

- `--peraviz-render-isolation=no-custom-footprints` disables the existing native
  footprint material consumer and instance visibility; resources and physical
  values remain retained. Projector transform notifications still run.
- `--peraviz-render-isolation=no-volumetric-shafts` sets cached shaft draw layers
  to zero at binding boundaries. Optical transforms, beam mutations and native
  shutter ownership remain active. Lens and footprint layers are untouched.

The policies deliberately differ in which mutations remain: use actual setter
counters, and the existing draw-only bottleneck matrix, when separating mutation
cost from graphics cost. Disabling draw layers alone does not measure all shaft
presentation CPU work. These flags do not change Native Footprints ownership;
use the Custom backend when measuring Custom Footprints. Invalid values use neither
isolation. Existing Full, No-beams and transforms-only suppression stays distinct.

A production-import regression drives 120 actual native DMX updates, including
Pan/Tilt, in each startup configuration. Physical-state and transform digests match
bitwise, and all three execute 480 source-program evaluations. A 32-member Wash
aggregate remains one shaft; Custom resource count remains 32. Active consumer
counts, lens emission, no live installations, held mode replay and retirement are
checked separately. Receiver culling is accounted for rather than overridden.

## Windows comparison

Use the same scene, fitted/saved camera, chase recording, resolution, renderer,
V-Sync policy and build. Run each command first with tracing OFF; collect warmed
median FPS over the same interval. Then repeat **adding
`--peraviz-perf-trace` after `--`** for viewport/CPU/counter evidence. Driver-level
V-Sync can override the command. Do not compare different saved optical presets.

```powershell
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --print-fps -- --peraviz-render-diagnostic=full
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --print-fps -- --peraviz-render-diagnostic=full --peraviz-render-isolation=no-custom-footprints
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --print-fps -- --peraviz-render-diagnostic=full --peraviz-render-isolation=no-volumetric-shafts
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --print-fps -- --peraviz-render-diagnostic=no-beams
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --print-fps -- --peraviz-render-diagnostic=transforms-only
```

Record trace-off FPS separately. `[peraviz-stability]` contains sampled process
and viewport CPU/GPU times, viewport draws/rendered objects, consumer isolation,
active/allocated shafts and footprints, exact script uniform and physical material
writes, cold-operation counters, shutter evaluations/invalidations and native
source workload. Counts of active footprints precede camera culling; transparent-only
objects are not exposed by Godot's viewport API. Do not add overlapping process,
viewport, native evaluation/compose, application and mutation times. Process monitor
samples are coarse, and viewport GPU time excludes compositor/present overhead.
Use Godot CPU profiling and a real GPU capture to distinguish RenderingServer waits,
Vulkan submission, shaft/footprint overdraw and GPU execution.

The existing graphical/bottleneck probe also accepts `--startup-isolation-probe`:

```powershell
& $godot --path . --rendering-method forward_plus --rendering-driver vulkan --disable-vsync --script tests/gdscript/test_custom_surface_footprints.gd -- --render-footprint-probe --bottleneck-probe --startup-isolation-probe --footprint-output=C:/Temp/peraviz-shafts --peraviz-render-isolation=no-custom-footprints
```

Repeat with each mode/consumer argument above. This reuses its generated geometry,
resolved-input pulse, viewport capture and diagnostics; it excludes raw DMX/GDTF
evaluation and is not an owner-stream replay. The explicit startup probe bypasses
the unrelated full-consumer unit assertions; normal CI and existing probes keep
the complete regression path. Six-output Forward+/Vulkan **llvmpipe software**
validation records 18 / 12 / 12 / 6 / 6 draws for the five configurations. This
proves consumer isolation, not hardware performance.

## Native beam admission

The existing eligibility predicate is retained: independent compatible Vector
Prism resources only; aggregate rows, grouped materials, gobos, realtime-light,
unknown shaders/materials and unsupported policies retain fallback. The minimum
is lowered from 128 to **32 eligible candidates**, not 32 physical outputs. The
31-candidate boundary remains on script application. The new boundary regression
reproduced obsolete script signatures after native revocation; cold admission now
invalidates those cached signatures before clearing native-candidate flags. This
preserves exact fallback when a previously admitted set loses eligibility.

The existing generated footprint presentation harness compares native and script
application with identical prebuilt rows, 32 warm-up frames, 240 measured frames,
three rounds and alternating execution order. Values and visibility compare exactly,
including physical/footprint data, and routes retire cleanly. Median microseconds
per complete compose/application call, Linux Debug / Godot 4.7.1 headless:

| Compatible candidates | Script µs | Native µs |
| --- | ---: | ---: |
| 32 | 1,096.7 | 133.2 |
| 64 | 2,345.9 | 277.6 |
| 115 | 3,578.5 | 450.6 |
| 128 | 2,984.0 | 363.6 |

These are presentation CPU samples, excluding GDTF evaluation and real rendering,
not frame/FPS/GPU predictions. Shutter resources already install independently of
this threshold; their ownership and eligibility are unchanged. The supplied MVR's
115-row graph has **75 eligible individual candidates** after the documented held
synthetic open-profile snapshot (20 aggregate rows and 20 emission-only rows are
excluded). It admits 75 rather than inferring eligibility from 1,095 physical outputs.
Actual gobo selection and live policies can reduce that count; read the setup gauge
on the owner's stream. Full serial/async, gobo and temporal regression suites remain
required alongside the exact-value admission test.

## Acceptance limits

The reported Windows medians remain 27 Full, 28 with lens writes suppressed,
69 No-beams and 74.5 transforms-only. This branch makes no new Windows FPS claim.
It removes reproduced cold work and demonstrates a bounded native application CPU
improvement; the shaft versus footprint graphics contribution, RenderingServer /
Vulkan synchronization and real GPU cost remain hardware measurements. The five
startup commands now make that comparison possible with normal DMX evaluation.

Validation: complete Debug build; all 13 native CTests (required inventory validated);
all 47 pinned Godot 4.7.1 GDScript CI tests; nine CI-script Python tests; architecture,
size and diff checks; five software graphical configurations. The PR records the
exact tested commit and hosted CI status separately from these local results.
