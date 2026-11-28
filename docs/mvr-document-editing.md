# MVR document editing foundation and canonical Patch editor

## Ownership and standards

The scene-owned native `PeravizMvrDocument` owns an immutable disk snapshot of the
imported archive, bounded original XML, lexical element ranges, canonical fixture
identity, inversion values, ordered authored patch entries, staged commands and Undo/Redo. It is separate from
`SceneModel`, Godot nodes and the live compiled runtime. The importer reads the
same snapshot; another application's changes to the external source cannot
silently change the editor's authority during a long import.

The [MVR 1.6 Fixture definition](https://gdtf-share.com/help/developers/mvr_1_6/file-format-definition/index.html#node-definition-fixture)
assigns `DMXInvertPan` / `DMXInvertTilt` to optional Fixture children. The
[Bool/UUID definitions](https://gdtf-share.com/help/developers/mvr_1_6/generic-value-types/)
require `true`/`false` and canonical non-nil UUIDs. Absence requests no inversion;
it is retained as absence rather than rewritten as explicit false. Invalid and
duplicate declarations retain diagnostics and are excluded from live fixture
compilation. No GDTF file is rewritten; the former ChannelFunction `DMXInvert`
was [removed in GDTF 1.0](https://gdtf-share.com/help/developers/gdtf_1_2/changes/version-1.0/index.html).

`AppShell.selection` remains the selection authority. Editing requires an indexed,
unique canonical UUID and a published fixture node. Names, row indexes, generated
nodes and GDTF geometry paths are never document edit identities. Source UUID
spelling stays intact; UUID ambiguity checks are case-insensitive. Replacing a
scene retires the prior document, staged commands, history and serialization
cache. File-open and application-close guards protect pending edits.

## Source-preserving mutation and bounds

TinyXML2 validates the XML and supplies decoded fixture identities and metadata.
A lexical pass cross-checks element preorder and records exact source ranges.
Commands replace supported boolean/address text, insert missing canonical children,
or explicitly remove selected assignments. Existing Address attributes and optional
break absence are retained.
All unrelated XML bytes, child order, Matrix text, addresses/break order, unknown
attributes/elements, namespace extensions, references and provider data survive.
No runtime SceneModel-to-MVR serializer exists.

The archive remains on disk. XML is limited to 32 MiB, 500,000 elements and 256
lexical nesting levels. ZIP central-directory validation permits up to 1,000,000
entries. History is limited to 4,096 commands / 200,000 retained changes. These are
explicit rejection bounds, not silent truncation. Commands check projected XML size
before the runtime transaction using indexed field lengths; they do not serialize
the document on each checkbox action. Binary resources are never
unpacked into the document; resource verification uses fixed 64 KiB streams.
The existing Godot PVZ packer needs one complete MVR byte buffer, released before
reading/verifying the embedded entry; editing itself retains no binary archive
buffers in Godot.

Safe canonical editing currently requires unprefixed MVR 1.0–1.6 XML, one Scene /
Layers collection and UTF-8 XML 1.0 characters. Unsupported versions/default
namespaces, malformed XML/entities/encoding, DTDs and excessive complexity reject
editing/canonical export with an actionable diagnostic. A structurally safe ZIP
that only the legacy viewer accepts can still be embedded unchanged in PVZ from
the same native snapshot; this opaque compatibility copy grants no editing or
standalone canonical-export permission. The importer still reads that snapshot.
Foreign-default-namespace,
self-closing or ambiguously identified fixtures and inversion fields containing
markup remain unavailable for mutation. Other valid fixtures can be edited when
their own identities and fields are safe. Archive traversal/absolute/alias paths,
case collisions, encryption and compression other than Store/Deflate reject the
canonical document. Legacy viewer import remains separate; it does not grant a
legacy/synthetic identity permission to edit or silently normalize it.

## Commands, consistency and runtime integration

`MvrDocument::prepare()` validates the entire selection before exposing a staged
command. Each change stores old/new effective values **and XML presence**. Undo
and Redo stage the inverse/original operation through the same transaction.
Semantic no-ops retain absent fields. A successful PVZ save advances a separate
save point; export and presentation/preferences do not. Dirty checks in UI/menu
refreshes are cached constant-size reads, not XML scans.

`mvr_editing_service.gd` coordinates the staged command with native presentation
ownership. `PeravizPresentationState::set_fixture_inversions()` reclaims any
in-flight native session, validates all runtime fixture IDs, changes fixture-local
mechanical flags and invalidates affected held input contexts. This is an explicit
control boundary; the next presentation resumes from held native bytes. It does
not rebuild MVR geometry, reinstall materials, change selection, reset the camera
or reconstruct the entire runtime. A rejected runtime boundary cancels the staged
document command. Commit then synchronizes SceneModel/prepared metadata and UI.
Unbound canonical fixtures retain their document settings for future binding.

Native evaluation assembles ordered 1–4-byte DMX values first. A Pan/Tilt consumer
uses `maximum - raw` before function range selection and normalized/physical
mapping. Descending physical ranges remain authored mappings. ModeMaster input
bytes and unrelated Color/Dimmer/Zoom consumers keep their original source
results. Shared raw source caches and pure serial/parallel source evaluation are
unchanged. Fixture-local flags apply to every qualified mechanical target;
multiple Pan/Tilt axes emit qualified component rows using the existing protocol.
The standard one-Pan/one-Tilt path retains its established row format. Held-domain
replay also retains multiple-axis identities.

Compiled setup contract 12 stores effective Pan/Tilt flags in the existing
reserved fixture integer. Versions 1–11 decode with both flags false; source XML
presence remains document metadata. Unknown flag bits fail decoding. No Art-Net
routing, packet mutation, GDTF rewrite or GDScript Pan/Tilt evaluator is added.

## UI and the single serialization contract

The Inspector offers one OFF/ON toggle each for Invert Pan / Invert Tilt.
Multiple-selection differences show **Mixed → ON**, explicitly enabling the
complete selection on the next click; subsequent clicks toggle normally. An
unsafe target disables the entire operation with a reason. Patch has its own compact editor below; other fields remain read-only. Edit > Undo /
Redo and Ctrl+Z, Ctrl+Y / Ctrl+Shift+Z respect text-editor focus. `*` in the project
title marks unsaved document changes. Canceling discard or failing a write keeps
the current editing session.

`canonical_archive()` is the **only MVR writer**. It materializes one verified
archive per document revision. Unmodified state returns the original snapshot;
edited state copies the ZIP on disk and changes only scene XML. XML-entry mtime
and compression method are retained. Every non-XML entry's name/order and
uncompressed bytes are compared against the snapshot before publishing the
canonical serialization.

- Save PVZ embeds that exact canonical archive as `scene.mvr`, alongside existing
  visual/DMX/Auto Span settings and supported optional project metadata.
- File > Export MVR copies that same canonical archive, including edits not yet
  saved to PVZ, without adding Peraviz JSON or requiring a prior project save.
- Without intervening edits, an export equals embedded `scene.mvr` byte-for-byte;
  the regression crosses a ZIP timestamp quantum before comparing them.
- Open PVZ imports its embedded edited MVR. Standard inversion never comes from
  `fixture_overrides.json`; distinct visual-only override data is retained.

Standalone MVR export requires a new filename, rejects source/existing output
replacement, stages beside the destination, validates and atomically publishes
without replacement. Unsupported filesystem publication fails with a diagnostic.
PVZ saving stages, verifies the canonical entry hash and safely renames the
project; a failed write leaves the previous project and editing state intact.
No-op accepted MVR exports are byte-identical to the original archive. Edited
archives guarantee original binary **contents**, not identical whole-ZIP bytes.
The XML/ZIP validator is deliberately narrower than a complete MVR schema audit;
it does not repair pre-existing missing resources or unsupported source semantics.

## Validation and tested scope

Public synthetic fixtures contain moving heads, truss, groups, UTF-8 metadata /
resource paths, unknown namespace data, repeated resources and numbered breaks.
Native tests cover absence, explicit booleans, malformed/duplicate fields, exact
no-op bytes, atomic rejection, nested identities, source snapshot isolation,
resource verification, Undo/Redo and failed/unsafe exports. Runtime tests cover
8/16/24/32-bit endpoints/midpoints, noncontiguous cross-universe sources, descending
physical ranges, shared-source/overlapping fixtures, independent Tilt, range /
ModeMaster activation, multiple axes and serial/forced-parallel execution.

The Godot integration exercises real local ArtDmx reception, Inspector edits,
held-state changes without another packet, multi-selection, shortcuts/focus,
dirty/save/failure behavior, PVZ reopen, unsaved MVR export, standalone reopen,
and exact embedded/exported archive equality. It checks node, source mesh/material,
camera and runtime-generation stability. The numbered-break test separately
covers a noncontiguous 16-bit Pan on break 1 and independent Tilt on break 2.
Python ZIP/ElementTree independently verifies source XML outside inversion fields,
hierarchy/UUID identity and SHA-256 for every binary resource. An additional
read-only check with **PyMVR 1.0.7** recognizes the exported MVR 1.6, four canonical
fixtures and the expected inversion values. PyMVR is an optional local validator,
not an application or CI dependency.

Reproducible commands (Godot 4.7.1; wrappers select the pinned executable and
isolated user preferences):

```bash
PATH=/workspace/.peraviz-tools/python/bin:$PATH cmake --build native/build --parallel 5
/workspace/.peraviz-tools/python/bin/ctest --test-dir native/build --output-on-failure --timeout 120
work/godot --headless --audio-driver Dummy --rendering-method gl_compatibility \
  --path . --editor --import --quit
python3 .github/scripts/run_gdscript_tests.py \
  --godot /workspace/Peraviz/work/godot-tests --project /workspace/Peraviz \
  --output /workspace/Peraviz/work/edit/tests --timeout 90
PERAVIZ_NATIVE_EVALUATION=parallel work/godot-tests --headless \
  --audio-driver Dummy --rendering-method gl_compatibility --path . \
  --script tests/gdscript/test_mvr_document_editing.gd
DISPLAY=:17 work/godot --audio-driver Dummy --rendering-method gl_compatibility \
  --path . --script tests/gdscript/test_mvr_document_editing.gd
bash tests/check_runtime_architecture.sh
bash tests/check_no_large_files.sh
git diff --check
```

Foundation validation (PR #139): 64/64 headless GDScript regressions and 16/16 native CTests passed.
The full editing test also passes in real Compatibility/llvmpipe UI and with a
forced native asynchronous presentation session. Logs/captures are under the
untracked `work/edit`. Windows/macOS publication paths, Windows DPI, graphical
Forward+ and the owner's large show were not validated here. No large-show
latency or CPU/GPU improvement is claimed.

## Canonical Patch editing (editor PR2)

The [MVR 1.6 Addresses definition](https://gdtf-share.com/help/developers/mvr_1_6/file-format-definition/index.html#node-definition-addresses)
permits ordered Address and Network siblings. An Address has a unique integer
`break` (default 0), with either a positive absolute value or `Universe.Address`.
Universes are 1-based and slots are 1–512. GDTF break n maps to MVR break n−1;
a break identifier never means a universe offset. Noncontiguous breaks are retained.

The document indexes each original entry's range, raw text, format and optional
break presence. `Change::Kind::Patch` carries before/after ordered states in the
same staged history as inversion. Set modifies only existing value text; insert
appends a new explicit break to the existing container (or expands/creates one);
remove deletes only the explicitly selected entry. Network, unknown siblings and
attributes, other assignments, UUIDs, hierarchy, inversion and binary resources
remain untouched. Undo restores exact old source spelling, whitespace and
container/attribute absence. A semantic set no-op retains its original text.

`mvr_document_patch.cpp` owns these native semantics; no GDScript XML writer,
private PVZ patch JSON or occupancy authority is added. Editing is bounded to
4,096 entries per fixture / 256 raw text bytes per entry. History counts retained
patch entries toward its existing 200,000-change bound. Oversized/ambiguous fields
remain preserved but unavailable for patch mutation. Legacy scalar patch fields
are not silently promoted into canonical Addresses. Empty canonical Addresses
are valid unpatched metadata and never fall back to legacy scalar addresses.

### Inspector and validation

Select one canonical fixture to edit its existing Universe/Address rows under
**Patch**, with a footprint span when known. Technical break identities stay
internal; multiple assignments appear as additional rows. Each field commits
only on **Enter**, through the same validated native document/runtime command.
Leaving a field without Enter restores its saved value; invalid or failed
submissions also restore it and show an error. Other fields' unconfirmed drafts
never enter the command. Add/remove assignment controls are not exposed in the
ordinary Inspector; the native typed command capabilities remain available for
future explicit technical workflows. Multiple selection stays read-only for
patching, while Pan/Tilt multi-selection remains editable. Text fields retain
their normal focus/shortcut ownership.

The document checks identity, structure, unique breaks, 1–512 slots and a 1–32768
universe editing bound. The loader validates the actual native Art-Net range
(0–32767 after the configured offset), selected cached GDTF mode, required breaks,
ordered byte routing and the currently chosen Auto Span policy. Occupancy is
advisory: authored footprint overlaps warn and remain legal. Unknown GDTF
footprints are reported as unknown rather than guessed. A crossing footprint is
reported separately from its effective Auto Span continuation.

### Exclusive routing transaction and supported boundary

`PeravizLoader::stage_document_patch()` temporarily compiles the proposed authored
metadata against cached selected GDTF types, restoring the live model before it
returns. It validates the packed semantic topology with only physical byte routes
and fixture start addresses normalized. No geometry import, source archive parse,
GDTF rewrite or Godot resource installation occurs.

The native presentation owner reclaims its async session before
`commit_document_patch()` replaces numeric routing plans. Existing fixture,
component, target and source identities and the presentation generation remain
stable. Mechanical/property/color state, gobo selection/rotation, shutter
authorities and the runtime clock survive. Held full frames from existing native
contexts are submitted to the new plans once. The transport's compiled interests
are refreshed at the next immediate poll, retiring stale subscriptions. Newly
unreceived universes wait for input; no missing byte value is fabricated. Frames
not retained by the existing subscribed transport are not promised as available.

A successful runtime transaction precedes document/history publication and the
provider refresh. Failures cancel the staged command without advancing history,
changing XML or installing contradictory metadata. The camera, scene selection,
geometry, lights and material identities are unchanged. Numeric plans are
recompiled for the scene at this explicit command boundary, not on every packet;
this is not a per-fixture compiler or a new runtime architecture.

The conservative production boundary is **same installed control topology**.
Existing required and optional break values can change; unused optional breaks
can be explicitly inserted/removed. Missing required assignments, fully unpatched
fixtures without an installed renderer plan, last-assignment/required-break
removal, or an Auto Span change that adds/removes supported controls reject the
operation with a clear reason. The native document itself preserves and tests
valid unpatched/partially patched states and source-preserving insert/remove;
the UI does not claim to create/retire renderer domains in this PR. Completing an
unbound fixture requires correcting the source and reopening it. This restriction
protects unrelated live/temporal state rather than silently performing a full
renderer rebuild.

Auto Span `off`, `auto_safe` and `auto_overlap` remain runtime policies in
`dmx_settings.json`. The Inspector and exported MVR always show/store authored
Address entries; inferred continuation universes are never inserted. Existing
legacy compatibility remains separate from canonical document writing.

### Persistence and regression coverage

The canonical archive cache/writer is unchanged: Save PVZ embeds the current
edited MVR as `scene.mvr`, and direct Export MVR copies exactly those bytes,
including edits not yet saved to PVZ. Reopen reads embedded canonical patch and
inversion together. No-op exports retain original bytes; unrelated XML and all
binary resources remain preserved, with staged validation and source protection.

Native tests cover implicit/explicit zero, absolute/dotted values, noncontiguous
breaks, Network/extensions, unpatched containers, insert/remove, mixed inversion /
patch history, exact Undo, unsafe rejection and full-width 8/16/24/32-bit held
routing with independent overlapping consumers and serial/parallel evaluation.
Godot tests exercise a moderate 32-fixture scene with real ArtDmx, no-packet
held replay, stopped/restarted input, multi-break 16-bit coarse/fine routing,
Inspector validation/mixed read-only state, geometry/material/camera/selection
stability, failure rollback, PVZ and MVR reopen and byte equality. Independent
Python ZIP/XML/SHA-256 checks retain Network, hierarchy, UUIDs and every binary
resource. The PR2 suite passes 66/66 GDScript regressions and 17/17 native CTests, including
the existing 10k-scene harness. Forced native async presentation is checked
separately. The 32-fixture workflow also passes graphical Compatibility/llvmpipe.
Windows and graphical Forward+ validation remain pending; no owner's-show timing is claimed.

## Exact next-phase handoff

The native mode preparation path enumerates exact authored GDTF names and
prepares a candidate against existing patch addresses and Auto Span policy.
The staged document operation retains the original GDTFMode source span, XML
text spelling and element presence for Undo. When the element is absent, its
insertion point is directly after a unique canonical GDTFSpec. The mode
operation shares the patch and inversion history and canonical archive writer.

1. **GDTF Mode:** connect the staged mode command to an exclusive native
   renderer transaction. Install and retire renderer domains and reuse
   compatible fixture resources before publishing the document command. Resolve
   required breaks against the authored patch and preserve inversion, history,
   held input and the Auto Span policy.
   Never replace GDTF definitions or silently create missing patch assignments.
2. **Transform:** add a Matrix command with verified MVR units/bases and raw
   before/after source text. Recompose the affected native subtree and publish
   presentation transforms; a Godot-only setter is not an MVR document edit.

Neither mode selection nor transform gizmos are implemented here. The native
source ranges, typed history, canonical writer and explicit runtime transaction
are the boundaries to extend; no second project patch model is needed.
