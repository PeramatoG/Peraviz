# CI test audit

This audit records the test surface at commit `056af0d` before the first Linux Debug workflow was added. The checkpoint uses branch-head registrations and files rather than assuming that a zero exit code means every test was discovered or parsed.

## Dependency boundary

The eight CTest executables use C++17 and focused production sources. Runtime storage, MVR-xchange service/packet/transfer, Art-Net flow, and runtime-table tests need only the standard library and platform sockets. DMX, end-to-end, visual-runtime, and GDTF-schema tests link tinyxml2 and libzip. No test source or link list uses `godot-cpp` or mdns. The normal `peraviz_native` target uses `godot-cpp`, tinyxml2, libzip, and mdns, and Godot needs that library during import to register native classes.

`PERAVIZ_BUILD_GDEXTENSION=OFF` now exposes this pure-native boundary for focused development. CI retains the default `ON`: it builds the shared library and every test because headless GDScript tests exercise an imported project. Runtime behavior and the normal library output are unchanged.

## Native CTest inventory

CI runs `ctest --test-dir out/linux-debug --output-on-failure --verbose --timeout 120` without labels, regexes, exclusions, or disabled-test overrides. All tests are deterministic and headless. File tests use isolated temporary directories; Art-Net uses loopback UDP and an ephemeral port.

| CTest name | Dependencies / coverage | GDExtension required | Expected timeout | Audited status |
| --- | --- | --- | --- | --- |
| `peraviz_native_runtime_storage_tests` | C++ filesystem, runtime storage | No | <5 s; 120 s guard | Pass |
| `peraviz_native_mvr_xchange_tests` | Filesystem, service name, packet, transfer; no mdns discovery | No | <5 s; 120 s guard | Pass |
| `peraviz_native_dmx_tests` | tinyxml2, libzip, archive/XML/classification | No | <5 s; 120 s guard | Pass |
| `peraviz_native_artnet_flow_tests` | Loopback UDP, threads, Art-Net parser/receiver/cache | No | <5 s; 120 s guard | Pass |
| `peraviz_native_dmx_e2e_tests` | tinyxml2, libzip, temporary GDTF archives | No | <5 s; 120 s guard | Pass |
| `peraviz_native_visual_runtime_tests` | tinyxml2, libzip, compiled fixture/visual runtime | No | <5 s; 120 s guard | Pass |
| `peraviz_native_gdtf_runtime_schema_tests` | tinyxml2, libzip, GDTF/frame schemas | No | <5 s; 120 s guard | Pass |
| `peraviz_native_runtime_table_tests` | Runtime table schemas/model | No | <5 s; 120 s guard | Pass |

Evidence: a clean GNU 13.3 Debug build without `NDEBUG` discovered and executed 8 tests; 8 passed, 0 failed, and 0 skipped in 0.26 seconds. CI validates an explicit authoritative name set before execution and verifies the JUnit execution total afterward.

## Repository shell checks

| Command | Dependencies | Deterministic / CI-safe | GDExtension | Headless | Timeout | Audited status |
| --- | --- | --- | --- | --- | --- | --- |
| `tests/check_no_large_files.sh` | Bash, `find`, `wc` | Yes | No | Yes | <10 s | Pass; existing soft warnings for `dmx_fixture_runtime.gd` and `load_scene.gd` |
| `tests/check_runtime_architecture.sh` | Bash, ripgrep, temporary-directory tools | Yes | No | Yes | <10 s | Pass |
| `GODOT_BIN=/path/to/godot tests/check_live_gobo_controls_resolver.sh` | Godot and imported script classes | Yes after import | Indirect import prerequisite | Yes | <60 s | Historical wrapper can silently pass parse errors; CI supersedes it with the strict all-script runner |

## GDScript headless inventory

CI builds `peraviz_native`, imports the project once, then runs:

```bash
python3 .github/scripts/run_gdscript_tests.py \
  --godot "$GODOT_BIN" --project . --output out/ci-results/gdscript --timeout 60
```

The runner uses `--headless --audio-driver Dummy --rendering-method gl_compatibility`, rejects script errors even if Godot returns zero, writes one log per script, and emits JUnit. All six tests are deterministic, CI-safe, need no display/audio device, and use a 60-second guard. They do not directly instantiate the extension, but the compiled extension is an import prerequisite because production scripts refer to registered native classes.

| Script | Coverage | Pre-checkpoint local status |
| --- | --- | --- |
| `test_beam_geometry_contract.gd` | Geometry/aperture contracts | Passed after class-cache import |
| `test_dmx_gobo_controls_resolver.gd` | Gobo controls/runtime integration | Invalid apparent pass exposed: Godot returned zero despite dependent-script errors when extension was absent |
| `test_lightweight_prism_beam_optics.gd` | Lightweight Prism optics | Blocked without compiled extension/import |
| `test_lightweight_prism_dimmer_target.gd` | Target-oriented dimmer application | Blocked without compiled extension/import |
| `test_native_renderer_target_registry.gd` | Target registry setup/reuse | Blocked without compiled extension/import |
| `test_native_target_application.gd` | Sectioned-frame target application | Blocked without compiled extension/import |

The blocked results are a **missing prerequisite**, not a production/test defect: logs show missing `bin/libperaviz_native.so`, extension-load failure, then unresolved dependent types. Exact-head Actions evidence remains required for final classification with the manifest-built extension present.

## Workflow and cache contract

The job tests the exact PR head or push SHA on Ubuntu 24.04 Debug. Its vcpkg key includes OS, architecture, `x64-linux`, immutable vcpkg commit `9d7f79f56ae1a9b4704d6a7fb8237e347a974133`, manifest hash, GCC 14, and Debug. Downloads and binary archives are cached; installed trees are regenerated from the manifest. Pinned sccache is the C++ launcher. These boundaries prevent incompatible configuration, ABI, triplet, manifest, or baseline reuse.

## Checkpoint recommendation

Checkpoint 02 should first inspect and stabilize the authoritative exact-head Linux run. Once Linux is green and repeatable, add Windows and macOS through shared helpers rather than duplicating the job wholesale.
