# Automatic DMX Auto Span validation

Linux, GCC 14, Debug native build, pinned Godot 4.7.1 (`a13da4feb`), based on main
`50d7d51` including PR #129. Fixtures/archives added for these tests are synthetic
and redistributable. The foundation's original failure reproduction remains in
this document's history at PR #129; current expected defaults are different.

## Commands

Commands ran from `/workspace/Peraviz`; `work/tools/bin` supplies CMake/Ninja and
the retained environment supplies native dependencies and pinned Godot bindings.
No tracked dependency or shader change was needed.

```sh
work/tools/bin/cmake --build native/build -j 4
work/tools/bin/ctest --test-dir native/build --output-on-failure --timeout 120
tests/check_no_large_files.sh
tests/check_runtime_architecture.sh
git diff --check
git diff origin/main --check
```

Native CTest: **15/15 passed**. This includes existing native suites, PR #129's
serial/native-worker/actual async material publication tests and the new
`peraviz_native_automatic_auto_span_tests`. Architecture and whitespace checks
passed. The large-file check passed with its existing advisory warnings for four
large files; the new planner, panel and tests remain separate modules.

Clean editor import and the full existing Godot regression runner:

```sh
export XDG_CACHE_HOME=/workspace/Peraviz/work/cache
export XDG_DATA_HOME=/workspace/Peraviz/work/godot-data
export XDG_CONFIG_HOME=/workspace/Peraviz/work/godot-config
export GODOT_BIN=/workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64
mv .godot work/automatic-godot-cache-before-clean
timeout 120 "$GODOT_BIN" --headless --audio-driver Dummy --rendering-method gl_compatibility --editor --path . --quit
PYTHONUNBUFFERED=1 python3 .github/scripts/run_gdscript_tests.py --godot "$GODOT_BIN" --project /workspace/Peraviz --output /workspace/Peraviz/work/automatic-gdscript-final --timeout 120
```

The runner selects existing Compatibility/Forward+ test backends, writes per-test
logs/JUnit and rejects unexpected engine/script errors or leaked instances, even
when a process exits zero. The clean import passed. The complete Godot suite passed **51/51** tests with zero skipped tests and zero unexpected diagnostics.

## Deterministic verification

`automatic_auto_span_test.cpp` generates ZIP GDTF/MVR inputs and checks:

- Independent 30-channel fixture at 1.500: 13 complete controls in strict mode,
  all 30 when a continuation is admitted.
- Occupancy at the first, middle and last required continuation slots: safe denial,
  permissive admission, and unchanged independently patched controls.
- Reversed fixture order, two competing candidates (both denied in safe mode,
  both admitted in overlap mode), normal co-patching and unresolved occupancy.
- The exact same universe 2 slot 9 byte drives normalized Dimmer on one fixture
  and 0–100 degree Pan on another through the real native mailbox/coordinator.
- Whole-control 16/32-bit strict omission and complete ordered 32-bit output,
  including final material-energy values from bytes split between universes.
- Complete/incomplete RGBW groups, independent complete Dimmer retention and
  exact explicit-break routing when another break overflows.
- Unsupported attributes/shutter/gobo/wheel policy guards; existing foundation
  tests retain GeometryReference/Overwrite, 180-byte routing, Port-Address bounds,
  canonical IDs, reverse arrival, unchanged suppression and archive fidelity.
- Policy-independent potential-byte subscriptions replay both held universes on
  policy replacement, and the selected-mode parser cache retains identical objects.

`test_auto_span_project_policy.gd` runs the actual application with two generated
60-pixel Glow fixtures. A real loopback ArtDmx packet at universe 2 slot 9 remains
red on the normally patched fixture and becomes green on the inferred fixture.
No additional packet is sent during GUI policy transitions. The test checks actual
native material binding values, unchanged peer output, strict/overlap restoration,
Advanced-only UI, exact three options, invalid/default/reset settings, PVZ save/open
and import restoration, preparation-cache policy mismatch, ordinary MVR defaults,
full cleanup and the unchanged source archive hash. It installs the native
subscription before sending, rather than racing the first presentation tick.

Existing import regressions now distinguish informational routing status from
semantic fallback warnings/errors. The native compatibility regression explicitly
selects `off` for its strict fine-byte omission check and separately verifies
complete default automatic coarse/fine routing; it never accepts partial decoding.

## Scope and cost

Occupancy maps and conflict work are transient setup-only data. Runtime retains
immutable selected-mode parser templates and bounded potential-byte subscriptions
for held replay; it does not retain an occupancy map or add conflict detection to
per-packet/per-frame evaluation. See [architecture/cost details](dmx-auto-span.md).

Strict partial retention is implemented for supported direct scalar/Color modes,
including explicit independent breaks. Temporal/wheel/gobo/unknown-mode overflow
retains its existing strict safety guard; those semantics do not gain Auto Span.
No graphical frame-rate, vendor-corpus, hardware-network timing or full standards
conformance claim follows from these native/headless results. Remote CI results
are reported separately in the PR.
