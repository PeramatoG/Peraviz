# Targeted idle runtime corrections

This change removes confirmed redundant work and adds a default FPS cap. It does
not change rendering quality, native DMX evaluation, temporal scheduling, physics
frequency or idle rendering policy. No CPU/GPU improvement is claimed without
measurements.

## Corrections and ownership

- `scripts/ui/user_preferences.gd`, `frame_rate_limit.gd` and `fps_overlay.gd`:
  View > FPS limit offers 30, 60 (default), 120 and Unlimited (`Engine.max_fps = 0`).
  The saved choice applies at startup and changes live, outside MVR/PVZ settings.
  V-Sync remains unchanged. `project.godot` remains unchanged; startup applies
  the user preference instead of a second authoritative project cap.
- `native/src/application_options.{h,cpp}`, `register_types.cpp` and
  `native/CMakeLists.txt`: a small startup-only query reads original process
  arguments on Windows/Linux/macOS. Godot 4.7.1 consumes `--max-fps` and
  `--fixed-fps` before `OS.get_cmdline_args()`; relying on that GDScript API
  would overwrite explicit benchmark caps, especially `--max-fps 0`. Those
  engine overrides retain precedence and disable the FPS submenu for that run.
  Arguments after `--` / `++` do not count. No shell, new library or native
  runtime/transport change is introduced. Without the native extension, only
  a detectable nondefault engine cap can be preserved by the fallback.
- `scripts/editor_camera.gd`: smoothing snaps yaw/pitch/roll and distance to
  exact targets within small convergence thresholds. A value-state guard skips
  unchanged transform writes, including direct calls. Translation, layout,
  viewport, projection and external transform changes invalidate the guard.
  Existing target-position behavior, mouse/keyboard input and smoothing remain.
- `scripts/controllers/dmx_controller.gd`: OFF initialization and each transition
  reset counters and refresh the quick panel, monitor, toggle and status once.
  Explicit stop and the stopped-frame path share that reset. Failed start also
  establishes OFF immediately while retaining its error tooltip. Restart marks
  the stopped state dirty; unchanged running/receiving status is not re-emitted.
- `scripts/runtime/native_gobo_resource_registry.gd`: its existing continuous
  set supplies one early return before the clock read. No second activity
  registry, tree scan or per-frame allocation is added.

## Deliberately unchanged temporal paths

`load_scene.gd` continues advancing gobo and shutter presentation independently
of receiver state. Active held DMX must keep playing. The renderer-target wrapper
already delegates to the gobo registry; another guard there would duplicate it.
`fixture_light_apply_service.gd` delegates shutter advancement to native
`PeravizPresentationState::advance_shutters()`, whose existing `pending()` guard
returns before time sampling, waveform work or renderer updates when idle.
Adding a GDScript shutter registry or another native query would duplicate this
ownership. These files and the native shutter scheduler remain unchanged.

## Regression coverage

`test_idle_runtime_efficiency.gd` checks defaults, every saved/live/restored FPS
choice, invalid-value fallback, real Godot override subprocesses (including
Unlimited), settled-camera transform notifications, immediate translation/orbit
resumption and layout changes. Controller probes exercise missing receiver,
start, receiving changes, explicit/external stop, failed start, restart and
unchanged status. They count UI refresh boundaries; production packet processing
and decoding are not mocked into a new authoritative runtime.

`test_gobo_posrotate_lifecycle.gd` additionally exercises the production clock
entry point with held continuous rotation and an empty continuous set.
`test_native_shutter.gd` explicitly stops DMX before its existing autonomous
10 Hz held-state checks. Existing camera/navigation, shell, gobo, shutter and
project/runtime regressions are retained.

Commands on Linux with Godot 4.7.1 and the retained toolchain:

```bash
PATH=/workspace/.peraviz-tools/python/bin:$PATH cmake --build native/build --parallel 5
work/godot --headless --audio-driver Dummy --rendering-method gl_compatibility \
  --path . --editor --import --quit
work/godot-tests --headless --audio-driver Dummy --path . \
  --script tests/gdscript/test_idle_runtime_efficiency.gd
python3 .github/scripts/run_gdscript_tests.py \
  --godot /workspace/Peraviz/work/godot-tests --project /workspace/Peraviz \
  --output /workspace/Peraviz/work/idle/tests-final --timeout 60
/workspace/.peraviz-tools/python/bin/ctest --test-dir native/build --output-on-failure --timeout 120
bash tests/check_no_large_files.sh
bash tests/check_runtime_architecture.sh
git diff --check
```

Results: **62/62 GDScript tests** and **15/15 native CTests** pass. Architecture,
file-size and whitespace checks pass (existing large-file warnings remain).
The FPS submenu was also inspected in the real Compatibility/llvmpipe UI.
Local logs are in `work/idle`; generated artifacts are not committed.

Windows/macOS raw-argument paths are implemented with platform APIs but have not
been executed in this Linux environment. Real-device reception and GPU timing
are outside this focused change.
