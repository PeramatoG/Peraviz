# Peraviz project data ownership

## Purpose

This document records the data ownership rules for Peraviz project files and editing workflows. Runtime architecture lives in `docs/architecture.md`.

## Source data layers

### MVR scene data

MVR owns scene-level fixture data:

- Fixture instances, names, IDs, and fixture numbers when available.
- Patch information.
- Position, rotation, and scene hierarchy.
- References to GDTF files.

The scene-owned native MVR document is authoritative for standard MVR properties.
Phase 1 supports source-preserving `DMXInvertPan` and `DMXInvertTilt` commands,
Undo/Redo and export. It never regenerates an MVR from the partial runtime
SceneModel. The importer reads the same immutable document snapshot used by the
editor. See [MVR editing foundation](mvr-document-editing.md).

### GDTF fixture definition data

GDTF owns fixture-definition data:

- Fixture type and geometry.
- DMX modes, channels, capabilities, wheels, and gobos.
- Physical and visual fixture behavior.

Current workflows treat source GDTF files as read-only. Peraviz may parse and cache GDTF-derived data for runtime use, but it must not silently rewrite fixture definitions.

### Peraviz `.pvz` project data

A `.pvz` archive wraps an MVR scene with Peraviz-specific runtime and visual state. It does not replace MVR or GDTF ownership.

Format details are documented in `docs/pvz-project-format.md`. Project archives may store:

- Visual environment settings.
- Camera state.
- Art-Net / DMX settings.
- UI and application state.
- Visual-only fixture overrides.
- Explicitly distinguished visual-only corrections; standard MVR DMX inversion
  is stored exclusively in the embedded canonical MVR.
- Debug or advanced visualizer options.

Global preferences such as recently opened paths and auto-start settings are user preferences, not project source data, and should remain outside `.pvz` archives.

## Editing ownership rules

Editing features must first identify the owning data layer:

- Patch, position, rotation, fixture name, and fixture number belong to MVR.
- Fixture mode definitions, geometry, wheels, gobos, and capabilities belong to GDTF.
  A fixture instance's selected GDTFSpec/GDTFMode reference belongs to MVR.
- Visual environment, camera, Art-Net settings, visual-only overrides, and UI state belong to Peraviz project data.
- Live DMX values are runtime state and should not be saved as fixture definitions.

If the owning source layer is not writable yet, the feature should remain read-only or save only an explicit Peraviz override that does not pretend to modify the source file.

## Runtime routing overrides

The [DMX Auto Span policy](dmx-auto-span.md) belongs to Peraviz project metadata:
`auto_span_policy` in `dmx_settings.json`, with `off`, default `auto_safe`, or
`auto_overlap`. It derives effective native byte routing from unchanged canonical
MVR patches and resolved GDTF breaks. It is not a second patch model. Occupancy,
effective addresses and live/held DMX are never persisted. Saved policy is restored
before native setup; ordinary MVR import and Reset use `auto_safe`.

## Canonical document persistence

`scene.mvr` in PVZ is the current native document serialization, including all
committed standard MVR edits. Save PVZ and File > Export MVR consume the same
validated archive per revision. An unmodified accepted document copies original
MVR bytes; edited XML patches preserve all unrelated XML bytes and all resource
contents. Reopening a project imports its embedded edited MVR. `fixture_overrides.json`
remains distinct visual-only data and cannot impersonate MVR inversion flags.
Only successful PVZ publication advances the document save point; export, camera,
rendering and user-preference changes do not clear pending document edits.

## Authored Patch commands

The native document's typed patch states extend the existing inversion history.
The loader stages parser-validated routing from those canonical entries using
cached selected modes, then the exclusive presentation boundary installs numeric
plans before document publication. Same-topology edits retain renderer resources,
held DMX and temporal state; unsupported additions/retirements fail atomically.
The SceneModel and provider remain projections, not parallel patch authorities.
Auto Span stays a runtime policy in project DMX settings, never an MVR mutation.
See [MVR document editing](mvr-document-editing.md) for source preservation,
mixed selections and supported insert/remove operations.

### Native fixture mode transaction

The loader caches the mode catalog for the leased GDTF revision. Apply stages
the canonical command, validates authored addresses, compiles the prospective
runtime and builds a renderer manifest. Existing geometry is the default.
Changing a root prepares a fixture-local subtree with the shared model cache.

The presentation boundary reclaims the worker before changing dense bindings.
Compatible physical outputs, lens resources and unaffected group resources are
reused. Dense indices are regenerated from canonical target IDs. The new core
inherits the runtime epoch and compatible unrelated temporal state, then
evaluates actual held universe frames. The changed fixture releases prior
authority and resets obsolete effects. A rejected installation restores the
previous target bindings and held presentation values. Publication commits
the MVR command and updates the SceneModel projection through the native loader.
The patch-only transaction still handles address changes.

A future Transform editor can use the canonical UUID and document history to
stage its Matrix command. Its presentation transaction should resolve the
existing fixture root by UUID and apply the transform there.
