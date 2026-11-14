# First-import placeholder material investigation

## Production evidence

The owner supplied a Windows first-import trace from Godot 4.7.1 Forward+ on an
RTX 2060. It includes the operation counters introduced in PR #134. Total import
was 842,015.774 ms. Native load took 47,272.355 ms, node resources 762,408.650 ms,
and first-render preparation 19,521.873 ms. Node construction (native shells plus
visual installation, excluding budget awaits) accounted for 702,721.166 ms.

Nested geometry decoding was only 20,118.687 ms, mesh creation 2,306.271 ms and
imported material preparation 3,365.476 ms. Those cannot explain the construction
interval. The imported mesh cache was functioning: 4,498 mesh decodes/builds and
17,728 hits; six glTF decodes, 437 clones and 18.470 ms of scene instantiation.
There were no external 3DS image decodes in this load. Timers are nested and must
not be summed as independent phases.

The material cache recorded **9,680 hits on one prototype**. The active production
caller is `NodeFactory._create_dummy_mesh`, which requests `clone_for_instance=true`.
That exactly matches the 9,661 SceneObjects plus 19 trusses. A native semantic owner
without a direct asset still creates a dummy, including owners whose child model
parts later make the dummy redundant. `get_material` deep-duplicates every stored
StandardMaterial3D property, binds the temporary back-face-culling material, and the
subsequent double-sided pass duplicates it again. A hidden root does not prevent
this resource work. The imported-material timer did **not** enclose this path.

The proprietary MVR still cannot be transferred by the attachment tool (32 MiB
limit). Its trace establishes the unexplained interval and actual prototype use;
it does not directly time each clone. The controlled graphical reproduction below
establishes the placeholder cost. The precise savings on this production MVR
remain an owner-side before/after observation, not a guaranteed extrapolation.

## Correction and ownership

Known built-in dummy descriptors now construct their final independent
StandardMaterial3D directly with the same color and disabled culling. The same
independent default surface override is retained, even though the whole-instance
override normally takes precedence. This also preserves behavior if a caller
clears the whole-instance override. There is no prototype duplication, temporary
back-face material or subsequent duplicate-and-rebind pass for these known dummies.

Shapes, scale normalization, node names, metadata, parent attachment, removal of
redundant dummies, source geometry, fixtures, cancellation, picking and publication
remain under their existing owners. Every surviving dummy still owns its mutable
materials; editing one does not affect another. The imported material preparation
and optics paths are unchanged, including immutable scenery sharing and genuinely
independent fixture state. No global node pooling, MultiMesh conversion, Godot
worker, resource lease change, cache persistence or renderer rewrite is introduced.
The unused legacy construction helpers in `load_scene.gd` remain outside the active
NodeFactory pipeline; this fix does not restore them as an alternate authority.

## Reproduction and measurement boundaries

`tests/integration/benchmark_builtin_placeholders.gd` contains a test-only reference
constructor reproducing the old prototype/deep-copy/double-sided path. Both variants
use the same production build pipeline, hidden root, 1,000 distinct semantic owners,
frame budget, attachment, cleanup and diagnostics. No file decoding is involved.
Run serially on the same machine and settings:

```sh
"$GODOT_BIN" --path . --audio-driver Dummy --rendering-method forward_plus --windowed --resolution 640x360 --script tests/integration/benchmark_builtin_placeholders.gd -- --count=1000 --reference
"$GODOT_BIN" --path . --audio-driver Dummy --rendering-method forward_plus --windowed --resolution 640x360 --script tests/integration/benchmark_builtin_placeholders.gd -- --count=1000
```

Linux, official Godot 4.7.1/a13da4feb, Debug native extension, Xvfb 640×360, software
Vulkan/llvmpipe. Each run starts a new process; engine/OS caches are not purged.
Reported intervals start after engine startup. Driver initialization and any initial
shader cache warmup before the interval are excluded. No timing is a CI threshold
or a prediction for Windows/NVIDIA. The test-only reference is not a production
runtime fallback.

| 1,000 built-in placeholder owners | Pre-fix reference | Candidate |
| --- | ---: | ---: |
| Pipeline wall time | 26,323 ms | 1,353 ms |
| Synchronous node construction | 21,588 ms | 390 ms |
| Dummy creation (nested) | 21,468 ms | 353 ms |
| Dummy material preparation (nested) | 20,901 ms | 259 ms |
| Budget checkpoint waits | 4,597 ms | 900 ms |
| Yielded frames | 1,013 | 43 |
| Placeholder instances | 1,000 | 1,000 |

The reference/candidate retain both whole-instance and surface overrides. An
initial independent microprobe without the full pipeline also reproduced the
bottleneck (about 29 s for 1,000 pre-fix dummies). A broader 1,000-distinct-textured-
3DS investigation located 26,809 ms in dummy materials versus only 1,071 ms in
resource decoding. Removing the repeated known-material setup is therefore more
relevant than optimizing those file reads in this reproduction. Wall time remains
sensitive to frame scheduling, renderer load and cache state. Do not project the
isolated benchmark ratio onto total production import.

No cross-session cache behavior changes: fresh-process resource state is rebuilt;
same-session imports retain native extraction only while leases remain valid and
retire/rebuild Godot generation resources. The isolated benchmark has no archive
or disk assets to reuse. It is not a measurement of a completely cold OS/driver.

## New bounded diagnostics

The existing opt-in `[peraviz-load]` summary adds:

- `shell_creation_ms`: detached native shell creation/metadata/transforms.
- `visual_creation_ms` and `visual_attach_ms`: visual construction versus ownership attachment.
- `dummy_instances_created`, `dummy_creation_ms` and `dummy_material_ms`: actual built-in placeholders and their material cost, previously outside the imported-material timer.
- `primitive_creation_ms`: authored primitive/fallback geometry creation.
- `mesh_instance_creation_ms` and `mesh_instance_assignment_ms`: 3DS renderer instance creation versus resource binding.
- `budget_yield_wait_ms`: total time inside budget checkpoint awaits, across import phases. This is separate from synchronous construction spans, includes other event-loop/render work, and is not pure CPU idle or GPU time.

These are aggregate fields; no per-node logs, paths or geometry are added. Nested
spans overlap. The preparation benchmark also reports yielded frames/wait time so
a smaller construction interval is not confused with a proportional wall-time gain
when frame scheduling or the software renderer is saturated.

## Other inspected costs and unresolved boundaries

- Archive extraction consumed 29,843 ms for 4,516 resources / 83,194,608 bytes in
  the owner trace. It remains material, but cannot explain the twelve-minute node
  phase. First-import publication still owns the extracted files through leases.
  This patch does not add a persistent cache or relax path/security checks.
- Model inspection: 26,088 calls / 1,669 ms; bounds/diagnostics traversal 5,339 ms;
  LOD installation 4,192 ms; late orientation 601 ms; dummy removal 662 ms. These
  remain measurable but are not the unexplained hundreds of seconds.
- Renderer installation is an existing atomic transaction (7,590 ms here). First
  activation used 161 acknowledged batches / 9,125 ms. Its visibility audit cost
  8,349 ms. Frame acknowledgments, readiness, cancellation and the setup/live
  transaction boundary are retained; increasing batches does not address dummy
  construction.
- The owner log's 2,212 null-material renderer errors occur **after** the final load
  summary and after all fixtures unregister on teardown. They are not evidence of
  a failure during the measured successful import. No warnings are suppressed and
  no speculative renderer-lifetime change is bundled. Graphical lifecycle tests
  below check for errors on reproducible public inputs; any remaining production
  teardown error needs its own reproducer.
- Existing missing-body and unsupported DMX/Auto Span diagnostics retain their
  semantics. A successful import is not a claim that every authored fixture
  feature or model exists.

## Regression contract

`test_builtin_placeholder_preparation.gd` compares both whole-instance and surface
stored material properties against the pre-fix constructor, and shape AABBs at
small/default/large scales. It builds and reloads 10,000 semantic owners, compares
world transforms under a small reflected parent, checks independent material edits,
and cancels during dummy construction without publishing detached shells.

Its optional `--render-placeholder-probe` compares exact Forward+ viewport pixels
for both box and cone descriptors and requires actual foreground coverage; headless
counts alone do not prove rendered equivalence. The full existing import, selection,
fixture, optics, DMX, resource-lifetime and first-render suites remain applicable.


## Candidate validation

- Complete native CTest suite: 15/15 passed; native code is unchanged relative to
  the PR #134 prerequisite.
- Optional placeholder Forward+ probe: exact legacy/candidate pixels for both
  descriptors, with 288 box / 138 cone foreground pixels. No renderer errors.
- Full graphical MVR/GDTF fixture import probe: loading completed, root published
  visible, 89,223 changed viewport pixels; no renderer/null-material errors during
  that reproducible import/teardown.
- Runtime architecture, source-size guardrails and diff checks passed (existing
  advisory size warnings remain).

The graphical checks use software Vulkan on Linux. They verify public-input
rendering/lifecycle behavior, not Windows/RTX timings or the proprietary show's
post-exit error reproduction. Full headless suite results are recorded in the PR.
