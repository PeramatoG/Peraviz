# Auto Span validation record

Validated on Linux with GCC 14, Debug native builds and the pinned Godot
4.7.1 (`a13da4feb`), rebased onto `986728f` (includes the additive-emitter
intensity fix). All fixtures and archives used here are synthetic.

## Original failure before implementation

The initial native reproduction was compiled and run against the unmodified
routing/evaluation implementation before changing it:

```sh
work/tools/bin/cmake --build work/native --target peraviz_native_visual_runtime_tests -j 4
work/native/peraviz_native_visual_runtime_tests --auto-span
```

The test exited 1 with both limitations reproduced:

```text
Strict boundary rejection reproduced: Patch-adjusted ordered byte source exceeds its 512-slot break.
Cross-universe RGB target was dropped at installation
```

Inspection also confirmed that `make_sources()` retained out-of-range slots
without advancing the universe, and scalar decoding read every component from the
single evaluation-owner frame. Address wrapping alone could not fix playback.

## Final checks

Commands ran from the repository root. The local `work/tools` environment supplies
CMake/Ninja. Setup used the retained vcpkg dependencies and an environment-only
Godot binding profile containing the existing classes plus RenderingServer,
Light3D and MeshInstance3D; the older retained profile initially omitted those
classes and failed the extension build. No tracked dependency/profile changes
were needed. The system Godot was 4.6.3, so all Godot checks used the pinned binary.

```sh
XDG_CACHE_HOME=/workspace/Peraviz/work/cache work/tools/bin/cmake -S native -B native/build -DGODOTCPP_BUILD_PROFILE=/workspace/Peraviz/work/godot-build-profile.json
work/tools/bin/cmake --build native/build -j 4
XDG_CACHE_HOME=/workspace/Peraviz/work/cache work/tools/bin/cmake -S native -B native/build
work/tools/bin/ctest --test-dir native/build --output-on-failure --timeout 120
tests/check_no_large_files.sh
tests/check_runtime_architecture.sh
git diff --check
git diff origin/main --check
```

Build passed, including the Godot extension. CTest: **14/14 passed**, including
`peraviz_native_auto_span_tests` and all existing native suites. Architecture and
whitespace checks passed. The large-file check passed with existing advisory
warnings for the visual runtime test harness and three large GDScript files.

Godot commands used these environment variables (all writable task-local paths):

```sh
export XDG_CACHE_HOME=/workspace/Peraviz/work/cache
export XDG_DATA_HOME=/workspace/Peraviz/work/godot-data
export XDG_CONFIG_HOME=/workspace/Peraviz/work/godot-config
export GODOT_BIN=/workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64
timeout 120 "$GODOT_BIN" --headless --audio-driver Dummy --rendering-method gl_compatibility --editor --path . --quit
```

Import passed without script/engine errors. Each test below ran with the exact
command shape (120-second timeout) and exited 0. Logs were also checked using
`classify_result` from `.github/scripts/run_gdscript_tests.py`; no unexpected
script/engine diagnostic or leaked-instance failure was found.

```sh
timeout 120 "$GODOT_BIN" --headless --audio-driver Dummy --rendering-method gl_compatibility --path . --script tests/gdscript/<test>.gd
```

| Test | Result |
| --- | --- |
| `test_cross_universe_color` | Pass; native Color, implicit intensity, real native material binding, reverse arrival, unchanged packet, blackout, renderer refresh and scene reinstall |
| `test_rgb_strip_emission` | Pass; production 60-pixel RGB Glow import, independent native physical/material output and held replay |
| `test_import_compatibility_baseline` | Pass; explicit breaks, Overwrite/reference identities, ordered bytes, held state, renderer replacement, reload and forced native async path |
| `test_native_compiled_scene_contract` | Pass; retained numeric setup versions |
| `test_native_target_application` | Pass |
| `test_dense_renderer_mutations` | Pass |
| `test_color_material_routing` | Pass |
| `test_native_shutter` | Pass; same command with `--rendering-method forward_plus` |

The dedicated native Auto Span suite covers 180 contiguous bytes at 1.1, 1.400,
1.511 and 1.512, configured offsets −1/0, exact receiver subscriptions, strict
rejection by default, per-target canonical identity, source archive/patch fidelity,
16-bit coarse/fine Color and Dimmer, two independently co-patched fixtures,
multibreak/unsupported-policy diagnostics, highest-universe acceptance/overflow
rejection, and 1,200 split-source emitters through forced native workers and the
actual async physical/material snapshot publication path.

These results establish deterministic native and headless behavior only. No
GPU/frame-rate, external Art-Net hardware, vendor corpus or full standards
conformance result is claimed. Remote CI results belong to the PR checks and are
reported separately from these local results.
