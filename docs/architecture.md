# Peraviz architecture

## Purpose

This is the short technical source of truth for the active Peraviz runtime. Peraviz is a real-time lighting visualizer: native C++ owns DMX/GDTF-derived runtime state resolution, dirty-state generation, and render-ready frame preparation, while Godot owns presentation, renderer resources, interaction, and applying prepared sections to cached scene objects.

## Current implementation

The active live output remains the native sectioned visual frame. `SectionedVisualFrame` carries section descriptors plus separate integer and float payload arrays. The Godot bridge exposes the latest completed frame as a `Dictionary` with `descriptors`, `integers`, `floats`, and schema data for the section applier.

The production setup authority for the visual runtime is now a native compiled scene contract produced by the loader-owned native GDTF/MVR compiler. It installs stable fixture, component, render-target, patch, DMX source-program, property-contributor, and renderer-manifest records before live frames are submitted. The current Dimmer/Pan/Tilt slice is native-first, with application verification still required before broader production claims.

Current native runtime responsibilities include:

- Latest-frame coalescing so Godot consumes only the newest visual frame.
- Universe filtering and relevant-slot hashing before fixture updates are emitted.
- Native compiled scene generation and installation for fixture instances, stable IDs, DMX byte sources, and property contributors.
- Multi-byte DMX value assembly from ordered source byte records, including non-adjacent coarse/fine addresses.
- Dirty-state detection for transform and intensity output in the verified Dimmer/Pan/Tilt slice.
- Render-value cooking for sectioned visual output.
- Section assembly using descriptors and typed payloads.
- Visual frame schema validation helpers and behavior tests.

Current Godot runtime responsibilities include:

- Orchestrating runtime setup and renderer registration.
- Consuming the native sectioned visual frame.
- Applying domain-specific sections for prepared runtime output.
- Maintaining renderer-facing nodes, materials, beams, and UI state.

## Current live data flow

```text
MVR fixture patch
  -> parser-owned selected GDTF DMX mode model
  -> scoped DMXChannel records under the selected mode, including standard DMXChannels wrappers and harmless vendor wrappers
  -> LogicalChannel / ChannelFunction records with inferred or explicit full-resolution DMX ranges
  -> CompiledGdtfFixtureType
  -> native compiled runtime scene
  -> native fixture instances, patch, source programs, and contributors
  -> submitted universe snapshots
  -> relevant-slot filtering and native DMX evaluation
  -> dirty SectionedVisualFrame descriptors + integer payloads + float payloads
  -> Godot sectioned frame applier
  -> exact cached native target IDs resolved from shared canonical GDTF geometry-instance keys
  -> cached renderer nodes, materials, lights, and beams
```

The live frame format is intentionally sectioned rather than one universal fixed row. Integer identifiers, flags, masks, offsets, and raw DMX source metadata stay in integer-oriented structures and payloads. Physical/render scalars such as pan, tilt, and intensity values stay in float payloads after compiled native evaluation.

## Removed visual-runtime setup bridge

The native visual runtime no longer exposes the old `set_fixture_bindings(Array<Dictionary>)` or `set_fixture_render_params(Dictionary)` setup methods. The runtime core no longer uses `FixtureChannelBinding`, magic numeric `channel_type` mappings, or a legacy semantic translation table to install production visual programs.

Godot registers the native renderer manifest once during structural setup, resolves native component/render-target IDs to cached scene targets by canonical GDTF geometry keys, and applies live Transform and Intensity rows through those IDs. Compiled-scene used universes, not legacy flattened bindings, own Dimmer/Pan/Tilt frame submission to the native runtime. The remaining GDScript inspection and gobo compatibility code is not an authoritative Dimmer/Pan/Tilt runtime path. Domains outside the verified Dimmer/Pan/Tilt slice must be wired through the compiled native contract before being described as production-supported.

## Verified GDTF/runtime coverage

- Dimmer: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and render-target ownership for native evaluation.
- Pan: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and component ownership for native evaluation.
- Tilt: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and component ownership for native evaluation.
- The generic source reader accepts one to four ordered bytes, so 8-bit, 16-bit, 24-bit, and 32-bit source layouts are supported by the runtime model.
- One resolved component property can contain multiple ChannelFunction ranges; native evaluation selects the active range from the assembled raw DMX value.
- Transform section rows use integer payloads `[fixture_id, pan_component_id, tilt_component_id, changed_mask]` and float payloads `[pan_degrees, tilt_degrees]`.
- Transform section Pan/Tilt values are physical degrees, not normalized values.
- The technical DMX monitor is on-demand: hidden windows perform no grid refresh work, and visible windows copy the selected universe only when metadata changes.

## Known unsupported GDTF semantics

ModeMaster, Relations, virtual attributes, complex ChannelSet selection, CMY/RGB/color wheels/CTO, gobos, prisms, strobe curves, repeated emitters, and repeated wheel families are not claimed as production-supported by this slice unless a later test connects them through the compiled runtime path end to end. Unsupported or incomplete compiled inputs should produce diagnostics instead of silent semantic guessing.

## Runtime invariants

- Structural setup and live DMX submission remain separate contracts.
- The sectioned frame path remains active.
- Descriptor, integer payload, and float payload storage remain separate.
- The obsolete native fixed visual-frame buffer path stays deleted.
- Section appliers do not reconstruct the removed universal fixed row.
- Native receiving or processing threads do not mutate Godot scene nodes directly.

## Next architectural step

The next recommended vertical slice is color intensity/color-mixing through parser-owned compiled GDTF programs, with behavior tests proving selected ChannelFunction ranges and renderer-facing color sections without restoring Godot-built semantic dictionaries.

## Supporting documents

- `docs/adr-gdtf-parser-ownership.md` records the parser ownership decision shared with Perastage.
- `docs/gdtf-support-matrix.md` summarizes currently verified GDTF semantic coverage.
- `docs/pvz-project-format.md` documents the `.pvz` archive format.
- `docs/godot_performance_guidelines.md` contains renderer and scene-tree performance guidance.
- `docs/NATIVE_BUILD.md` documents native build steps.
- `docs/MVR_XCHANGE.md` documents MVR-xchange behavior.
