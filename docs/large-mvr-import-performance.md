# Large MVR import: correctness and setup performance

## Scope and confirmed causes

This change preserves native fixture geometry templates, runtime classification
indexes, Control Groups, Render Groups, authored model detail, selection/picking
ownership and the first-render readiness barrier. It does not introduce scenery
MultiMesh or change DMX interpretation.

Confirmed in the prior implementation:

- `ZipAssetCache::resolve_entry` scanned all entries for every exact/case/basename
  resolution. Extraction additionally sanitized and compared every other archive
  entry, and each model directory scanned the full archive for companions.
- Both Godot basis validators used an absolute approximate-zero determinant test.
  A valid diagonal `0.001` basis was replaced with identity because its determinant
  is `1e-9`. This discarded scale rather than repairing invalid data.
- MVR `GroupObject` children were assigned a parent ID without emitting the group
  node. Attachment therefore lost the group transform. Layer elevation was also
  omitted from emitted root transforms.
- Repeated opaque scenery duplicated the same double-sided material, including
  deep texture duplication. `ModelGeometry.inspect` repeatedly fetched primitive
  surface arrays to answer the same immutable renderability question.
- First visibility submitted at most 16 instances per acknowledged batch: 10,000
  instances required 625 batches, even when resources were shared.
- Camera focus capped the orbit at 500 m, ignored the narrower viewport FOV,
  retained unsuitable clipping for tiny scenes, and initially interpolated from
  the previous camera pose. Queued dummy geometry could remain in the immediate
  bounds traversal after being scheduled for deletion.

The proprietary `STG MAHOU.mvr` is unavailable. These are confirmed code defects
and synthetic reproductions, not a claim to have identified every cause of that
file's empty presentation or its reported 5–10 minute load.

## Archive resolution and ownership

Each cache owner builds exact, ASCII case-compatible and unique-basename indexes;
ambiguous aliases have explicit rejection markers. The ZIP wrapper exposes its
rejected case aliases so omission from `list_files` cannot make another basename
appear unique. Existing normalization, Unicode byte identity, traversal rejection,
format/quality precedence and explicit GDTF paths remain authoritative.

Sanitized destinations and case-compatible destination collisions are prepared
once. Supported companion files are indexed under their containing directory and
its non-root ancestors. Root models retain the historical root-only companion
policy. Setup is proportional to entry/path data, plus the existing sorted file
listing; reference resolution uses expected constant-time hash lookups. Repeated
models share canonical extraction and one dependency visit per directory. MVR
XML reads reuse the already opened archive and historical sorted XML selection.

Companion selection remains conservative. External image/buffer references can
exist in 3DS/glTF and other accepted compatibility formats. The cache does not
parse sufficient dependency semantics to prune a model directory safely. It does
avoid unrelated directories, tested with thousands of unreferenced assets. Exact
URI/material dependency parsing is a separate optimization, not an extension-based
assumption that every GLB is self-contained.

`RuntimeDirectoryLease` ownership and final-owner cleanup remain unchanged. A live
second owner can reuse extracted files; no cache survives a process session by
policy. Invalidated source contents obtain another content identity.

## Transform and visibility contract

The authority is the official [MVR Matrix definition](https://github.com/mvrdevelopment/spec/blob/main/mvr-spec.md#node-definition-matrix):
right-handed, Z-up, one distance unit = one millimetre. The native mapper retains
`C * basis * C^-1` and converts translation to metres exactly once. The specification
also defines 3DS units as millimetres; glTF retains its own embedded transforms.

Godot validates finite axes and nonzero column lengths, then tests normalized
column volume (`abs(det) > 1e-6`) and a finite, nonzero actual determinant/inverse.
This rejects dependent/unusable float matrices without using absolute scale as a
singularity test. Small nonuniform, rotated and reflected bases are preserved.
The Euler compatibility path also preserves nonzero small scales. Invalid basis
fallbacks are counted per import and reported once. The legacy validator delegates
to the same implementation.

Groups now have semantic nodes without dummy geometry. Layer transforms fold once
into their top-level children, preserving the existing emitted layer-less graph.
Redundant placeholders detach immediately, so deferred deletion cannot inflate the
first camera bounds. Focus uses the narrower viewport angle and a bounding sphere,
adapts navigation/clipping to scene size, and installs the fitted pose immediately.
For tiny scenes, keeping an arbitrarily small near plane with a distant far plane
actually caused Forward+ `create_frustum_points` errors despite passing headless
frustum checks. Focus now keeps a usable far/near ratio and moves back enough to
keep the model beyond near clipping, retaining the distant range for optics.

Four distinct observations must not be conflated:

1. The scene is intentionally hidden/covered during preparation.
2. Attached nodes and finite bounds establish scene-tree/resource structure.
3. Frustum tests establish camera inclusion and clipping.
4. Rendered image comparisons establish viewport pixel contribution.

The graphical tests exercise stages 3 and 4; node/visibility counts alone do not
prove pixel coverage or absence of occlusion in an arbitrary production scene.

## Godot resource and activation changes

Only ordinary MVR `model_part` scenery on the 3DS/static-runtime-glTF routes can
share prepared opaque StandardMaterials. Animated/Skeleton scenes, emissive or
transparent materials, next passes, local-to-scene resources, animated/viewport
textures and unknown material classes keep the existing preparation route.
Fixture geometry/optical materials retain their independent path. Prepared copies
share immutable textures and never mutate the authored source material.

Mesh renderability facts belong to the scene asset cache. Inspection still
traverses each current instance and recomputes hierarchy transforms, bounds,
attachment and visibility; none of those mutable results are cached. Retirement
clears facts, prepared materials and observations. Inspection profiling has no
static script state retaining resources after unload.

Activation starts at 64 instances and adapts between 64 and 256 based on the
acknowledged batch duration (33 ms target). A soft 4 ms CPU slice can stop a batch
earlier, checked every 16 submissions. Each batch still awaits `frame_post_draw`,
then final readiness awaits three acknowledgments. These are renderer acknowledgments,
not GPU fences. Hidden-window deferral, lost-ack timeout, cancellation and generation
retirement retain their existing behavior. No synchronous all-scene activation is
introduced; an individual engine/driver call remains non-preemptible.

## Measurements and limitations

Linux, official Godot 4.7.1/a13da4feb; native Debug application build. Standalone
archive comparisons compile the same benchmark at `-O2` against baseline cache
sources and the candidate. Graphical checks use Xvfb and Forward+ llvmpipe/LLVM 19,
640×360. Measurements came from a shared cloud machine; archive and material table rows were rerun sequentially without compilation;
software rendering overlapped an archive baseline in the activation pair, and
driver caches can affect startup. No portable
speedup, CI timing threshold, Windows result or proprietary-file timing is claimed.

| Isolated workload | Baseline observation | Candidate observation |
| --- | ---: | ---: |
| 4,500 distinct models, extraction-cold resolution/extraction | 23,348 ms | 238 ms |
| Same archive, live-lease warm resolution/extraction | 24,671 ms | 31 ms |
| 10,000 repeated case-compatible lookups, cold owner | 1,617 ms | 25 ms |
| 10,000 scenery material preparations | 1,056 ms / 10,000 materials | 65 ms / 1 material |
| 30,000 model inspections | 311 ms | 172 ms |
| 10,000 visuals, graphical first activation | 47,229 ms / 625 batches | 9,477 ms / 125 batches |

The activation pair produced exactly 17,905 cyan pixels in both cases and three
final acknowledgments. The candidate's largest measured activation CPU submission
slice was 1.354 ms. This isolates first visibility, not an entire MVR import.
The baseline and candidate archive warm owners both retain the extraction lease;
the baseline still performs its collision/directory scans before file reuse.

A full synthetic 10,000-object import with 100 transformed groups, repeated
Symdefs, mixed GLB/3DS, three fixtures and 4,500 unrelated archive entries retained
20,112 native nodes and all 10,000 model parts. Scenery used two mesh and two
prepared material resources. The final traced headless run took 12.94 s cold / 8.85 s
same-content reload. It wrote eight assets / 6,034 bytes cold, zero assets / zero
bytes on reload. Godot scene caches retire on reload: resources/instances are
rebuilt, while native extraction leases, OS pages and driver state can be warm.
Cross-launch extraction reuse is not implemented.

That run still exposed a 1.77 s native node-payload transfer on the cold load
and a 0.59 s maximum interruption on reload (node-payload phase). Fixture
registration took 1.03 s cold / 0.54 s warm, including its yielded setup work. Orientation, dummy removal, bounds diagnostics
and LOD inventory remain measurable whole-tree setup work. The new metrics make
these visible; they are not evidence that every main-thread import interruption
is below the 8 ms construction budget. A sectioned/incremental node payload and
further budgeted registration/traversal are follow-ups, without replacing the
existing native setup/runtime architecture.

## Telemetry

Use `PERAVIZ_LOAD_TELEMETRY=1` or `--peraviz-load-trace`. Logging remains phase-level
and bounded, with existing first/middle/final activation breadcrumbs.

- `archive_open_index_ms` includes content hashing, opening and index construction;
  `archive_entries` sums accepted entries per opened cache owner.
- `unique_asset_references` counts distinct resolved canonical extraction references
  per owner; `unique_lookup_references` includes normalized candidate probes.
  `indexed_lookups`, extraction cache hits/misses, physical extraction count/bytes,
  dependency candidates/discovery and extraction time describe actual cache work.
- `xml_parse_ms` covers the MVR document and Symdef parse; `archive_xml_ms` retains
  the broader prior phase. `geometry_ms` retains native fixture expansion, and
  `native_mvr_ms` covers the complete native MVR/scenery preparation.
- Existing mode/runtime compilation, payload, controls and render-group metrics
  remain. `node_resources_ms` covers yielded Godot construction; opt-in
  `node_construction_ms`, `resource_decode_ms`, `scene_instantiation_ms` and
  `material_preparation_ms` separate hot operations.
- Orientation, dummy removal, LOD installation, bounds/diagnostic traversal,
  model inspection calls/time, asset-cache resource counts, visibility audit,
  activation CPU/wall time, first-render time, total time and largest uninterrupted
  main-thread/event-loop intervals are reported. Nested scopes overlap; do not sum
  all fields. Per-operation counters are zero when tracing is disabled.

`duplicate_manifest_target_ids` counts repeated handles in the registry's semantic
maps, not repeated mesh instances. Stable compiler target identities derive from
fixture UUID, semantic role and geometry path. Multiple source/attribute components
or invalid identities require inspecting the existing bounded `first_failures` and
native diagnostics. The 10k repeated-scenery regression reports zero duplicates.
Without the original selected GDTFs/manifest, the reported 30 cannot be classified
as invalid DMX semantics or safely deduplicated. This PR changes no DMX semantics
and retains that diagnostic rather than suppressing it.

## Reproduction and regression coverage

```sh
cmake --build native/build --parallel 5
ctest --test-dir native/build --output-on-failure --timeout 120
native/build/peraviz_native_scene_asset_lifetime_tests --archive-benchmark 4500
python3 .github/scripts/run_gdscript_tests.py --godot "$GODOT_BIN" --project . --output /tmp/peraviz-gdscript --timeout 120
python3 tests/integration/benchmark_scene_setup.py --godot "$GODOT_BIN" --workload scenery --instances 10000 --entries 4500 --output /tmp/peraviz-large-setup.json
"$GODOT_BIN" --headless --path . --script tests/integration/benchmark_model_preparation.gd -- --reference
"$GODOT_BIN" --headless --path . --script tests/integration/benchmark_model_preparation.gd
"$GODOT_BIN" --rendering-method forward_plus --resolution 640x360 --path . --script tests/integration/benchmark_render_activation.gd -- --rendered
"$GODOT_BIN" --rendering-method forward_plus --path . --script tests/gdscript/test_import_camera_framing.gd -- --render-camera-probe
"$GODOT_BIN" --rendering-method forward_plus --path . --script tests/gdscript/test_gdtf_fixture_geometry.gd -- --render-import-probe
```

Native tests check 9,003 archive entries, 10k shared references, exact/case/basename
precedence, ambiguity, Unicode, collisions, dependency boundaries, physical byte
counts, leases and source invalidation. The 10k native graph test checks group and
layer transforms, exact object identity, Symdef/direct resources and expected
world translations. Godot tests compare actual nested world transforms and exercise
small/nonuniform/rotated/reflected/singular/non-finite bases; small Euler scales;
shared scenery versus independent materials; dummy removal; cache retirement;
full 10k import/reload with exact hierarchy/resources/patches; cancellation and
failed/minimized rendering acknowledgments. Existing model-detail and optical,
selection, picking, fixture-control and DMX suites remain applicable.

On the owner's Windows/RTX 3070 machine, run the generated workload and optionally
`STG MAHOU.mvr` with tracing, both in a fresh application and as a same-process
reload. Record exact engine/renderer/device, source hash, source-detail/LOD settings,
archive counts, extraction hits/bytes, phase summaries and largest interruption.
After overlay removal check framing, visible viewport geometry, picking/selection,
fixture controls and live/held DMX. Compare the same content/settings on baseline
and candidate; keep the proprietary asset outside the repository and PR artifacts.

## Validation results

- Native Debug build and all 15 CTest cases passed on the updated main baseline.
- All 56 discovered headless GDScript regressions passed, including the 10k
  import/reload, fixture control/selection/picking, optics, shutter and DMX tests.
- Forward+ software rendering passed tiny/large portrait/landscape camera pixel
  checks and real first-render acknowledgment/cancellation/failure tests.
- The imported-geometry pixel probe changed 89,223 viewport pixels after toggling
  published geometry; model-dimension checks exclude runtime shafts under lights.
- Runtime architecture guardrails, file-size checks and `git diff --check` passed.
  Existing soft file-size warnings remain; no new hard-limit failure is introduced.
- Windows/RTX 3070, the proprietary MVR and remote PR CI remain unverified locally.

## Separate persistent-cache follow-up

Simply retaining session directories would violate current ownership and cleanup.
A cross-launch cache needs a separate reviewed storage design:

- Strong content-addressed archive identity (for example SHA-256), extraction
  schema/sanitation version and original entry identity; do not promote the
  current non-cryptographic session fingerprint into a trusted persistent key.
- A completion manifest with expected identity, size/checksum validation and
  source-change invalidation. A file's presence alone is insufficient after a
  crash or concurrent extraction.
- Private staging, atomic publication, process-safe locking, validated paths,
  protection against symlinks/partial writes and clear Windows rename semantics.
- Persistent entry leases integrated with scene/runtime leases, including multiple
  processes and crash recovery. Active scenes must never refer to evicted files.
- A bounded byte/age policy, ownership verification and cleanup that evicts only
  inactive entries, with disk-pressure and corrupt-entry recovery tests.
- Separate mesh-LOD keys including engine/import/conversion/simplification policy,
  source quality and parity, rather than confusing decoded/derived resources with
  extracted archive bytes.

Test same-process reuse, fresh-process reuse, modification at the same source path,
concurrent owners, cancellation, interrupted publication, corruption, eviction and
final lease release. No cross-session cache policy is changed in this PR.
