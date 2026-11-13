# Ambient rendering baseline (Godot 4.7 Forward+)

Current revision: the ground is matte grey `(0.4, 0.4, 0.4)`, with the original sky.
Directional bias/normal bias now use Godot defaults **0.1 / 2.0** as an anti-acne
candidate. Earlier sections below record previous iterations; they are not all
current defaults. GPU validation of this candidate is still pending.

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
| Ground dimensions | 20000 × 20000 m | 2000 × 2000 m empty; adaptive on import | Scene + setup-only ground helper |
| Ground casting / receiving | on / on | off / on | MeshInstance3D; ordinary opaque material still receives |
| Ground material | grey 0.45, specular 0.45, roughness 0.78 | #202020, specular 0, metallic 0, roughness 1 | StandardMaterial3D scene resource |
| Camera near / far | 0.05 / 4000 m | Same | Godot defaults; camera script never changes clipping |
| Positional shadow atlas | **4096** | Same | Godot default, see malformed settings below |

`project.godot` originally placed `rendering/lights_and_shadows/...` and
`rendering/environment/volumetric_fog/...` inside `[rendering]`. These become
`rendering/rendering/...`, unrecognized custom settings. In particular the apparent
1024 positional atlas request was ineffective. These ineffective entries have now been removed; no replacement override was added, preserving the effective positional/fog engine defaults. New
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
the existing transformed imported mesh AABBs, with a minimum 2000 m size and 20 m
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
and are reported from the explicit applied case. GPU timing can now be requested with `--gpu-time` using the engine Viewport timing API. Unsupported/headless samples produce null; compare identical profiling overhead. Headless reports are marked and must not be used
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

## Follow-up: flat surfaces, shadow edges and theatre ground

### Findings and limits

The supplied Windows images show a finite bright ground rectangle against black,
large shadow-edge steps, and a fine diagonal pattern across the light region as
well as shadow edges. These are observations, not a verified single cause. No MVR
corresponding to those images is available here. No coplanar face pair, invalid
normal or erroneous transform in that show has been identified. No imported object
has been shifted, deduplicated or hidden in production. The newly attempted graphical
launch again failed with X11/Wayland errors; the host exposes no GPU device.

The 200 m finite floor and its relatively reflective material contributed to the
conspicuous ground appearance. The controller selecting sky mode is established
day/night behavior, not a defect; it is preserved. The temporary studio-background
change was reverted following user feedback. Only ground appearance/coverage changes
remain from that presentation adjustment.

[Godot 4.7 lighting documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html)
explains that PSSM divides atlas coverage among camera-depth regions. Shorter shadow
ranges improve texel density but remove distant coverage. Increasing blur exposes
filter grain; High/Ultra filtering also increases the sampling radius. Low bias
can cause acne, while excessive bias detaches shadows; normal bias can thin them.
32-bit depth and larger atlases cost resources and need scene-specific evidence.
These mechanisms explain plausible causes, not a diagnosis of the supplied show.
The [referenced forum discussion](https://forum.godotengine.org/t/why-are-my-shadows-dithered/142905)
describes a related filtering problem, not proof that Peraviz has the same cause.
The linked Store demo was inaccessible through the research tool; the official
documentation links the [source demo](https://github.com/godotengine/godot-demo-projects/tree/master/3d/lights_and_shadows).

The fine pattern could be acne, overlapping geometry, shading/normal artifacts,
specular aliasing, LOD or post-processing. SMAA is not a cure for shadow-map texel
resolution or coplanar geometry. The current bias is below the engine default;
that warrants an isolated comparison, not a blind global reset. Until GPU comparisons
resolve these causes, directional defaults remain **72 m, four splits .08/.20/.45,
blend on, bias .015, normal bias .7, blur 1, Soft Medium, 4096/16-bit, angular distance
0**. AA remains **SMAA only**, scale 1; TAA/MSAA/SSAO/SSIL/SSR/debanding remain off.
No speculative 8192, temporal AA, shortened shadow range or softened default was
promoted. Shadow/noise correction is still awaiting target-machine evidence.

### Ground and background corrections

The fallback receiver is now #202020, roughness 1, metallic/specular 0, opaque and
per-pixel lit. Minimum coverage is 2000 × 2000 m, still using imported world bounds
plus margins with no upper cap, following off-origin bounds only at setup and
retirement. Its height/clearance and no-casting policy are unchanged. The two-triangle
plane adds no geometry complexity; more visible receiver pixels and its extended
coverage may affect fragment cost. No GPU cost is measured here.

There is no alpha, distance dithering, noise, texture, camera-following movement or
fullscreen concealment. Production shading normals are preserved. Custom Footprints
(`scripts/shaders/custom_footprint.gdshader`) reconstruct depth and sample normals;
the additive projector does not multiply its output by ground albedo. Thus the
receiver remains suitable structurally, and a dark albedo does not mathematically
attenuate that additive projection. Native lighting still depends on receiver
albedo. Low-intensity Custom and Native output must be judged separately on hardware;
no optical gain has been raised to compensate.

The original procedural sky remains the default, including the existing day/night
colors, horizon and lighting cycle. The temporary studio-background selector and
saved-setting owner have been removed. Even a PVZ saved during that intermediate
implementation with `environment_use_sky_background=false` cannot disable the sky.
The existing controller-disabled fallback is preserved. Ground changes do not replace
the sky or force a neutral background. The finite ground can still have a visible
border at extreme angles; a seamless infinite horizon is not claimed.

### Extended controlled matrix

Use the same `tests/manual/ambient_render_audit.gd`; there is no second harness.
Legacy A–J keep their original reference meaning. The following cases instead vary
one factor from current `clean`, unless explicitly described as combined:

| Cases | Change |
| --- | --- |
| previous | Prior cleanup: 200 m, grey floor, sky (combined reference) |
| distance36 / distance48 | 36 / 48 m versus clean 72 m |
| splits2 | Two PSSM splits, other values unchanged |
| splits_near | Four splits .05/.15/.40, versus .08/.20/.45 |
| filter_high / filter_low / filter_hard | High / Low / Hard, versus Medium |
| blur05 / blur025 | Blur .5 / .25, versus 1 |
| high_blur05 | High + blur .5 (explicit combined candidate) |
| atlas8192 / depth32 | 8192/16-bit or 4096/32-bit, versus 4096/16-bit |
| bias003 / normal_bias1 | Bias .03 or normal bias 1, one at a time |
| no_shadows / no_sun | Disable directional shadows / sun; ambient retained |
| no_aa / msaa4 / taa | None / MSAA4 / TAA; never stacked with SMAA |
| unshaded / matte / normals | Per-instance diagnostic override, shared assets untouched |
| ground_hidden / ground200 / ground1500 / ground_grey | Hide ground / size 200 / size 1500 / old material |
| sky / sky_deband / viewport_deband | Sky without/with sky debanding; viewport debanding alone |
| no_post / lod_original | Disable adjustment+glow (combined); restore exact original casing geometry |

`--view=overview|close|flat|distant` chooses deterministic framing. `--target=Proxies/...`
centers the chosen MeshInstance3D for all cases, important for a real show's flat
wall or distant truss. Without a target the scene bounds center is used. A synthetic
untextured `AuditFlatBox` is included alongside thin box casters when no MVR is given.
`--moving` follows the same per-frame orbit/zoom sequence; use video for temporal
flicker/ghosting. Filenames now include the view to avoid overwriting different views.

PowerShell example (Godot executable as in the earlier instructions):

```powershell
$Out = Join-Path $PWD 'ambient-followup'
$Cases = 'clean','previous','distance36','distance48','splits2','splits_near','filter_high','filter_low','filter_hard','blur05','blur025','high_blur05','atlas8192','bias003','normal_bias1','depth32','no_shadows','no_sun','unshaded','matte','normals','no_aa','msaa4','taa','ground_hidden','ground200','ground1500','ground_grey','sky','sky_deband','viewport_deband','no_post','lod_original'
foreach ($View in 'overview','close','flat','distant') {
  foreach ($Case in $Cases) {
    & $Godot --path . --rendering-method forward_plus --audio-driver Dummy --script tests/manual/ambient_render_audit.gd -- "--case=$Case" "--view=$View" "--out=$Out\synthetic" --gpu-time
    if ($LASTEXITCODE -ne 0) { throw "Audit failed: $Case / $View" }
  }
}
# Repeat with the SAME real MVR and target path on EVERY call:
$Mvr = 'C:\Shows\representative.mvr'
$Target = 'Proxies/path/to/flat/MeshInstance3D'
& $Godot --path . --rendering-method forward_plus --script tests/manual/ambient_render_audit.gd -- --case=no_shadows --view=flat "--mvr=$Mvr" "--target=$Target" "--out=$Out\show" --gpu-time
# Repeat the matrix with --moving, including clean and TAA, and record video.
```

Keep `--gpu-time` consistent across trials. JSON contains actual frame-time mean,
standard deviation, reciprocal FPS, counters and GPU mean/sample count from the
Viewport timing API. A null GPU value means unsupported/not requested; never treat
zero or headless results as GPU measurements. Default warmup/sample counts remain
120/300. `--warmup=2 --frames=10` is only a fast structural smoke, not a benchmark.

Isolation sequence on the *same target*:

1. Compare clean, no_shadows and no_sun at flat and close views. If the pattern
   disappears only with shadows off, prioritize shadow acne/filtering, not materials.
2. Compare matte, unshaded and normals; then no_aa and no_post. A persistent pattern
   in unshaded geometry is a reason to investigate depth/overlap rather than lighting.
3. Compare the synthetic box against imported surfaces, ground_hidden, lod_original
   and near (0.1 m). Check whether artifacts track mesh edges, camera distance or sun.
4. JSON inventory records up to 256 imported meshes with paths, parent ownership,
   resources, transforms, determinant, bounds and missing-normal surface counts.
   Identical AABBs are candidates only: intersecting bounds do not prove coplanar
   faces. Inspect the actual vertex/index faces and ownership in Godot before any fix.
   `--hide-node=Proxies/exact/path` can explicitly hide one suspected object for this
   diagnostic process; it never changes production or shared resources.
5. With `--target`, use `--no-target-cast` to remove only that object's casting while
   retaining receiving, testing self-shadow involvement. Compare world origin against
   `--world-offset=100000` in a separate output directory. This shifts only the
   diagnostic root (camera/scene together), leaving imported local transforms intact;
   it is never an import correction or a production coordinate remap.
6. Then compare shadow distance, splits, filter/blur, bias, depth and AA independently.
   Reject detached/thinned contacts and missing distant shadows even if grain improves.

No supplied real-show mesh is diagnosed as defective. Housing, selection, LOD,
Pan/Tilt, prisms, both projection backends, haze and live DMX still need graphical
acceptance after selecting a shadow candidate. This follow-up deliberately does not
present a headless pass as a solved shadow/noise problem.

### Follow-up execution results

- Godot 4.7.1: `python3 .github/scripts/run_gdscript_tests.py --godot /workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64 --project /workspace/Peraviz --output /workspace/work/correction-suite --timeout 60`: **52/52 passed**. Includes the updated matte/opaque ground, 2000 m coverage, the then-current sky/studio restoration and explicit background color regressions (subsequently replaced by sky-preservation regressions), plus existing footprint, LOD, native projector, haze and Pan/Tilt contracts.
- `ctest --test-dir native/build --output-on-failure --timeout 120`: **15/15 passed**; no native code changes.
- The 31 follow-up cases plus clean/depth32/A ran headlessly with `--warmup=2 --frames=10`: **34 passed**. Generated small MVR imports passed close/flat/distant moving views. An additional targeted imported-mesh smoke exercised `--no-target-cast`, `--hide-node` and `--world-offset=100000`. These are state/control checks, not visual or performance comparisons.
- `bash tests/check_no_large_files.sh`, `bash tests/check_runtime_architecture.sh`, `git diff --check`: passed (existing soft-limit file-size warnings remain).
- Graphical command attempted: `Godot_v4.7.1-stable_linux.x86_64 --path . --quit-after 2` with writable XDG directories. Failed to initialize X11/Wayland. No GPU timing, new screenshots or image-quality claims are available from this environment.

The larger plane has a 1000 m half-extent versus a 500 m navigation radius, not
infinite coverage. An 8192 atlas would use four times the depth texels; 32-bit depth
doubles raw depth storage compared with 16-bit at the same size. These are resource
ratios, not measured frame-time changes. Both remain diagnostic-only.

### Sky preservation correction

User testing found no appreciable shadow improvement and rejected the studio
background. Restore the original sky as the sole enabled-controller background and
remove the added UI/defaults/loader mapping. Keep the opaque dark matte 2000 m ground.
Regression coverage verifies Day/Night sky restoration and ignores the obsolete
saved studio flag. The directional shadow parameters were not changed by the
follow-up; shadow aliasing/surface noise remain unresolved graphical findings.

Sky correction validation: the focused Godot 4.7.1 ambient regression passed, including
missing-key restoration, the obsolete false studio flag, Day/Night sky, and the retained
dark matte receiver. Architecture, file-size and diff checks passed. Graphical shadow
improvement remains unverified and was not established by these tests.

## Grey ground and bias correction after Windows feedback

The charcoal floor was too dark in daylight. Restore a readable grey albedo .4
(original .45), keeping roughness 1, metallic/specular 0, opaque lighting, adaptive
2000 m coverage and no shadow casting. Preserve the original sky. Floor size is not
assumed to be a performance problem simply because its extent is large; it remains
a minimal plane. Its finite edge can still appear at grazing viewing angles.

[Godot 4.7 Light3D](https://docs.godotengine.org/en/4.7/classes/class_light3d.html)
uses bias .1 and normal bias 2.0. The scene's custom .015/.7 values reduce separation
between receiver and stored shadow depth, making acne a plausible cause of the fine
surface pattern. Restore the engine values as a concrete candidate, without changing
shadow resolution, filter, AA, range, cascades or geometry. This has no added atlas
allocation or filter sample count, but may detach or thin shadows: inspect cylinder
contacts before accepting. It is not a verified cure for silhouette aliasing.

The [Godot forum example](https://forum.godotengine.org/t/why-are-my-shadows-dithered/142905)
separates filtering grain from cascade resolution. Historical issue
[12028](https://github.com/godotengine/godot/issues/12028) concerns 3.x SpotLights;
it does not establish a 4.7 directional-light defect here. No workaround from that
old issue is applied. In particular, camera far-plane reductions from orthographic
examples are not blindly applied to this perspective editor camera.

Scale review: `gdtf_scene_builder.cpp::convert_translation_m_to_mm` converts GDTF
local translations to the importer's intermediate millimetres; native scene
conversion exports Godot metres. Loader `IMPORTED_CONTENT_SCALE` remains 1.0.
The existing imported-transform tests remain the guardrail. This source review
finds no global double scaling; it cannot rule out a malformed individual mesh
without the original show. No unit conversion, hierarchy or imported transform is
changed. The repeating texture is still a hypothesis of acne, not proof of bad scale.

The same synthetic scene now includes two 10 cm diameter horizontal CylinderMeshes
above the flat box to reproduce the reported caster type. Compare `clean` (.1/2),
`old_bias` (.015/.7), `bias_only` (.1/.7), `normal_only` (.015/2), then `no_shadows`:

```powershell
foreach ($Case in 'clean','old_bias','bias_only','normal_only','no_shadows') {
  & $Godot --path . --rendering-method forward_plus --script tests/manual/ambient_render_audit.gd -- "--case=$Case" --view=close "--out=$Out\bias" --gpu-time
}
```

Repeat on the actual flat imported panel using the same `--mvr`/`--target` for every
case, then repeat with `--moving`. If the pattern persists with shadows disabled,
bias is not sufficient: compare unshaded/matte/normals and coplanar-face diagnostics.
If bias cleans the surface but the edge remains stepped, that is a separate
resolution/filter comparison; larger atlases or TAA have not been enabled by default.

Source cross-check: the [Godot 4.7 Forward+ scene shader](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)
applies directional depth bias and an angle-dependent projected normal offset before
sampling the shadow map. This supports testing receiver self-shadow precision; it
is not a claim that the screenshots prove acne. The native metre conversion is
explicit in `coordinate_mapper.cpp::map_position_mm_to_m` (division by 1000, plus
axis mapping). No project-scale workaround was applied.

Grey/bias revision validation: all **52 GDScript regressions passed** with Godot
4.7.1 via `run_gdscript_tests.py` (logs in `/workspace/work/grey-bias-suite`). The five
close-view bias/no-shadow smoke cases completed headlessly and recorded the expected
independent values. Runtime architecture, file-size and `git diff --check` passed
(existing soft warnings remain). No GPU frame-time or visual improvement is claimed.
