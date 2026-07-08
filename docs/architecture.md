# Peraviz architecture

## Purpose

This is the short technical source of truth for the active Peraviz runtime. It separates what is implemented today from the target responsibility split and the known transitional bridge that still exists on `main`.

Peraviz is a real-time lighting visualizer. Native C++ should own protocol ingestion, DMX/GDTF-derived state resolution, dirty-state generation, and render-ready frame preparation. Godot should own presentation, renderer resources, interaction, and applying prepared render sections to cached scene objects.

## Current implementation

The active runtime uses a native sectioned visual frame. `SectionedVisualFrame` carries section descriptors plus separate integer and float payload arrays. The Godot bridge exposes the latest completed frame as a `Dictionary` with `descriptors`, `integers`, `floats`, and `stats` arrays for the section applier.

Current native runtime responsibilities include:

- Art-Net packet reception through the native receiver.
- Latest-frame coalescing so Godot consumes only the newest visual frame.
- Universe filtering and relevant-channel hashing before fixture updates are emitted.
- Fixture binding lookup from the currently registered setup bridge.
- Dirty-state detection for render domains.
- Render-value cooking for transform, intensity, color, optics, wheel selection, wheel motion, and temporal output.
- Section assembly using descriptors and typed payloads.
- Visual frame schema validation helpers and tests.

Current Godot runtime responsibilities include:

- Building runtime setup data from loaded scene and fixture information.
- Registering fixture bindings and render parameters with the native visual runtime.
- Consuming the native sectioned visual frame.
- Applying domain-specific sections for transforms, intensity, color, optics, wheel selection, wheel motion, and temporal output.
- Maintaining renderer-facing nodes, materials, gobos, beams, and UI state.

Current GDTF work includes a preliminary `CompiledGdtfFixtureType` model and runtime schema foundation. This model is not yet the production source for the live visual runtime.

## Current live data flow

```text
Art-Net / DMX input
  -> native receiver and latest universe cache
  -> registered fixture/channel bindings
  -> relevant-channel filtering
  -> dirty render-state cooking
  -> SectionedVisualFrame descriptors + integer payloads + float payloads
  -> Godot sectioned frame applier
  -> cached renderer nodes, materials, lights, beams, and gobo resources
```

The live frame format is intentionally sectioned rather than one universal fixed row. Integer identifiers, flags, masks, offsets, and slot IDs stay in integer payloads. Physical/render scalars such as positions, rotations, intensities, colors, optics, speeds, and phase values stay in float payloads.

## Known transitional bridge

The production path still has a setup bridge that will be removed in a later runtime branch. Documentation and tests must not pretend it is already gone.

Current production setup still uses:

- `set_fixture_bindings(...)` on the native visual runtime Godot wrapper.
- `FixtureChannelBinding` as the native binding record.
- Magic numeric `channel_type` values created by current Godot setup code.
- `set_fixture_render_params(...)` for fixture render parameters.
- Godot `Array` and `Dictionary` setup data.
- `scripts/dmx_fixture_runtime.gd` to build and register fixture bindings.
- Transitional Godot-side gobo metadata and compatibility paths.

Guardrails may prevent the removed fixed-row visual frame from returning, but they must not fail only because these transitional setup APIs still exist.

## Target responsibility split

### Native C++

Native C++ is the owner for expensive or high-frequency runtime work:

- Art-Net, sACN, and DMX packet handling.
- Universe filtering and patch lookup.
- GDTF and MVR-derived fixture model data needed by the runtime.
- Attribute resolution, physical-value calculation, interpolation, smoothing, and relation handling as support grows.
- Dirty-state generation and frame coalescing.
- Render-ready values for transforms, linear color, intensity, beam and optical parameters, wheel state, shutter/strobe, prism, and temporal output.
- Versioned, schema-driven, batch-oriented data transfer.

### Godot

Godot is the client rendering layer:

- Scene presentation, cameras, UI, selection, and interaction.
- Renderer-facing meshes, materials, lights, textures, shaders, beams, atmosphere, and post-processing.
- Structural installation of cached render targets.
- Application of prepared live sections from C++.

Godot should not parse live DMX, evaluate GDTF channel functions, own protocol receivers, or rebuild per-fixture dictionaries during playback once the target architecture is complete.

## Runtime invariants to keep now

- The sectioned frame path remains active.
- Descriptor, integer payload, and float payload storage remain separate.
- The obsolete native fixed visual-frame buffer path stays deleted.
- The old Godot universe decoder is not registered as the live playback path.
- Section appliers do not reconstruct the removed universal fixed row.
- Native receiving or processing threads do not mutate Godot scene nodes directly.

## Next architectural step

The next runtime branch should connect parser-owned compiled GDTF fixture programs to the production visual runtime setup path. That work should replace the transitional Godot-built binding bridge rather than adding a second active setup pipeline.

The change is not complete until the production path no longer depends on Godot-built channel binding dictionaries, magic `channel_type` values, or Godot-side GDTF/gobo semantic compatibility caches.

## Supporting documents

- `docs/adr-gdtf-parser-ownership.md` records the parser ownership decision shared with Perastage.
- `docs/gdtf-support-matrix.md` summarizes currently verified GDTF semantic coverage.
- `docs/pvz-project-format.md` documents the `.pvz` archive format.
- `docs/godot_performance_guidelines.md` contains renderer and scene-tree performance guidance.
- `docs/NATIVE_BUILD.md` documents native build steps.
- `docs/MVR_XCHANGE.md` documents MVR-xchange behavior.
