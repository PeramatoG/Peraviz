# Blackout motion transform path

Base: `70126398711d1564118bb9be5a7c6767facc625d` (Vector Prism visual-profile
checkpoint). This milestone preserves mechanical GDTF ownership, the beam visual
profile and footprint design. RenderEmitterGrouping and MultiMesh remain deferred.

## Evidence and limits

The reported canonical references are 75 FPS idle, 75 FPS with aggressive camera
motion, 26 FPS with continuous Pan/Tilt at Grand Master zero, and 23–24 FPS with
continuous Pan/Tilt plus visible shafts. These are user measurements, not new
branch results. The canonical inventory is 82 MVR fixtures, 71 live renderer
fixtures, 43 Pan targets, 43 Tilt targets and 1,095 physical outputs, with up to
51 outputs per fixture. The canonical MVR, live chase and Windows RTX workload
are unavailable in this cloud checkout. Its exact hierarchy counts and this
branch's canonical FPS/viewport timing must be collected on Windows below.

Code inspection confirms `merge_transform_state()` already skips unchanged
physical Pan/Tilt. The old renderer path nevertheless writes both mechanical
axes on an emitted row. A moving ancestor dirties the emitter's SpotLight anchor
and presentation descendants even when the beam mesh is hidden and the surface
light RID is disabled. A camera move does not write these ancestors.

A bounded synthetic experiment measured this propagation before enabling the
bridge. It used 43 Pan/Tilt pairs and 1,095 anchors, each with a hidden mesh. The
original probe alternated inherited and frozen ownership twice: inherited anchors
received about 657,000 notifications over 600 frames; frozen carriers received
only setup notifications. Mechanical write time fell by roughly 4–6 times in
that initial probe. This proves recurring hidden presentation propagation exists;
it does not attribute the canonical 38 ms frame to that cost.

The retained probe uses the actual bridge, drains setup notifications, and exposes
the active-output tradeoff. One headless Godot 4.7.1 GL-compatibility sample:

| Ownership | Active outputs | Mechanical writes, total ms / 600 frames | Presentation stage, total ms / 600 frames | Anchor transform notifications |
| --- | ---: | ---: | ---: | ---: |
| normal | 0 | 139.911 | 1.599 | 657,000 |
| mechanical-only | 0 | 60.006 | 1.689 | 0 |
| active-only | 0 | 51.405 | 1.673 | 0 |
| active-only | 7 | 44.285 | 8.134 | 4,193 |
| active-only | 1,095 | 47.709 | 601.270 | 655,905 |

These are CPU stage totals, not frame-time or FPS recovery claims. Engine pacing
kept elapsed time near 4.14 seconds in every run. The all-active case still pays
individual synchronization (about 1 ms/frame here); grouping/batching is the
intentionally deferred optimization. Normal and mechanical-only reported explicit
presentation-stage time is just an empty controller pass; normal's automatic
notification/render-server work occurs elsewhere in the engine.

## Ownership and hierarchy audit

| Resource | Attachment before | Attachment now | Transform authority |
| --- | --- | --- | --- |
| GDTF body and lens meshes | Mechanical geometry/axes | Same | Mechanical SceneTree |
| Lens/emissive materials | Resources on physical meshes | Same | Native held photometric state; materials themselves do not inherit Node3D transforms |
| Picking/collision | Imported mesh/proxy hierarchy | Same | Mechanical SceneTree |
| Emitter SpotLight anchor | Physical emitter geometry | Carrier under that same geometry | Carrier world pose plus existing local optical state |
| Vector Prism / Lightweight Prism / proxy mesh | SpotLight child | Same SpotLight child | Existing local optics plus carrier world pose |
| Gobo shadow plane / projector texture | SpotLight child / light resource | Same | Existing Optical Projection State and bounded surface policy |
| Beam debug axis and local helpers | SpotLight children | Same | Carrier world pose |
| Global coordinate-debug gizmos | Separate debug root | Same | Existing explicit debug owner |

`PresentationTransformBinding` caches the mechanical source, original local anchor
transform, physical output ID, dense index, activity and last applied world pose.
It inserts a top-level **presentation-only carrier** without detaching the body or
emitter geometry. Keeping the light's local coordinate system intact is essential:
Optical Projection State still owns lens offsets, gobo roll/parity, Zoom and the
relative shaft transform. Godot's Light3D scale-disabled behavior also remains intact.

The binding resolves the source's **current** global transform only when active.
A typed swap-removal array excludes dark bindings from the production pass. Before
the renderer draws a reactivated output, the post-semantic commit synchronizes its
carrier. Latest held color, intensity, Zoom and gobo state remain in their existing
owners. No fresh Pan/Tilt packet is required. Active projectors keep following even
with shaft gain zero. Open Spot/Wash ownership policy is unchanged.

Carriers stay inside the original fixture subtree. Scene clear/rebind disconnects
bound callbacks, reparents surviving anchors to their original parents with local
optical transforms intact, frees carriers, and retires the generation. Native
workers never touch nodes. Active sources are validated after commits and in the
loader process for editor motion or frames without new semantic data. Camera
motion changes neither the source state nor the set of transform writes; unchanged
active source checks cost the same when the camera is idle or moving.

Trace setup caches axis-to-emitter ownership and classified descendant handles.
Resource replacement invalidates this cache; held gobo rotation callbacks do not.
There is no recurring SceneTree enumeration. Once per interval the reporter unions
cached handles for moved axes, avoiding double counting descendants under both Pan
and Tilt. `*_under_moved_axes` describes SceneTree ownership, including top-level
carriers, rather than claiming that those objects still inherit automatic updates.
Lens material resources are counted through setup-cached material ownership.

## Trace interpretation

Enable `--peraviz-perf-trace`. `[peraviz-transform]` reports one interval:

- `transform_rows_generated`, `transform_rows_skipped_unchanged`: native emitted and
  evaluated-but-unchanged rows. Identical raw DMX rejected before evaluation is not
  an evaluated transform row and does not increment the latter.
- `fixtures_moved`, `moved_pan_tilt_axes`: unique identities; `pan_writes` and
  `tilt_writes` count actual guarded mechanical writes, not requested targets.
- `presentation_emitter_handles_on_moved_fixtures`, `active_emitters_on_moved_fixtures`,
  `dark_emitters_on_moved_fixtures`, `active_projectors_on_moved_fixtures`,
  `visible_shafts_on_moved_fixtures`: interval fixture membership with current activity.
- `presentation_bindings_affected`: unique bindings owned below moved axes.
  `presentation_transforms_written` counts actual carrier writes; shaft/projector
  move counters may both increment for a single carrier if it serves both.
- `presentation_transforms_skipped_dark`: dark binding/motion-pass events,
  deduplicated across both axes in a pass. This classification is trace-only;
  production does not visit those dark bindings at all. `dark_outputs_ignored` is
  a unique current-dark count, not a sum across passes.
- `presentation_transforms_skipped_unchanged`: active source checks that need no
  write, using Godot's `Transform3D.is_equal_approx()` tolerance.
- `presentation_descendants_under_moved_axes`, `spotlight_anchors_under_moved_axes`,
  `beam_meshes_under_moved_axes`, dark/active beam counts, gobo resources, lens meshes
  and material resources, debug axes, collision/picking objects, presentation helpers
  and remaining mechanical helpers: cached hierarchy inventory. The
  `hierarchy_audit_builds` gauge should stay constant during ordinary motion/roll.

Timing is aggregate, with no clock per emitter:

| Field | Boundary / units |
| --- | --- |
| `native_transform_decode_us` | Native transform property evaluation plus held-state merge, interval total microseconds; excludes DMX reception and unrelated color evaluation |
| `mechanical_transform_writes_us` | One clock pair around each packed transform batch, including ID resolution, guards and trace classification; interval total microseconds |
| `presentation_transform_us` | One clock pair around active source validation, transform comparisons/writes and trace dark classification per pass; interval total microseconds |
| `render_setup_cpu_ms` | Godot renderer frame-setup CPU sample in milliseconds |
| `viewport_cpu_ms`, `viewport_gpu_ms` | Godot measured viewport frame samples in milliseconds; headless values are not hardware evidence |

Trace OFF skips native counters/timers, static ownership audit and moved-output
classification. It retains the active-only production bridge. In `normal`, explicit
carrier writes are zero because the engine owns inherited transforms; compare
mechanical/render/viewport time and inventory rather than interpreting zero as
absence of presentation work. In `mechanical-only`, presentation is intentionally
frozen while body geometry continues moving; it is a diagnostic, not a usable show
mode. These flags are application arguments, absent from saved settings and the UI.

## Direct RenderingServer evaluation

The retained probe also compares 657,000 Node global-transform assignments against
657,000 direct instance RID assignments with separate, explicitly freed resources.
The first sample measured 63.370 ms versus 24.156 ms of dispatch time (about
0.106 versus 0.040 ms/frame at 1,095 outputs). This excludes deferred notifications,
source resolution, child optics, projector alignment and GPU execution. Repeated
samples showed the same dispatch ordering, but are not a production migration proof.

This milestone keeps **one Node carrier transform authority** per emitter. Direct
RID writes are not added to a live Node-owned resource. A future RID backend must
own its full instance lifecycle and compose shaft/projector local transforms itself;
the isolated dispatch saving does not justify introducing that second optical path
before canonical profiling. Existing RID visibility/material ownership is unchanged.

## Exact canonical Windows A/B commands

Build the native extension from this branch first, using the normal Windows build
procedure. Keep Godot 4.7.1, Vulkan Forward+, window resolution, camera, scene,
visual settings, stream and warm-up identical. Load the canonical scene after each
launch. Peraviz options must follow `--`.

```powershell
$godot = "C:\Users\Peramato\Desktop\Programas\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

# Production / trace OFF (default active-only)
& $godot --path C:\codigoscpp\peraviz --print-fps

# A: inherited presentation, tracing enabled
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-transform-diagnostic=normal

# B: isolate physical body/axes; presentation stays frozen
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-transform-diagnostic=mechanical-only

# C: active-only presentation, tracing enabled
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-transform-diagnostic=active-only

# Matched trace-OFF inherited reference
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-transform-diagnostic=normal
```

For each mode, warm up and record stable intervals for idle/no DMX, aggressive
camera/no DMX, continuous Pan/Tilt at GM zero, continuous Pan/Tilt with shafts,
and projector-only presentation (shaft gain zero). Include a 51-output fixture
all-dark and mixed-active case if available. Restore GM/dimmer without sending
fresh Pan/Tilt; check immediate current orientation, Zoom, roll and footprint
alignment. Repeat after scene reload. Record:

| Case | Mode / trace | FPS | Process ms | Native transform us | Mechanical us | Presentation us | Setup ms | Viewport CPU/GPU ms | Moved fixtures/axes | Active shafts/projectors | Dark ignored / carrier writes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Canonical Windows | pending | | | | | | | | | | |

If mechanical-only stays near 26 FPS, presentation inheritance does not explain
most of the loss: inspect the retained body/lens/collision hierarchy and native vs
mechanical timing before changing presentation again. If it improves substantially,
compare active-only GM-zero against mechanical-only, then quantify the remaining
all-active cost. Do not infer success merely from the smaller GPU difference between
GM-zero and visible shafts. The camera case remains an independent control.

For the small synthetic CPU probe only:

```powershell
& $godot --path C:\codigoscpp\peraviz --script tests/manual/transform_propagation_benchmark.gd -- --peraviz-transform-diagnostic=normal --active=0
& $godot --path C:\codigoscpp\peraviz --script tests/manual/transform_propagation_benchmark.gd -- --peraviz-transform-diagnostic=mechanical-only --active=0
& $godot --path C:\codigoscpp\peraviz --script tests/manual/transform_propagation_benchmark.gd -- --peraviz-transform-diagnostic=active-only --active=7
```

## Validation

- Native CTest: all 11 tests pass, including changing dark Pan/Tilt, unchanged
  semantic/raw inputs and trace-OFF telemetry guards.
- Headless GDScript: all 28 tests pass. The focused 51-output regression checks
  actual dark descendant notifications, zero writes/visibility/light activations,
  latest-pose activation with held color/Zoom, mixed activity, genuine gobo and
  projector-only motion, Grand Master/dimmer blackout, camera independence,
  unchanged guards and generation replacement. Existing optical/profile tests pass.
- Clean-cache application checker: both renderer lifecycles, 13 real-process argument
  cases (including all transform modes, separator placement and reload), ownership
  release checks and deliberate dense-failure contracts pass.
- Repository size/architecture checks and `git diff --check` pass. Existing file-size
  extraction warnings remain; no unrelated lint cleanup was performed.

The original request's Part 15 ended at “Use the”. The commands above use the
repository's existing canonical Windows executable/project paths and preserve the
reported benchmark controls. Windows FPS, GPU timing, visual acceptance and exact
canonical descendant inventory remain pending the user's run.
