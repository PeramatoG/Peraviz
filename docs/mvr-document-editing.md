# MVR document editing foundation · phase 1

## Ownership and standards

The scene-owned native `PeravizMvrDocument` owns an immutable disk snapshot of the
imported archive, bounded original XML, lexical element ranges, canonical fixture
identity, inversion values, staged commands and Undo/Redo. It is separate from
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
Commands replace only supported boolean text or insert missing canonical children.
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
unsafe target disables the entire operation with a reason. Other fields remain read-only. Edit > Undo /
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

Linux results: 64/64 headless GDScript regressions and 16/16 native CTests pass.
The full editing test also passes in real Compatibility/llvmpipe UI and with a
forced native asynchronous presentation session. Logs/captures are under the
untracked `work/edit`. Windows/macOS publication paths, Windows DPI, graphical
Forward+ and the owner's large show were not validated here. No large-show
latency or CPU/GPU improvement is claimed.

## Exact next-phase handoff

1. **Patch:** extend the staged typed command and source ranges for canonical
   Addresses, keeping numbered-break identity/order. Validate all selected
   footprints and conflicts before one native routing transaction. Replay held
   mailbox input and preserve UUIDs, other renderer resources and the existing
   Auto Span policy; never silently turn a runtime span into an authored patch.
2. **GDTF Mode:** edit the per-fixture MVR GDTFSpec/GDTFMode reference, after checking
   the embedded definition and selected mode. Keep GDTF definitions immutable.
   Compile affected native fixture plans, preserve inversion/history, and replace
   only geometry that the new mode actually requires. Stage failure leaves the
   prior document/runtime binding intact.
3. **Transform:** add a canonical Matrix command with verified MVR units/bases and
   raw old/new source text. Recompose the affected native subtree, then publish
   presentation transforms. A Godot-only transform setter or gizmo is not a
   document command. Do not generalize the entire XML object graph in advance.

These editors, GDTF archive mutation and interactive gizmos are not implemented
in phase 1. The current source-preserving document, UUID index, command staging,
history and canonical writer are the ownership boundaries to extend.
