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

The job tests the exact PR head or push SHA on Ubuntu 24.04 Debug. Independent vcpkg download and binary-archive keys include OS, architecture, `x64-linux`, immutable vcpkg commit `9d7f79f56ae1a9b4704d6a7fb8237e347a974133`, manifest hash, the detected GCC version/target identity, and Debug. Explicit save steps run immediately after successful manifest resolution, before tests and policies can fail. Installed trees are regenerated from the manifest.

Pinned sccache uses a stable `peraviz-ci-v2-linux-<architecture>-<compiler identity>-debug` namespace and workspace base directory. Statistics are reset before compilation, retained as text and JSON, and summarized with requests, hits, misses, hit percentage, and cache errors. The immutable Godot distribution has a separate key containing cache schema, OS, architecture, and exact Godot version; cache hits must still provide an executable that reports its version. The project `.godot` directory is not cached.

Manual `workflow_dispatch` exposes `cache_warm`. When enabled, checkout and a second verification both require the current commit at the repository default branch. This trusted mode may stop after dependency resolution, the full native build, cache statistics, and Godot distribution preparation. Pull requests cannot select a source for shared warming, and ordinary PR runs always execute every required test and policy.

## First authoritative run and correction

[Run 30476712589, job 90660139729](https://github.com/PeramatoG/Peraviz/actions/runs/30476712589/job/90660139729) configured and built the complete native graph successfully, then executed all eight CTest registrations: 8 passed, 0 failed, and 0 skipped. It failed before Godot at the large-file policy. The policy used `find` from the checkout root, so it traversed untracked `.tools/vcpkg`, `.cache`, `out/linux-debug/_deps/godot-cpp`, and `out/linux-debug/vcpkg_installed` data and reported third-party OpenSSL, godot-cpp, zlib, mdns, and other generated sources. This is classified as a **test defect**: the intended subject is repository-owned source, while the implementation inspected the runner filesystem.

The corrected policy consumes the NUL-delimited tracked inventory from `git ls-files -z` and applies the unchanged extension and line-limit rules. Its regression test creates a temporary Git repository, proves that a tracked 3,001-line source path containing whitespace fails, and proves that equally large untracked source-looking files under `out/` and `.tools/` are ignored. This changes the ownership boundary, not the protection threshold.

The first run recorded 20 sccache hits and 1,005 misses, a 1.95% hit rate. Its combined vcpkg cache post-save was skipped after the policy failure. The corrected explicit saves and stable namespace require a corrected cold run and one compatible rerun before cache effectiveness or cold-versus-warm durations can be reported. Godot and all six GDScript tests were skipped in that first run; their authoritative status likewise remains pending the corrected run.

[Run 30487800488, job 90697739555](https://github.com/PeramatoG/Peraviz/actions/runs/30487800488/job/90697739555) tested commit `9a8cb31eedc6167ee31de8c0cede2b91b8e97246`. It confirmed the tracked-file scope regression, configured and built the complete native target set, and again executed 8 CTests with 8 passed, 0 failed, and 0 skipped. Independent vcpkg download and binary cache save steps completed, and the Godot 4.7.1 distribution was downloaded, verified, and saved before policy execution. The policy then stopped at `[runtime-architecture] ripgrep (rg) is required.` because the Ubuntu tool-install step omitted the `ripgrep` package. This is classified as a **missing CI prerequisite**; the architecture policy remains unchanged and blocking.

The focused correction installs `ripgrep` with the existing build tools and immediately verifies both `command -v rg` and `rg --version`. The run reported 1,025 sccache requests, 20 hits, 1,005 misses, 0 cache errors, and a 1.95% hit rate. This was the first run using the new v2 compiler namespace, so it is cold evidence rather than proof of reuse. Exact cache restore hits, a compatible warm-run rate and duration, and all six GDScript results remain pending the next authoritative run because Godot import and GDScript execution were skipped after the missing-tool failure.

## Checkpoint recommendation

Checkpoint 02 should first inspect and stabilize the authoritative exact-head Linux run. Once Linux is green and repeatable, add Windows and macOS through shared helpers rather than duplicating the job wholesale.
