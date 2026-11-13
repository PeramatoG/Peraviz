# GDTF 1.2 shutter fidelity audit

This is a bounded correction of the existing native shutter engine, not full GDTF conformance certification. Production parsing, native dependency evaluation, persistent clocks, authority pooling, snapshot publication and Godot resource ownership remain in place. No fixture names or manufacturer ranges enter runtime decisions.

## References and interpretation

Reviewed on 2026-11-13 against the official [GDTF 1.2 definition](https://gdtf-share.com/help/developers/gdtf_1_2/file-format-definition/index.html), [Annexes A/B/F](https://gdtf-share.com/help/developers/gdtf_1_2/annex/index.html), [Builder functions](https://gdtf-share.com/help/users/gdtf_builder/dmx/add_channel_functions/index.html), [mode dependencies](https://gdtf-share.com/help/users/gdtf_howto/handle_mode_dependencies/index.html) and [split channels](https://gdtf-share.com/help/users/gdtf_howto/handle_split_channels/index.html). The web connector supplied the official pages while direct executor HTTP was blocked by its domain policy.

Table 60 supplies function bounds and activation references; Table 61 supplies set inheritance. Tables 9/10/62 distinguish units, defaults and subordinate parameter overrides. Tables 23/24 describe profile curves; Table 63 identifies Relation endpoints/types. Annex F defines pulse shapes and activation-relative timing. Those rules take precedence over labels and perceived smoothness. The official [libMVRgdtf serializer](https://github.com/mvrdevelopment/libMVRgdtf/blob/9f5a6420c72f24fdd249cfe8133f257026c5590b/src/GDTFManager.cpp) also confirms that a SubPhysicalUnit node reference is its Type token (`GdtfSubPhysicalUnit::GetNodeReference`), corroborating local override link resolution.

## Root causes and corrections

| Source and function | Finding | Correction / evidence |
| --- | --- | --- |
| `native/src/gdtf_runtime/shutter_compilation.h`: `shutter_function_range` | Every sibling start influenced every conditional function. One invalid start rejected all shutter functions in the LogicalChannel. | Boundaries now belong to the declared ModeMaster container. Distinct conditions can share starts; duplicate starts within one container remain invalid. Invalid sibling starts no longer erase independent valid functions. Archive-level regressions exercise both cases. |
| Same function | Nonstandard DMXTo shortened a valid normative range and rescaled its frequency. | Shutter DMXTo is ignored with `PVZ-SHUTTER-DMXTO-IGNORED`; the next start determines the end. Generic non-shutter compatibility is unchanged. |
| `native/src/gdtf_runtime/compiled_gdtf_fixture.cpp`: `compile_gdtf_fixture_type` | The generic previous-range check could reject independently conditional shutter functions already checked by shutter compilation. | Shutter ranges use their own container validation. Runtime simultaneous activation still becomes an unsupported state, never arbitrary precedence. |
| `native/src/runtime/visual_runtime_shutter.cpp`: `install_shutters` | Installation rejected every shutter chain crossing universe boundaries despite the existing native held-input graph supporting this routing. | All bindings of one layer now share an evaluation owner, and the existing byte/dependent graph subscribes to every physical universe. Invalid addresses, unresolved masters, invalid activation and cycles remain guarded. |
| `compiled_gdtf_fixture.cpp`: `compile_gdtf_fixture_type`; `shutter_compilation.h`: `append_shutter_targets` | Profiles and Relations were unsupported but could silently leave an ordinary linear shutter result. | Explicit profile links and resolved Relation followers now withhold ordinary shutter semantics. The guard propagates through shutter activation dependents. General Relation evaluation remains unimplemented. |
| Same parser/compiler functions | All SubChannelSets were rejected. | Constant locally Type-linked Duration, DutyCycle and TimeOffset overrides lower into the existing binding fields. A constant override can replace a valid variable default. Missing endpoints, invalid supplied numbers, duplicate links/types, unresolved links, variable overrides and linked profiles remain guarded. |
| `tests/gdscript/helpers/shutter_stress_probe.gd`: `run` | The test required GPU lens batches even under Compatibility, although production admits them only under Forward+. | Test expectations now distinguish GPU batching from the supported material fallback. Production renderer policy is unchanged. |

## Verified behavior retained

`parse_shutter_sets` already implements parent endpoint inheritance, independent one-sided overrides, inclusive next-start boundaries and descending interpolation. Label-only sets therefore restart the inherited physical interval: the characterized discontinuity is intentional, and was retained. Single-value sets use their PhysicalFrom endpoint.

`mode_master.cpp`, cached activation and the compiled input graph remain authoritative. New tests cover channel and function masters, nested activation, equal starts under distinct conditions, reversed master byte offsets and 8/16/24/32-bit master bounds. Mode-only, frequency-only and duration-only updates operate independently; parameter edits preserve phase and function transitions restart activation.

The existing Annex F sampler, zero-Hz open policy, deterministic random approximation, multiple numbered layers, shared authorities and independent fixture identities remain unchanged. Negative or invalid frequencies remain unsupported. Hold playback performs no source evaluations or semantic publications per flash. Canonical Color/Dimmer are not overwritten. No new setup wire fields were needed: constant overrides and effective unsupported states lower into existing bindings, and cross-universe sources already exist in setup contract 10. The codec round-trip regression covers the routed scene.

## Real archive inspection

Six unmodified archives were downloaded from [Perastage fixtures](https://github.com/PeramatoG/Perastage/tree/47b480220688ee057e5288aa0216d157bdb0cb24/library/fixtures), pinned to commit `47b480220688ee057e5288aa0216d157bdb0cb24`. Git blob hashes were checked after inspection. The optional existing native harness entry `--shutter-corpus DIRECTORY` imports temporary MVR wrappers, compiles every mode, installs the runtime, validates a submitted frame and prints bounded support/trace information. It does not certify manufacturer fidelity or require external archives in CI.

| Archive | Modes | Observed limits / evidence |
| --- | ---: | --- |
| `Robe_Lighting@Robin_MegaPointe@Perastage.gdtf` | 2 | Each mode compiles 25 standard and 6 approximate bindings. At DMX 128 the trace reports 0.087 Hz, 1% duty and 1% offset. The XML supplies those percentages and separately supplies zero Duration for ordinary strobe. These declarations must not be silently replaced by full-period pulses or 25 ms flashes. |
| `GLP@impression_X4_Bar_20@Perastage.gdtf` | 7 | Norm/High Resolution also have an independently active unsupported shutter Effect. Comp at DMX 128 resolves approximately 0.516129 Hz and 1% duty/offset. Four pixel modes are withheld by existing ordered-offset guards. |
| `Martin@Mac_Aura_XB@Perastage.gdtf` | 2 | Standard has supported strobe ranges plus an unlabeled generic shutter interval, which remains unsupported. Extended is withheld by the existing selected-tree geometry guard. |
| `PROLIGHT_SPAIN@PIXEL_STROBE_400_RGB@Perastage.gdtf` | 1 | DMX 128 resolves approximately 14.8789 Hz within set 6–129. Multiple inherited sets deliberately create frequency discontinuities. |
| `Blearred@JDC-1@Perastage.gdtf` | 1 | StrobeRate has PhysicalUnit None; an inverse-Hz interpretation cannot be established. The imported mode has no Beam output, and unsupported rate metadata is diagnosed. |
| `Custom@Chauvet_Color_Strike_M@Perastage.gdtf` | 2 | One mode has invalid ordered offsets; the other supplies no shutter/strobe functions. No new shutter behavior is inferred. |

## Remaining limitations and bounded follow-ups

- **Variable subordinate parameters:** the packed binding carries constant timing. A separate versioned extension should carry parameter endpoints, source intervals and profile identities, extend authority signatures/codec tests, and evaluate parameters only on input invalidation. This pass supports constant overrides only.
- **DMXProfiles:** a shared native piecewise cubic physical mapper is needed, including Min/Max, breakpoint validation and endpoint behavior. It must serve generic source mapping and subordinate parameters; a shutter-only curve evaluator was deliberately avoided. Explicit links currently receive a guard, including malformed/unresolved links.
- **Relations:** retain resolved master/follower identities in a versioned shared graph, establish normalized-versus-physical operands and override precedence from authoritative evidence, then test dirty propagation, ordering and cycles. This pass diagnoses declarations and guards resolved shutter followers/dependents; it does not implement Multiply or Override, or fix non-shutter Relation behavior. Malformed unresolved follower links remain diagnostics, not guessed targets.
- **Channel-wide typed mode candidates with extra activation conditions:** still guarded. Direct ChannelFunction master cascades work, including across explicitly routed universes. Candidate-specific activation needs its own compiled dependency/identity contract before removing that guard.
- **StrobeRate:** still unsupported. A declaration of time between flashes does not justify assuming Hz, guessing units for None, or deciding whether duration is included in a manufacturer's interval.
- **Manufacturer information:** arbitrary Effect, firmware-latched modes, unknown polarity and incomplete routing remain unsupported. Existing exact English open/closed labels are an explicit presentation approximation, not a standard polarity encoding. Additional equivalent textual ModeMaster representations are not a claim of complete container canonicalization.
- **Presentation:** short flashes can alias at render cadence. Random timing remains a documented approximation. GPU pixel fidelity and hardware timing were not validated; the headless engine has no RenderingDevice, and this environment has no `/dev/dri` or Xvfb. Real hardware/manual comparison remains necessary for the observed zero-duration/1% definitions and undocumented effects.

## Validation

Environment: existing Debug CMake/Ninja build, retained dependencies, pinned Godot 4.7.1. The local tool build profile needed existing rendering classes enabled; no tracked dependencies or lockfiles were changed.

Commands executed from the repository root (with the retained Python tools directory on PATH and XDG cache/data/config directed to `/workspace/.peraviz-tools`):

```sh
cmake --build native/build --parallel 5
ctest --test-dir native/build --output-on-failure --timeout 120
native/build/peraviz_native_visual_runtime_tests --shutter
native/build/peraviz_native_visual_runtime_tests --shutter-corpus /workspace/work/perastage-fixtures
bash tests/check_no_large_files.sh
bash tests/check_runtime_architecture.sh
git diff --check
```

Build passed. CTest: **15/15 passed**. Focused shutter regressions and optional corpus inspection passed. Architecture and size checks passed; existing file-size advisories remain.

```sh
GODOT=/workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64
"$GODOT" --headless --audio-driver Dummy --rendering-method gl_compatibility --editor --path . --quit
"$GODOT" --headless --audio-driver Dummy --rendering-method forward_plus --path . --script tests/gdscript/test_native_shutter.gd
"$GODOT" --headless --audio-driver Dummy --rendering-method gl_compatibility --path . --script tests/gdscript/test_native_shutter.gd
"$GODOT" --headless --audio-driver Dummy --rendering-method forward_plus --path . --script tests/gdscript/test_shutter_authority.gd
```

Editor import and both shutter suites passed. Both backends passed `test_native_shutter.gd` after the backend-aware assertion correction. An initial import without the required XDG settings failed to create sandboxed home directories; rerunning with the environment workflow settings succeeded. The initial Compatibility failure was the test's unsupported batching expectation, not an envelope mismatch.

Coverage includes archive-level range defaults/malformed values, all temporal shapes, descending/set boundaries, split control, high-resolution nested activation, constant overrides and guarded semantics; production consumer assertions cover shaft/lens/footprint/projector energy, held phase, renderer replacement, grouping, independent emitters and unchanged source/resource identities. Stress probes retain exact source-evaluation and authority-sampling counts. No performance or renderer regression was detected in these deterministic checks; no hardware FPS or GPU image claim is made.
