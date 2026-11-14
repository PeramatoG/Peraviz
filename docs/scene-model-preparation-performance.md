# Scene model preparation follow-up

## Evidence and scope

The owner reports a successful production import but several minutes in
**Building scene models** after the initial large-MVR fixes. The supplied log
confirms 23,154 native nodes, 9,661 SceneObjects, 81 fixtures and 12,103 attached,
visible model owners, with zero invalid basis fallbacks/world bounds. It does not
contain the opt-in `[peraviz-load]` phase summary, so it cannot establish whether
3DS parsing, glTF decoding, texture upload, materials or traversal dominates that
particular load. Existing missing-body/duplicate-Dimmer diagnostics are unchanged;
this follow-up does not reinterpret fixture or DMX semantics.

The original MVR was supplied, but the attachment transfer tool rejects files
larger than 32 MiB. It was not copied into the workspace or inspected. Production
speedup is therefore **unmeasured**. All assets used below are public synthetic
fixtures; no proprietary geometry, archive contents or user paths are committed.

The previous shared-geometry stress case cannot represent thousands of distinct
resources. The new generator exercises 1,000/4,500 separately named 3DS files,
960 triangles per file, one real shared external PNG, and an inherited reflection.
A separate glTF case uses 1,000 distinct paths with two material surfaces and an
embedded texture per source. Different authored paths remain distinct models.

## Confirmed repeated work

1. NodeFactory initially built a 3DS mesh using only its local basis. After
   attachment, inherited reflection could require reopening and decoding the same
   file, validating it, generating normals, copying packed arrays and creating a
   second mesh/texture. In the 4,500-file reflected case this produced 9,000 native
   decode calls and 9,000 cached meshes, although only one variant per path was
   used by the completed scene.
2. Every newly built 3DS mesh loaded and uploaded its albedo image, even when other
   model paths referenced exactly the same resolved texture path. The reflected
   case performed 9,000 image loads; its visible instances used 4,500 separate
   texture resources containing the same image.
3. The native 3DS output converter invoked Godot packed-array `size`/`set` bindings
   inside each vertex/normal/index/UV loop. Buffers were already pre-sized, so the
   per-element ABI dispatch was unnecessary.

Existing cache reuse for repeated mesh/PackedScene paths already works. Distinct
scene owners still need independent Node instances. Global node pooling, merging
models by similar filenames/content, persistent cache ownership and new worker
subsystems are not needed for these corrections.

## Implementation and safety boundaries

NodeFactory creates the same validated native shells and Axis/Emitter markers
first, then builds a generation-local O(nodes) orientation index from those local
transforms and the same parent IDs used by attachment. Models are created with
that inherited parity while still detached. The original attachment order,
loading shield, cancellation checkpoints, late orientation safety pass, LOD and
renderer installation/publication remain. No alternate live transform authority
survives setup. Child-before-parent records, reflected proxy roots and double
reflections are covered. Standalone `create_scene_node` callers retain the local
construction behavior through its default arguments.

The 3DS albedo cache is scene-owned and keyed by the **exact resolved path**.
Image decode, RGBA8 conversion and ImageTexture creation occur once per such path.
Different paths are not merged by basename or byte resemblance. Materials and
instance state remain under their existing owners. Failed image state prevents
repeated attempts in that generation; retirement clears textures and failures so
a later load retries. Native texture search precedence, traversal/ambiguity rules,
archive extraction leases and explicit model/quality selection are unchanged.

The native converter now validates resized lengths and writes through Godot's
public writable packed-buffer pointers. It keeps the same mm-to-m conversion,
axis mapping, indices, normals, UVs and material fields. Zero-length arrays do not
request a writable element pointer. Allocation failure returns a stable error
through the existing loader failure contract. Chunk validation, file parsing and
normal/winding algorithms have not been relaxed or replaced.

## Measured observations

Linux, official Godot 4.7.1/a13da4feb, native Debug extension, headless Compatibility
for preparation timings. The baseline is merged PR #133 (`a8a00df`, unchanged by
merge commit `81cd7d7`); baseline instrumentation only counted/timed existing work.
Each preparation probe starts in a fresh process with empty Godot resource caches.
Archive extraction/native scene parsing occurs before the reported preparation
interval. OS caches are not forcibly purged. Timings are observations, not CI
thresholds or predictions for Windows/RTX 3070.

| 4,500 distinct reflected textured 3DS models | Baseline | Candidate |
| --- | ---: | ---: |
| Preparation harness wall time | 25,547 ms | 15,534 ms |
| Native mesh decode calls | 9,000 | 4,500 |
| Mesh creations / raw mesh cache entries | 9,000 | 4,500 |
| Texture decode/upload calls | 9,000 | 1 |
| Visible albedo texture resources | 4,500 | 1 |
| Late orientation correction | 7,578 ms | 139 ms |
| New orientation plan, including checkpoints | absent | 97 ms |

In a separate 500-call load probe for a generated 2,145-vertex / 11,904-index 3DS,
the complete native binding loop took 1,560 ms before / 1,359 ms after writable
buffer transfer. That interval includes file reading and parsing; it does not
isolate copy time. Serialized packed data and metadata had the same SHA-256
`dd9310db22e7ac4a0a0de20460e9aceab99335952188f4782498892333a7b4da`
on the same machine/path. This is a local exact-output comparison, not a portable
cross-compiler golden hash or a mandatory timing assertion.

For positive, unmirrored 3DS-only scenes there is no claim of halving mesh decodes:
only redundant inherited-parity variants are avoided. Both variants remain valid
when different instances genuinely need different handedness. Each distinct model
still has to be decoded at least once, and distinct texture files remain distinct.
The native buffer-copy improvement also applies to the first/only decode.

## Investigated but deliberately retained

Runtime glTF currently generates a scene, packs a reusable prototype, then
instantiates its first independent instance. A singleton-only prototype bypass was
probed, but the small-model wall-time gain was not clear enough to justify changing
the working lifecycle. **The production PackedScene route is retained for all
runtime glTF**, including singletons, animations and local-to-scene resources.
New pack/clone counters make this cost measurable in an owner trace.

The native 3DS companion resolver still checks direct/ancestor paths and, when
needed, performs a bounded unique-basename directory search. No filesystem result
cache is introduced without an explicit immutable ownership/invalidation context.
We also retain current dummy removal, per-instance bounds/visibility inspection,
LOD eligibility/inventory, shader preparation, material independence and renderer
resource ownership. Their existing/new timers can identify the next bottleneck;
the present log cannot establish their share of the production minutes.

## Telemetry and reproduction

`PERAVIZ_LOAD_TELEMETRY=1` or `-- --peraviz-load-trace` retains bounded phase output.
Added observations are `mesh_decode_calls`, `mesh_build_calls`,
`texture_decode_calls`, `scene_decode_calls`, `scene_pack_calls`,
`scene_clone_calls`, `mesh_creation_ms`, `texture_preparation_ms`, `scene_pack_ms`
and `orientation_plan_ms`. Scene instantiation timing now includes the first
post-pack clone as well as cache-hit clones. Texture cache counts/hits/misses and
failed-image cardinality appear in the existing cache summary. Texture preparation
includes decode/conversion/CPU submission of the upload; it is not a GPU fence.
Nested timings overlap and must not be added as independent totals.

```sh
python3 tests/integration/generate_resource_preparation_fixture.py /tmp/distinct.mvr --count 4500
"$GODOT_BIN" --headless --audio-driver Dummy --rendering-method gl_compatibility --path . --script tests/integration/benchmark_resource_preparation.gd -- /tmp/distinct.mvr
# --positive isolates an unmirrored hierarchy; --kind glb probes glTF;
# --repeated gives many references to one file; --animated retains real tracks.
```

The preparation harness can also run against a locally available production MVR
without uploading it. Its `RESOURCE_PREPARATION_BENCHMARK` row contains aggregate
metrics, not model names or geometry. Its interval excludes native archive/scene
preparation, runtime registration and first rendering. For end-to-end observations,
launch the normal application with tracing, import normally and compare the final
`[peraviz-load]` row on the same machine/content/settings before and after.
A same-process reload reuses extracted files while their native leases remain;
Godot geometry/texture caches still retire and rebuild. No cross-launch cache
policy is changed.

Regression coverage checks exact mesh buffers against direct native data, inherited
winding, world translations, reversed record order, proxy/double reflection,
texture path identity, failed-image retirement/retry, detached-shell cancellation,
unchanged glTF packing, authored animation poses and independent playback/nodes.
The existing large-import, LOD, resource-lifetime, renderer, selection, optics and
DMX suites remain applicable. Windows/RTX 3070 and actual-production timing remain
owner-side validation.

## Validation on this candidate

- Native CTest: 15/15 passed after rebuilding the extension and test targets.
- Full headless GDScript suite: 57/57 passed, including the new resource regression.
- ASCII, accented and non-Latin importer/lifetime smoke: identical geometry identities.
- Graphical import probe: Godot Forward+ with software Vulkan under Xvfb,
  `test_gdtf_fixture_geometry.gd -- --render-import-probe`; loading completed,
  published root visible, 89,223 changed viewport pixels. This confirms rendered
  fixture output on Linux, not Windows/NVIDIA performance or production coverage.
- Runtime architecture, source-size guardrails and `git diff --check` passed
  (existing file-size advisory warnings remain).
