# Ambient rendering baseline (Godot 4.7 Forward+)

## Scope and evidence

This is a conservative candidate for ambient rendering, independent of the optical
presets. It does not change native code, DMX, GDTF interpretation, imported geometry
scaling, emitter state or saved optical behavior. No graphical improvement or GPU
performance gain is claimed from headless tests.

The audit used Godot **4.7.1-stable official a13da4feb** from the prepared cloud tools.
The system `godot` is 4.6.3 and must not be used for this project (the extension
requires 4.7). Engine property hints confirm screen-space AA `2 = SMAA`, directional
filter `3 = Soft Medium`, and the defaults below. Original settings were inspected
before editing; `A` in the diagnostic reconstructs their effective desktop values
for a reproducible graphical baseline. No pre-change graphical capture was possible.
A graphical launch failed with `X11 Display is not available` and Wayland connection
failure. The execution environment also exposes no `/dev/dri` GPU device. CPU timing
from a headless dummy renderer is not a GPU performance comparison.

## Effective settings and ownership

| Setting | Original effective desktop value | New baseline | Owner/source |
| --- | --- | --- | --- |
| Renderer | Forward+ | Forward+ | Godot default; now explicit in project |
| Root screen-space AA | Disabled (0) | SMAA 1x (2) | Project setting inherited by root Window/Viewport |
| MSAA / TAA | Disabled / false | Disabled / false | Defaults, now explicit project settings |
| 3D scale / scaling mode | 1.0 / Bilinear (0) | Same | Defaults, now explicit; no FSR or supersampling |
| Viewport debanding | false | false | Default, now explicit |
| Procedural sky debanding | true | false | Day/night controller; separate from viewport debanding |
| Directional filter | Soft Low (2) | Soft Medium (3) | Default → project setting |
| Directional atlas | 4096, 16-bit | Same | Defaults, now explicit project settings |
| Sun angular distance | 0.35 degrees | 0.0 | Scene resource; avoids PCSS by default |
| Sun shadow enabled | true | true | Scene resource |
| Sun bias / normal bias | 0.015 / 0.7 | Same | Scene resource (engine defaults are 0.1 / 2.0) |
| Sun blur | 1.0 | Same | Godot default |
| Sun shadow distance | 72 m | Same | Scene resource |
| Cascade mode | Four splits (2) | Same | Godot default |
| Splits / blending / fade start | 0.08, 0.2, 0.45 / true / 0.85 | Same | Scene resource except split 2 default |
| SSAO | enabled, radius 1.0, intensity 0.5 | disabled; retained radius/intensity | Startup High preset overrides scene |
| SSAO quality | Medium (2), half-size | Same (inactive) | Godot defaults |
| SSIL / SSR | disabled / disabled | Same | Godot defaults |
| Ground dimensions | 20000 × 20000 m | 200 × 200 m empty; adaptive on import | Scene + setup-only ground helper |
| Ground casting / receiving | on / on | off / on | MeshInstance3D; ordinary opaque material still receives |
| Ground material | grey 0.45, specular 0.45, roughness 0.78 | Same | StandardMaterial3D scene resource |
| Camera near / far | 0.05 / 4000 m | Same | Godot defaults; camera script never changes clipping |
| Positional shadow atlas | **4096** | Same | Godot default, see malformed settings below |

`project.godot` originally placed `rendering/lights_and_shadows/...` and
`rendering/environment/volumetric_fog/...` inside `[rendering]`. These become
`rendering/rendering/...`, unrecognized custom settings. In particular the apparent
1024 positional atlas request was ineffective. These pre-existing positional/fog
entries are left untouched to avoid an unrelated fixture-rendering change. New
ambient settings use the correct section-relative keys. The effective positional
atlas remains 4096, not 1024.

Global graphics quality belongs to `project.godot`; scene light defaults belong to
`test.tscn`. The existing loader owns environment preset application before capturing
the glow/ambient baseline and restoring visual settings. Low, Medium and High now
all leave SSAO disabled; glow behavior is preserved. No second startup quality
controller or graphics UI was added. The day/night controller changes lighting,
sky and ambient energy, not shadow/AA settings. The environment panel and optical
presets do not own graphics quality. `_load_visual_settings_from_project()` is
already intentionally a no-op; PVZ restoration updates existing supported visual
settings without applying arbitrary keys to the Viewport or Environment. MVR
loading does not reapply AA or directional quality settings.

Ground fitting runs only when loaded world bounds are rebuilt or retired. It uses
the existing transformed imported mesh AABBs, with a minimum 200 m size and 20 m
margin on each horizontal side, without a maximum size cap. Its center follows the
world bounds, including off-origin scenes. Imported transforms and
`IMPORTED_CONTENT_SCALE` remain untouched. The plane resource is local to each scene
instance. For imports, its height is 5 cm below the lower of world zero and the
lowest imported bound, avoiding coplanar overlap with imported floors; the fallback
may therefore be well below a scene with basements. This is a conservative bounds
policy, not semantic floor detection or automatic hiding of imported floors. It
cannot repair overlapping floors within the MVR itself. Extreme coordinate offsets
and very large scenes still require a graphical precision check.

The original near plane is retained pending close-up comparison: 0.1 m could clip
fixture inspections. No unsafe fixed far-plane reduction or navigation changes were
introduced. Godot Forward+ uses reverse-Z; the enormous plane and coplanar geometry
are more actionable suspects than assuming the near/far ratio alone explains noise.
The existing 4000 m far plane is still a limitation for scenes beyond that range.

## Reproducible diagnostics on Windows

Run from the repository root with the built 4.7 extension installed. Use a Godot 4.7
console executable, for example in PowerShell:

```powershell
$Godot = 'C:\Godot\Godot_v4.7.1-stable_win64_console.exe'
& $Godot --version
$Out = Join-Path $PWD 'ambient-audit'
$Cases = 'A','B','C','D','E','F','G','H','I','J','clean','msaa2','ssao','near','depth32'
foreach ($Case in $Cases) {
  & $Godot --path . --rendering-method forward_plus --audio-driver Dummy --script tests/manual/ambient_render_audit.gd -- "--case=$Case" "--out=$Out"
}
```

A is the original reference; B–J isolate one change against A (not cumulative):

| Case | Change from reference |
| --- | --- |
| A | Original AA, SSAO, PCSS, filter and ground |
| B | Directional shadows disabled (diagnostic only) |
| C | SSAO disabled |
| D | Angular distance 0 (no PCSS) |
| E | Soft Medium directional filtering |
| F | SMAA 1x only |
| G | MSAA 4x, no TAA or screen-space AA |
| H | TAA, no MSAA or screen-space AA |
| I | Ground casting disabled |
| J | Shadow distance 36 m (comparison only) |
| msaa2 | MSAA 2x only against A |
| clean | Combined new production defaults |
| ssao | Clean + experimental radius 0.5 / intensity 0.25 |
| near | Clean + 0.1 m near plane |
| depth32 | Clean + 32-bit 4096 directional atlas |

The script creates repeatable thin boxes and contact shadows for an otherwise empty
scene, applies Day lighting, disables auto-load in memory, hides UI, fixes the
1280 × 720 window, disables VSync and FPS limiting, and freezes the camera after
positioning. It warms up 120 frames, samples 300, then writes PNG and JSON reports.
Use an empty output folder for each workload. Settings are process-local and never
saved. The `depth32` report is compared with clean's 16-bit atlas. Sky debanding is
restored for the original reference. The harness's full-scene camera framing is
deterministic from bounds and identical across candidates for the same workload.
No Art-Net sender, manual fixture test or DMX receiver is needed.

For a small or fixture-heavy MVR, add its absolute path and a distinct output folder:

```powershell
$Mvr = 'C:\Shows\small.mvr'
& $Godot --path . --rendering-method forward_plus --audio-driver Dummy --script tests/manual/ambient_render_audit.gd -- --case=clean "--mvr=$Mvr" "--out=$Out\small"
# Repeat every case with the exact same MVR. Repeat for a representative heavy show.
# Repeat the matrix with --moving to sample deterministic orbit AND zoom motion.
& $Godot --path . --rendering-method forward_plus --audio-driver Dummy --script tests/manual/ambient_render_audit.gd -- --case=H --moving "--mvr=$Mvr" "--out=$Out\small"
```

Moving screenshots capture the final camera pose, not temporal artifacts over the
whole path. Record video or inspect an interactive run to judge TAA ghosting during
movement and after stopping. Test close fixture inspections separately with near
0.05 versus 0.1 m before changing the production near plane. Do not compare captures
with different viewport, lighting, camera, MVR or driver settings.

AA, TAA, clipping, light properties, SSAO and ground properties are runtime setters.
The filter and directional atlas size/depth also have RenderingServer runtime APIs,
which the harness uses explicitly. Merely calling `ProjectSettings.set_setting()`
does not reconfigure active renderer state; editing `project.godot` requires a fresh
application run for those inherited defaults. No editor restart or project file
mutation is required between diagnostic cases.

JSON records actual engine/renderer, viewport/window size, AA/scale, light values,
AO, ground, clipping, camera, average frame time, standard deviation, reciprocal FPS
and object/primitive/draw-call counters. Global filter/depth values have no getter
and are reported from the explicit applied case. GPU frame time is marked
unavailable: collect it with Godot's GPU profiler on target hardware, with the same
profiling overhead for all cases. Headless reports are marked and must not be used
as visual/performance evidence. Run several trials on a quiet machine; evaluate
image quality and frame-time variability as well as mean FPS.

## Validation and comparison results

Graphical A–J, 16/32-bit depth, SSAO experiment, near-plane experiment and actual GPU
cost remain **unverified**. No measured evidence currently justifies replacing the
requested conservative SMAA candidate with MSAA or TAA. Target hardware must confirm
that SMAA/filtering cost and ground behavior are acceptable. There were no supplied
small/representative real-world MVRs in the environment; generated workloads exercise
structural contracts, not representative graphical quality.

After ambient comparisons, manually check fixture housings; Vector Gobo Prism;
Custom footprints; Native gobo fallback; shared haze and volumetric modes; Pan/Tilt;
and response to live DMX. Check stationary, orbiting, zooming, close-up and distant
views. These optical/live graphical acceptance checks remain open even when their
headless regression tests pass. See the validation commands/results recorded below.

### Executed validation

The following commands ran from the repository root. For Godot commands,
`GODOT_BIN=/workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64`;
`XDG_DATA_HOME`, `XDG_CACHE_HOME` and `XDG_CONFIG_HOME` pointed to writable prepared
cloud tool directories. CMake/CTest came from `/workspace/.peraviz-tools/python/bin`.

- `cmake -S native -B native/build -DGODOTCPP_BUILD_PROFILE=/workspace/work/build-profile.json`
  and `cmake --build native/build --parallel 5`: passed. The retained extension
  library was initially absent and the old local build profile omitted Light3D,
  MeshInstance3D and RenderingServer. The temporary profile includes all native
  source class dependencies plus Engine/SceneTree; no tracked build files changed.
- `ctest --test-dir native/build --output-on-failure --timeout 120`: **14/14 passed**.
- `timeout 120 "$GODOT_BIN" --headless --editor --path . --quit`: passed, no script
  or engine errors in the import log.
- `timeout 60 "$GODOT_BIN" --headless --path . --script tests/gdscript/test_ambient_render_quality.gd`:
  passed. Covers effective root defaults, directional defaults, all environment
  presets and unknown-preset fallback, PVZ restoration isolation, casting, fitting,
  retirement and unchanged imported transforms/clipping planes.
- `python3 .github/scripts/run_gdscript_tests.py --godot "$GODOT_BIN" --project /workspace/Peraviz --output /workspace/work/gdscript --timeout 60`:
  **51/51 passed**, including existing scene-loading, optical, projection, native
  shutter, shared haze, volumetric, fixture presentation and Pan/Tilt contracts.
- `timeout 60 "$GODOT_BIN" --headless --path . --script tests/manual/ambient_render_audit.gd -- --case=CASE --out=/workspace/work/audit-synthetic`:
  passed for A–J, clean, msaa2, ssao, near and depth32. All 15 reports explicitly
  identify headless mode; rendering counters are zero, so their frame times are
  deliberately not presented as rendering performance results.
- Generated smoke inputs with
  `python3 tests/integration/generate_render_group_fixture.py /workspace/work/small.mvr --instances=4 --transforms --wheel=basic --mode=BasicControls`
  and the same command for `heavy.mvr` with `--instances=100`. Ran the diagnostic
  above with `--case=clean --moving --mvr=/workspace/work/small.mvr` and the heavy
  equivalent into distinct output directories. Both completed without engine or
  script errors and retained SMAA/no TAA/no MSAA after actual MVR loading. These
  synthetic workloads do not replace a representative owner-supplied show.
- `bash tests/check_no_large_files.sh`: passed with existing soft-limit warnings
  for the loader, DMX runtime, light apply service and native visual runtime tests.
- `bash tests/check_runtime_architecture.sh`: passed.
- `git diff --check`: passed.

No native optical/protocol source files were modified. Automated successes establish
behavioral contracts and diagnostic reproducibility; they do not establish the
visual acceptance criteria or a measured GPU advantage.
