# Dense presentation runtime recovery after 832882d

**Historical recovery record; correctness work described here is implemented.**
The current owner-reported stable full run is 24–25 FPS; see
[performance foundation](performance-foundation.md) for closure status, corrected
application-argument contract and the remaining visual/scalability roadmap.

The latest Windows logs at `832882d` are **INVALID performance measurements**:
required beam/runtime scripts failed to compile. The missing `dense_presentation`
block and 1,095-entry legacy state dictionaries show that the intended production
path was inactive. FPS from that run cannot validate the renderer correction.
Performance work is paused until the canonical full visual check passes.

## Verified failures

`BoundBeamState` existed as a global `class_name`, but normal runtime startup
used the checkout's existing `.godot/global_script_class_cache.cfg`. Without the
new entry, the adapter and base/derived renderer signatures could not parse.
Dependent scripts then failed to compile and their `.new()` calls were invalid.
The previous CI editor import registered the new global class before individual
tests ran; a zero exit status from editor import alone also did not reject all
script diagnostics. It did not exercise a normal application launch with the
internal helper absent from that registry.

This was reproduced with Godot 4.7.1 by removing only the helper's class entry.
The new clean-runtime checker rejects unchanged `832882d`: import passes, then
normal startup fails with `Could not find type "BoundBeamState"`.

`bound_beam_state.gd` now exposes a small local `Cache` class through explicit
script preloads. It has no global `class_name`, self-preload, or renderer/service
dependency. The base renderer accepts `RefCounted`; implementations and the
adapter preload the helper directly. Applied shader signatures remain presentation
caches; native dense state still owns control values.

A second failure appeared when testing the real application MVR path, rather
than only a synthetic adapter loader. `_find_or_create_emitter_light()` reset an
existing light's visibility and energy when `peraviz_base_light_energy` was
absent. That legacy metadata is not the dense state's authority. Resource
rediscovery could therefore hide the structural parent of an otherwise visible
beam and disable its footprint. The real lifecycle test failed its actual
`is_visible_in_tree()` checks before this fix. Existing-light discovery now
preserves visibility/energy and projector roll; initial zero state is assigned at Node creation.
No fixture-specific behavior or GDTF calculation changed.

## Installation and initialization contracts

Dense installation returns a success result through the production registration
path. A required installation failure emits one clear error, reports inactive,
and rejects subsequent snapshots instead of silently selecting legacy state.
Compatibility-only test callers that never request a dense installation retain
their explicit legacy API. Stability telemetry includes
`dense_presentation_active` alongside the existing dense block. The application
lifecycle asserts both are present and legacy state dictionaries remain empty.

Trace-only interval diagnostics distinguish:

| Counter | Meaning |
| --- | --- |
| `beam_initializations` | Lazy initialization requests |
| `beam_initialization_succeeded` | Requests ending with a valid, dynamically ready bound resource |
| `beam_initialization_failed` | Requests still unresolved afterward |
| `beam_resource_rebounds` | Actual changes of bound MeshInstance identity |
| `beam_topology_rebuilt` | Optics calls replacing the actual mesh resource, rather than merely claiming a topology update |

A failed lazy initialization is latched until an optics/resource/renderer refresh
permits retry, with one explicit error instead of an indefinite per-snapshot
initialization loop. Successful resources and their applied caches remain bound
through ordinary color/intensity changes. Existing unchanged-write guards and
no-beams suppression remain intact.

## Clean-cache validation

After building the native extension, run from the repository root:

```bash
python3 .github/scripts/check_clean_runtime.py --godot "$GODOT_BIN" --project . --output /tmp/peraviz-clean-runtime
python3 .github/scripts/run_gdscript_tests.py --godot "$GODOT_BIN" --project . --output /tmp/peraviz-gdscript --timeout 60
ctest --test-dir native/build --output-on-failure --timeout 120
```

`GODOT_BIN` must point to pinned Godot **4.7.1 stable**. The checker intentionally
removes only the specified project's generated `.godot` directory, imports from
scratch, and rejects script/parse/compile/load errors even on exit code zero.
Deleting a cache is a test setup, not the dependency fix. It then removes any
internal helper registration, launches the normal project in a separate process,
and loads the normal main scene and a generated MVR through production APIs.
No renderer/service preloads in the test reorder the application dependency graph.
CI runs this step before the complete individual GDScript suite.

Both Vector Prism and Legacy Prism tests inspect actual MeshInstance, mesh,
material, shader values, Node tree visibility, light energy/color, projector
textures and stable resource identities. Reported visibility counts use tree visibility,
so a hidden parent cannot produce a misleading visible-beam count. Native DMX frames drive two independent
fixtures through dimmer, RGB, pan/tilt, zoom and gobo selection. Ninety changing
snapshots preserve active beams/footprints, including projector-required lights
with optional realtime spotlights disabled. Tests cover blackout/reactivation,
full/no-beams/full without fresh DMX, held open-gobo restoration, ancestor
visibility and the real visual-settings refresh. Steady state has zero lazy
initialization/rebind/topology counts. The 1,095-output mutation/capacity regression
continues in the complete suite.

Two deliberate negative subtests separately require exactly one expected error:
invalid dense bindings cannot enable legacy fallback, and an unready renderer
cannot retry initialization every snapshot. Unexpected diagnostics still fail.
These intentional errors are isolated from the clean import/startup/lifecycle logs.

Headless tests establish resource and mutation correctness, not GPU culling,
rendered-pixel parity or Windows performance. Rendered-pixel acceptance remains
a canonical-machine responsibility. The later stable full observation is recorded
in the current foundation roadmap.

## Historical Windows recovery acceptance

At the recovery stage PR #100 remained draft for this check; it has since merged.
The current foundation status and acceptance commands are maintained in
[performance foundation](performance-foundation.md). The corrected command is:

```powershell
$godot = "C:\Users\Peramato\Desktop\Programas\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
& $godot --path C:\codigoscpp\peraviz --print-fps -- --peraviz-perf-trace --peraviz-render-diagnostic=full
```

Require zero `SCRIPT ERROR`, normal scene load, an active dense block, visibly
present beams and footprints, and correct DMX behavior for 30–60 seconds. Check
blackout/reactivation and stable gobo projection. Only after that passes should
no-beams performance comparison resume. Do not interpret the failed-compilation
Windows logs as performance evidence. Do not begin milestone 2.
