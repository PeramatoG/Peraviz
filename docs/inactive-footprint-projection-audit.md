# Inactive Custom Footprint projection work

Base: main `cda38ee` (merged PR #126). No private fixture assets are used.

## Ownership and required work

| Path | Existing authority and safe boundary |
| --- | --- |
| Pan/Tilt | Native registered mechanical targets and ordinary Godot transform propagation. Every independent physical optical origin inherits its complete ancestry. Unchanged by this PR. |
| OpticalProjectionState | Canonical aperture, artwork, lens offset, roll/parity, Beam/FieldAngle profile and projection geometry. Evaluation continues while dark; only renderer commits can wait. |
| Volume notification | Previously always read the parent's global transform, compared the world, inverted changed matrices, submitted matrix/origin uniforms and updated receiver bounds. Node visibility did not prevent it. |
| Native PresentationMaterialBindings | Owns effective physical footprint energy: physical visibility/SpotEnergy-or-BeamEnergy × surface gain × the native shutter envelope. Its retained instance RID visibility additionally requires structural/receiver allowance. |
| ShutterPlayback | Samples admitted native authorities and broadcasts only changed physical owners through indexed routes, including held DMX. No flash reinstalls resources or evaluates source programs. |
| Receiver and camera culling | Receiver depth bounds and volume intersection can change after light/scenery movement; camera frustum culling is renderer-owned. Neither proves lasting inactivity. An energized culled volume must continue updating. |
| Diagnostics | `no-custom-footprints` suppresses native energy/material presentation and draws. Canonical physical, optical and mechanical state still advance. It now also admits safe projection deferral. |

Previously hidden native RIDs left Godot `visible` and transform notifications
unchanged. Shader uniform writes and transforms are CPU work, not draw calls;
`active_custom_footprints` is before camera culling, not a viewport draw count.
Zero energy, Node visibility, native instance visibility and camera culling are
therefore separate states throughout this change.

## Small synchronous admission mechanism

The existing material visibility function is the common boundary for normal
physical snapshots, asynchronous completed snapshots, shutter ticks, surface gain
replay, consumer suppression and visibility notifications. A cold, generation-
checked install pairs each retained instance with its volume's weak ObjectID.
Retirement clears both together. There is no owning native reference, new scene
scan, worker scene mutation or physical-state cache.

Positive committed energy activates projection work. While a native authority
requires continuous sampling, positive base energy × surface gain keeps its
physical projectors ready through the entire effect, including closed flashes.
That fact is borrowed directly from ShutterPlayback's existing indexed activity
vector. Stable zero energy, stable Closed, zero gain and disabled consumers can
sleep. Receiver and structural allowance remain separate. Dark notifications mark pending renderer
work and retain normal mechanical propagation. Optical sync/softness and receiver
edits retain canonical state and pending renderer revisions. On activation the
native function synchronously calls the indexed volume **before** showing its RID.
The volume reads current ancestry even if an ancestor's notification is still
queued; activation uses exact world equality (ordinary active updates retain their
existing equality guard), and pending optical/receiver changes use normal synchronization. Dense
native admission occurs before the script applies Pan/Tilt sections. Any later
mechanical edits in that same transaction use the restored normal notifications,
which Godot flushes before drawing; Pan/Tilt ordering and processing are unchanged. Native
admission rereads allowance afterwards because bounds can synchronously change
Godot visibility. Setting the admission cache before calling avoids recursive
activation through the existing visibility signal.

Continuous 1 Hz/20 Hz/Random Strobe never sleeps or wakes on individual flashes:
static effects do no projection checks/setters/bounds work, and moving effects
retain normal eager updates. This measured restriction avoids moving repeated
catch-up work into the high-frequency native mutation path. A first prototype
that deferred every closed flash reduced setters but failed to improve combined
notification + callback CPU cost at 20 Hz, so that policy was discarded.
Stable activation synchronizes the latest physical pose once; following queued
notifications retain the existing world-equality guard. This is event-driven deferral, with no throttle, approximation,
shared inverse or second optical/physical authority. Resource identity, shader,
texture sampling, full geometry and all semantic evaluation remain unchanged.

## Measurements and limitations

The checked-in evidence compares eager and deferred scheduling with identical
opt-in diagnostics and generated raw-DMX inputs. Whole-batch CPU measurements
wrap actual `force_update_transform()` dispatch, inherited transform reads and
resulting projection work with **two clocks per batch**. Trace-off production
has no per-output clocks. Color/Dimmer/source application is timed separately;
callback and notification timings must be considered together when activation
moves work into the native callback.

Fine clocks are a separate `volume.profile_enabled` diagnostic, default false,
independent of ordinary count-only tracing. They measure notification/world
scopes, parent global reads, affine inverse, matrix/origin setters and bounds.
Scopes overlap, clock/dispatch overhead is included, and microsecond quantization
limits tiny-operation attribution. The probe reports an empty clock-pair floor;
these fine timings are **not** unbiased trace-off frame cost. The global-read
counter names the parent read; the bounds scope also includes the volume's own
global transform and renderer-facing bounds/visibility work.

Native footprint material CPU scopes are separate from other material consumers
in synchronous and asynchronous presentation. Shutter footprint mutation has a
separate cumulative scope. These scopes include routing, cache filtering and
setters, not only driver execution. Draw submission and rendering remain viewport
measurements; all software Vulkan timings are explicitly software evidence.

The generated matrix covers blackout/moving Pan/Tilt, full/moving Pan/Tilt,
static Color/Dimmer, held 1 Hz/20 Hz/Random Strobe, motion with each shutter and
no-custom-footprints isolation. It runs shared authority and independent cells,
with trace/fine clocks both off and on. Source counts are null when tracing is off
because those counters are intentionally not maintained. Fixed 120 Hz timestamps
measure current presentation semantics, not the display's attainable frame rate.
Physical/axis and shutter digests, resource counts and installed-binding counts
are compared separately from performance. Headless draws are null, not zero.

The 128-output, 240-sample CPU run (Godot 4.7.1, headless/dummy renderer)
measures these mean batch CPU durations with tracing and fine clocks **off**:

| Workload / independent cells | Eager notification µs | Deferred notification µs | Eager callback + notification µs | Deferred callback + notification µs |
| --- | ---: | ---: | ---: | ---: |
| blackout_motion | 473.9 | 124.8 | 775.4 | 412.0 |
| lit_motion | 426.3 | 454.6 | 700.4 | 737.2 |
| held_20hz | 36.7 | 38.0 | 199.9 | 208.7 |
| motion_20hz | 471.9 | 442.9 | 931.2 | 850.9 |
| no_custom_motion | 458.9 | 128.6 | 763.1 | 443.8 |

For both shared and independent control, blackout and no-custom isolation reduce
30,720 parent reads/inverses/matrix setters and 30,480 origin setters to zero;
61,200 projection uniform setters and 30,720 bounds calculations are eliminated
per case. Continuous moving shutters retain all 30,720 necessary projection
updates. Static continuous shutter cases have zero world reads, projection setters,
bounds calculations and activation checks. All 40 case pairs retain identical
physical/mechanical and shutter digests, source evaluation counts, material setter
counts, resource counts and binding-install counts. No binding installs occur in
measured playback. Active-case timing variations are not claimed as improvements.

Ten existing six-projector graphical images are pixel-identical before/after.
Three active-reference/first-reactivated-frame comparisons (Dimmer, held gain,
camera/receiver edit) also have zero changed pixels and equal 11-draw counts.

The 320×240 Forward+/Vulkan **llvmpipe software** run, 120 samples/case,
also reduces actual notification CPU work with tracing disabled:

| Workload / independent cells | Eager notification µs | Deferred notification µs | Eager callback + notification µs | Deferred callback + notification µs | Draws before / after |
| --- | ---: | ---: | ---: | ---: | ---: |
| blackout_motion | 805.1 | 186.9 | 1738.0 | 913.9 | 129 / 129 |
| lit_motion | 978.9 | 805.4 | 1906.6 | 1575.4 | 385 / 385 |
| no_custom_motion | 766.6 | 202.8 | 1540.9 | 957.0 | 257 / 257 |

Software frame means (eager→candidate) vary: independent blackout
37.08→30.84 ms, full 110.38→88.01 ms, isolation 79.38→75.91 ms; shared
blackout 36.45→30.28 ms, full 88.86→93.31 ms, isolation 69.73→69.87 ms.
These establish no general frame-rate or GPU improvement. They preserve all
resource counts and draws, while the isolated CPU update scopes demonstrate the
inactive-work reduction. Full paired timings, scopes, counters and semantic/image
checks are in [the evidence](performance/inactive-footprint-projection-evidence.json).
The eager comparison uses the same diagnostics and probe with the frozen
pre-deferral volume and no weak-projector registration; native binaries are
otherwise identical. Reproduce by applying only the diagnostic changes to base.

Real Windows RTX 3070 frame times, GPU execution and driver submission savings
remain unmeasured here; this PR claims only the recorded CPU reduction and exact
projection-write elimination while inactive. It does not explain the owner's
whole 27–29 FPS result or change shutter frequency mapping.

## Reproduce and verify

Use the pinned Godot 4.7.1 and a Debug native build. For the generated CPU probe:

```sh
"$GODOT_BIN" --headless --audio-driver Dummy --rendering-method forward_plus --path . \
  --script tests/gdscript/test_native_shutter.gd -- --inactive-footprint-cpu-probe \
  --footprint-count=128 --footprint-samples=240 --footprint-output=res://work/inactive-cpu
```

Omit `--headless` and use Forward+/Vulkan for actual frame/draw data. Add
`--footprint-trace-off-only` and
`--footprint-cases=blackout_motion,lit_motion,no_custom_motion` for a bounded
uninstrumented graphical comparison. The workload
uses a 320×240 window, no V-Sync/cap, 30 warmup samples and 240 measured samples per
case. Use the existing graphical six-projector probe for optical references:

```sh
"$GODOT_BIN" --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan \
  --path . --script tests/gdscript/test_custom_surface_footprints.gd -- \
  --render-footprint-probe --footprint-output=res://work/footprint-images
```

Add `--inactive-footprint-visual-probe` for pixel-exact active/reference versus
first-draw restoration after blackout, held gain recovery and camera/receiver
movement. PNG/readback and semantic checks are outside CPU timing scopes.
`test_inactive_footprint_projection.gd` is included in the pinned Forward+ CI
inventory and covers pending Pan/Tilt, optics while dark, independent/shared
shutters, held activation, high-frequency static replay, receiver/camera changes,
renderer rebinding and scene reload. Existing native shutter and footprint tests
retain renderer replacement and source/phase/resource contracts.
