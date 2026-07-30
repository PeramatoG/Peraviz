# CI test audit: run 30521815871

## Evidence and method

This audit covers the completed Linux Debug run at commit `8b4d0a5dd7f5ffcc08d0331edbde181dad7f61a0`. The run is authoritative: eight enabled CTests passed, the project imported with Godot 4.7.1, and the GDScript runner discovered six tests with one pass and five failures. The per-test causal messages below were checked against the run evidence and reproduced from the tested commit with the pinned Godot executable. A timeout or shutdown leak is recorded as a consequence, not as a second independent defect.

## GDScript failure ledger

| Test | Intended behavior and production path | Run result and first causal error | Assertions reached? | Current collaborators | Classification | Correction and retained coverage |
| --- | --- | --- | --- | --- | --- | --- |
| `test_beam_geometry_contract.gd` | Validates GDTF radius units, aperture measurement, and Lightweight Prism/volumetric geometry through `BeamGeometryCalculator`, `BeamApertureMeasurementService`, `LegacyConeBeamRenderer`, and `VolumetricConeShapeProvider`. | Failed. Scene geometry was exercised from `SceneTree._init()`; the first causal engine diagnostic was `Condition "!is_inside_tree()" is true. Returning: Transform3D()`. Mesh/scene RID leaks followed at shutdown. | Pure numeric assertions ran; scene-transform calculations ran with invalid fallback transforms. | `select_render_near_radius`, `far_radius_for_full_angle`, `measure_circular_aperture`, `update_beam`, `get_beam_optics_state`, and `apply_shape`. | **invalid test lifecycle/setup/cleanup** | Defer scene work, await a process boundary, align the synthetic cylinder axis with the documented local beam axis, retain the physical radius/range expectations, free all harness nodes/resources, and await renderer cleanup. Valid scene state showed that production geometry remained correct, so the required corrections are confined to test setup and lifecycle. |
| `test_dmx_gobo_controls_resolver.gd` | Validates the Godot-side compatibility resolver for supported gobo controls without scene or renderer ownership. | Passed cleanly. | Yes, all assertions. | `DmxGoboControlsResolver.resolve`. | **obsolete test expectation or obsolete test double** does not apply; this is the passing control and requires no failure correction. | Keep unchanged as evidence that pure synchronous tests remain valid. |
| `test_lightweight_prism_beam_optics.gd` | Validates Lightweight Prism near/far orientation, zoom mutation, resource reuse, rectangular topology, and `BeamType None` visibility through `LegacyConeBeamRenderer`. | Failed. The first causal error was the same out-of-tree transform diagnostic. The near-at-lens and negative-Z assertions then failed because the returned transforms were invalid. | Yes, but world-space assertions used fallback transforms. | `ensure_beam`, `update_beam`, `apply_beam_optics`, `get_beam_resource`, and `get_beam_optics_state`. | **invalid test lifecycle/setup/cleanup** | Run after the light and renderer-created child are in the tree, preserve the world-space contract, use accumulated checks, and explicitly release renderer resources. |
| `test_lightweight_prism_dimmer_target.gd` | Validates target-oriented dimmer mutation, prism visibility, increasing lens emission, emitter-record lumen scaling, and return-to-zero behavior through `FixtureLightApplyService` and `LegacyConeBeamRenderer`. | Failed and timed out. The first causal script error was a bare assertion during invalid setup; the test had added `PrismLoader` to the tree and then manually called `_ready()`, producing duplicate-parent errors for `EmitterLens` and `PeravizEmitterLight`. The aborted script never reached `quit()`. | Only the initial assertions; the maintained dimmer sequence did not complete. | `apply_emitter_intensity`, `_has_native_dimmer_target`, `_get_native_dimmer_target_record`, `_apply_emitter_light_state`, and beam callbacks. | **invalid test lifecycle/setup/cleanup** | Observe real readiness exactly once, accumulate failures, execute the full dimmer sequence, free the root, and exit deterministically. |
| `test_native_renderer_target_registry.gd` | Validates manifest registration, transform targets, target failures, duplicate/overlap detection, shared emitter ownership, Beam profiles, and repeated emitter records through `NativeRendererTargetRegistry`. | Behavioral assertions completed, but shutdown failed with 107 leaked ObjectDB instances, one resource in use, 53 material RIDs, one shader RID, and 53 renderer scene instances. | Yes, all behavioral assertions. | `configure`, `install_manifest`, `apply_transform_targets`, target record/failure accessors, `clear`, and beam renderer callbacks. | **invalid test lifecycle/setup/cleanup** | Preserve all registry assertions, clear every registry, free all three harness trees, await process/RenderingServer cleanup, and use cleanup-safe accumulated checks. |
| `test_native_target_application.gd` | Validates sectioned native pan/tilt/dimmer application, skip diagnostics, manifest installation, and the renderer registry callback boundary through `SectionedVisualFrameApplier`, `FixtureLightApplyService`, and `DmxFixtureRuntime`. | Failed and timed out. The first causal error was access to missing `FakeLoader.DEFAULT_EMITTER_PHOTOMETRICS`; the fake also lacked `_apply_emitter_light_state`. Manifest validation then reported missing `_has_native_optics_target`, and a bare assertion aborted before `quit()`. | Early transform assertions ran; dimmer and manifest contracts did not complete reliably. | `apply_snapshot`, `apply_emitter_intensity`, `_install_renderer_manifest`, the loader photometric/light callbacks, and all required registry target methods including optics. | **obsolete test expectation or obsolete test double** | Implement only the minimal current loader and registry callback interfaces, assert the complete fake contract explicitly, preserve pan/tilt/dimmer/failure diagnostics and empty-manifest installation, and clean up deterministically. Empty manifests still require optics methods because production validates registry capability before accepting any compiled scene. |

## Runner contract

The runner treats a non-zero process exit, timeout, `SCRIPT ERROR:`, any unqualified engine `ERROR:`, and resource/RID leak errors as failures. Ordinary warnings alone pass. Test scripts report accumulated assertion messages as normal output and return non-zero, so assertion failure does not depend on log scanning. Timeout failures include the first preceding script or engine diagnostic when one exists.

## Native inventory authority

`.github/ctest-required-tests.txt` is the maintained minimum manifest. The validator rejects zero tests, fewer than eight tests, missing manifest entries, and disabled tests while allowing a deliberately registered ninth test. The same discovered inventory is supplied when validating CTest JUnit totals, preventing the former hard-coded JUnit count from diverging from inventory validation.

## Cache evidence

Run 30521815871 issued 1,025 compiler requests with 20 hits, 1,005 misses (1.95%), and one cache write error; sccache printed `Base directories (none)` despite the workflow environment value. The immediately preceding compatible executions were pull-request runs 30490584133, 30487800488, and 30476712589. GitHub cache scope prevents a default-branch push from restoring caches written only to a pull request's synthetic merge-ref scope, so the post-merge run had no compatible warm compiler-cache generation to consume. The run restored neither the pinned vcpkg download/binary entries nor the pinned Godot distribution and saved their newly populated keys successfully. The lone sccache write error is not sufficient to establish a systematic defect, and `SCCACHE_BASEDIR` does not appear in sccache's reported configured base-directory list in this execution. No speculative cache or build-directory caching change is made; two compatible runs are required to determine actual cold/warm behavior.

---

# Historical CI harness audit

## Godot 4.7 toolchain closeout

The production runtime/editor baseline is Godot 4.7.1 stable, while the generated GDExtension API target is Godot 4.7. The extension minimum is also 4.7: upstream compatibility is forward from an older generated API to a newer engine, not backward from a 4.7 API to an older engine. Peraviz therefore does not retain the former, unverified 4.2 minimum claim.

The official `godotengine/godot-cpp` repository, its README compatibility guidance, tag inventory, bundled API definitions, and CMake configuration were inspected on 2026-07-30. No official Godot 4.7 stable tag existed. The v10 master line supported `GODOTCPP_API_VERSION=4.7`, identified 4.7 as its latest bundled API, and selected its bundled `gdextension/extension_api.json` for that value. Peraviz pins reviewed official commit `82c6c449b9432d1eae1fbaa087bd579c77e6e8d5` rather than following the floating branch. This exact SHA makes FetchContent reproducible and requires no vendored generated bindings. `GODOT_CPP_DIR` remains available for local source overrides, but Peraviz still forces the explicit 4.7 API target.

`native/cmake/GodotCompatibility.cmake` is the authoritative contract for the runtime, API, immutable godot-cpp revision, and extension minimum. `.github/scripts/validate_godot_compatibility.py` checks `project.godot`, CI, CMake integration, README requirements, and the extension declaration against it. CI prints the validated values and incorporates a digest of the contract into the sccache namespace, preventing incompatible binding output from sharing compiler objects without caching the CMake build tree. The vcpkg download, vcpkg binary archive, and Godot distribution cache designs remain separate and unchanged.

Clean local verification removed `out/godot47-clean` and the existing Linux extension before configuration. The clean Debug configuration used `BUILD_TESTING=ON`, fetched the pinned commit, reported the 4.7 API and bundled `gdextension/extension_api.json`, and generated 2,135 binding files. The complete native target build succeeded. Inventory validation found exactly eight required CTests and the unfiltered suite passed 8/8. Godot 4.7.1 stable imported the project and the strict runner passed 6/6 discovered GDScript tests. The focused extension smoke check found all six expected native classes: `HelloWorld`, `PeravizLoader`, `PeravizGoboVectorizer`, `PeravizDmxReceiver`, `PeravizVisualRuntime`, and `PeravizMvrXchangeClient`.

The local editor import exited successfully without script, engine, resource, or RID errors, but Godot reported two leaked `ObjectDB` instances during shutdown. A second editor import and a normal headless project launch reproduced the same pre-existing shutdown warning, while the focused extension smoke and all six isolated GDScript processes exited cleanly. This warning remains a blocker for claiming the requested leak-free authoritative import; it has not been suppressed or attributed to the binding migration without evidence.

The authoritative draft-PR Actions run URL, tested commit SHA, cold/warm cache restore results, and measured sccache statistics must be added here after both compatible executions complete. The branch must remain draft until that evidence is green.

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
