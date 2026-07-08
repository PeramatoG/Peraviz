# Peraviz repository structure and module ownership

This document describes the real repository layout, the intended ownership of each area, and the architectural boundaries that contributors must preserve.

It is not a speculative future tree. Paths listed as current must exist in the repository. When files or responsibilities move, update this document in the same change.

`AGENTS.md` is the highest repository-level authority for architecture and refactoring rules. This document maps those rules to concrete paths.

## Structure status labels

The following labels are used throughout this document:

- **Active**: used by the current production path.
- **Target**: required ownership for the final architecture.
- **Migration-sensitive**: currently active or referenced, but must not receive new responsibilities that belong to the target architecture.
- **Legacy**: superseded implementation that must not be extended and should be removed from the active build during an approved architectural replacement.
- **Generated**: build, import, editor, or cache output. It is not an architectural source location.

A path may be active and migration-sensitive at the same time.

## Current root-level structure

The Godot project lives at the repository root. There is no `godot/` source directory.

```text
Peraviz/
|-- AGENTS.md
|-- CONTRIBUTING.md
|-- README.md
|-- README_gobos.md
|-- VERSION
|-- project.godot
|-- peraviz.gdextension
|-- test.tscn
|-- test.gd
|-- icon.svg
|-- scripts/
|-- native/
|-- docs/
|-- tests/
|-- bin/
`-- .godot/
```

### Root ownership

- `project.godot`
  - **Active**
  - Owns Godot project configuration and autoload or project-level registration.
  - Must not become a storage location for runtime semantics.

- `peraviz.gdextension`
  - **Active**
  - Declares the native GDExtension libraries and entry point.
  - Must reference only supported native build outputs.

- `test.tscn` and `test.gd`
  - **Active**
  - Currently act as the main project scene and entry script unless replaced by a dedicated scene structure.
  - Scene orchestration is allowed here.
  - GDTF parsing, DMX interpretation, physical-value resolution, and per-frame fixture semantics are not allowed here.

- `scripts/`
  - **Active**
  - Contains the Godot client, UI, scene orchestration, renderer adapters, and migration-sensitive runtime scripts.
  - Detailed ownership is defined below.

- `native/`
  - **Active**
  - Contains the C++ GDExtension, native tests, build configuration, protocol processing, parsing, compilation, and runtime data preparation.
  - Detailed ownership is defined below.

- `docs/`
  - **Active**
  - Contains architectural, protocol, performance, build, support, and migration documentation.

- `tests/`
  - **Active**
  - Contains repository-level architecture and quality checks.
  - Checks must inspect the real paths in this document.

- `bin/`
  - **Generated**
  - Contains native libraries or other runtime build output loaded by Godot.
  - It must not contain hand-maintained source logic.

- `.godot/`
  - **Generated**
  - Contains Godot editor and import cache data.
  - It is not a source module and must never be used as an architectural dependency.

## Native project structure

```text
native/
|-- CMakeLists.txt
|-- CMakePresets.json
|-- CMakeSettings.json
|-- vcpkg.json
|-- cmake/
|-- src/
`-- tests/
```

### Native build ownership

- `native/CMakeLists.txt`
  - Owns explicit native source registration, dependencies, targets, and GDExtension build configuration.
  - Project sources should be listed explicitly.
  - Removed legacy files must also be removed from the build.

- `native/cmake/`
  - Owns focused CMake helpers, platform configuration, and packaging support.
  - It must not contain runtime application logic.

- `native/tests/`
  - Owns C++ unit, integration, contract, and vertical runtime tests.
  - Runtime architecture tests must exercise the intended production path rather than only manually assembled legacy bindings.

## Native source ownership

The native source tree currently contains both focused subdirectories and older root-level source files.

```text
native/src/
|-- archive/
|-- dmx/
|-- gdtf_runtime/
|-- mvrxchange/
|-- runtime/
|-- table_model/
|-- asset_cache.*
|-- coordinate_mapper.*
|-- entry.cpp
|-- gdtf_scene_builder.*
|-- gobo_vectorizer.*
|-- mesh_3ds_loader.*
|-- mvr_scene_loader.*
|-- peraviz_debug_runtime.*
|-- peraviz_dmx_receiver.*
|-- peraviz_loader.*
|-- peraviz_mvr_xchange_client.*
|-- register_types.*
|-- scene_model.h
`-- other focused support files
```

This is a responsibility map, not an exhaustive filename list.

### `native/src/archive/`

- **Active**
- Owns archive access and extraction for ZIP-based MVR and GDTF content.
- Must not interpret GDTF semantics.
- Must return deterministic archive and file data to parser-owned code.

### `native/src/dmx/`

- **Active**
- Owns native DMX frame decoding, universe-level processing, relevant-address filtering, and related low-level data handling.
- May contain protocol-neutral DMX utilities.
- Must not contain Godot scene or renderer logic.
- Must not map magic channel-type numbers to fixture behavior as the final architecture.

### `native/src/gdtf_runtime/`

- **Target and partially active**
- Owns the serialization-neutral GDTF semantic and compiled-runtime foundation.
- This area must own or receive the output of:
  - GDTF parsing and validation.
  - Canonical attribute identities.
  - Geometry and geometry-reference resolution.
  - DMX modes.
  - Logical channels.
  - Channel functions and channel sets.
  - Physical ranges.
  - ModeMaster and relation data.
  - Wheels, wheel slots, emitters, filters, color spaces, gamuts, profiles, shapers, media, lasers, and other repeated families.
  - Stable component and semantic identities.
  - Diagnostics for invalid, unknown, custom, approximated, or unsupported data.
- Repeated families must use IDs and collections.
- It must not depend on Godot renderer types, Nodes, RIDs, editor commands, or Perastage-specific editing systems.
- Its semantic contract must remain compatible with Perastage.

### `native/src/runtime/`

- **Target and partially active**
- Owns the live native runtime after structural GDTF and scene compilation.
- This area owns:
  - Compiled DMX programs.
  - Fixture-instance runtime registration.
  - Universe interest maps.
  - Physical-state resolution.
  - Interpolation and smoothing.
  - ModeMaster and relation evaluation when implemented.
  - Dirty-state generation.
  - Render-ready state preparation.
  - Versioned section schemas.
  - Typed packed frame or delta assembly.
  - Native-to-Godot runtime bridge objects.

The final runtime must consume parser-owned and compiler-owned data directly.

The final runtime must not depend on:

- Godot-created `Array<Dictionary>` fixture bindings.
- Magic channel-type numbers.
- A fixed list of one pan, one tilt, one gobo, one prism, or one emitter per fixture.
- Per-fixture universal state Dictionaries.
- Duplicate active state caches in C++ and GDScript.
- Legacy fallback appliers.

Files ending in `_godot.*` inside this area form part of the narrow integration boundary. They may translate typed native data to Godot-compatible packed data, but they must not parse or reconstruct fixture semantics.

### `native/src/mvrxchange/`

- **Active**
- Owns MVR-xchange communication and protocol-specific support.
- Must remain separate from live DMX fixture-state resolution.
- Must not contain renderer behavior.

### `native/src/table_model/`

- **Active**
- Owns native table-model data exposed to Godot UI where required.
- Must remain UI-data oriented.
- Must not become an alternate GDTF or live runtime engine.

### Root-level native loader and scene files

Files such as `peraviz_loader.*`, `mvr_scene_loader.*`, `gdtf_scene_builder.*`, `scene_model.h`, and related root-level native sources are currently important to loading and scene construction.

They are **active and migration-sensitive**.

Their allowed responsibilities include:

- MVR archive loading.
- Scene-description parsing.
- Static scene-model creation.
- Asset and geometry discovery.
- Initial fixture metadata collection.
- Calling the project-owned GDTF parser and compiler.
- Producing structural scene installation data.

They must not remain the owner of a parallel live semantic engine once `native/src/gdtf_runtime/` and `native/src/runtime/` own the compiled production path.

If their responsibilities are split into new focused modules, update this document and the build files in the same change.

### `gobo_vectorizer.*` and CPU-side visual resources

- **Active and migration-sensitive**
- CPU-side gobo decoding, normalization, rasterization, vectorization, hashing, and caching belong in native code when practical.
- These operations must not run every frame.
- Native code prepares CPU-side image, mask, SDF, atlas, or resource data.
- Godot remains responsible for final renderer-facing texture, material, shader, and RID creation.
- Rotation, index, speed, direction, and shake should normally remain parametric renderer updates rather than regenerated images.

### Native registration files

- `entry.cpp` and `register_types.*`
  - **Active**
  - Own GDExtension initialization and native class registration.
  - Legacy runtime classes must be removed from registration when they are no longer part of the approved architecture.
  - A migration is not complete while an obsolete runtime remains registered as an automatic fallback.

## Godot source structure

The Godot scripts live directly under `scripts/`.

```text
scripts/
|-- beam_renderers/
|-- controllers/
|-- dmx_capabilities/
|-- gobo_vectorization/
|-- project/
|-- runtime/
|   `-- visual_sections/
|-- scene_loading/
|-- shaders/
|-- ui/
|-- asset_runtime_cache.gd
|-- beam_optics_controller.gd
|-- day_night_environment_controller.gd
|-- dmx_capability_control_reader.gd
|-- dmx_capability_normalizer.gd
|-- dmx_fixture_runtime.gd
|-- dmx_gobo_range_resolver.gd
|-- dmx_monitor_window.gd
|-- editor_camera.gd
|-- fixture_gobo_projector.gd
|-- fog_volume_gobo_beam_controller.gd
|-- gobo_shake_limits.gd
|-- load_scene.gd
|-- scene_registry.gd
`-- visual_settings_window.gd
```

This is a responsibility map, not an exhaustive filename list.

## Godot ownership rules

Godot owns:

- Scene presentation.
- Camera behavior.
- User interaction.
- UI and diagnostics presentation.
- Node, RID, material, mesh, texture, shader, beam, atmosphere, and post-processing setup.
- Registration of renderer-facing targets.
- Application of prepared structural data.
- Application of prepared typed live deltas.
- Renderer-specific approximation after native semantic resolution.

Godot does not own:

- Live Art-Net, sACN, or DMX packet interpretation.
- GDTF semantic parsing.
- ChannelFunction or ChannelSet evaluation.
- ModeMaster or relation evaluation.
- Physical-range mapping.
- Magic channel-type translation.
- Per-frame reconstruction of fixture behavior.
- CPU-heavy gobo generation in the live path.
- A second authoritative fixture-state engine.

### `scripts/runtime/`

- **Target and partially active**
- Owns the thin Godot-side runtime client and renderer application services.
- It may:
  - Install structural schemas and render-target registries.
  - Validate protocol versions and schema generations.
  - Iterate present section descriptors.
  - Apply typed rows to cached renderer targets.
  - Update Node properties, RIDs, materials, shaders, textures, and visibility.
- It must not:
  - Parse GDTF or DMX semantics.
  - Reconstruct a universal fixture-state Dictionary.
  - Resolve attributes from names.
  - Decode coarse, fine, or ultra-fine channel data.
  - Maintain a duplicate authoritative runtime state.

### `scripts/runtime/visual_sections/`

- **Target and active**
- Contains domain-specific appliers for typed native visual sections.
- Appliers should remain small and renderer-oriented.
- One section must not reset unrelated domains with default values.
- Section appliers must use cached component and render-target IDs.
- Section appliers must not call a universal fixture apply method that reinterprets all fixture state.

### `scripts/scene_loading/`

- **Active**
- Owns Godot-side scene installation and presentation orchestration.
- May create Nodes and renderer-facing resources during scene load or structural rebuild.
- Must consume prepared structural data.
- Must not become a second MVR or GDTF semantic parser.

### `scripts/beam_renderers/`

- **Active**
- Owns renderer-specific beam implementations.
- May provide volumetric, lightweight, debug, or future renderer variants.
- Receives prepared optical and intensity values.
- Must not interpret raw fixture channels.

### `scripts/shaders/`

- **Active**
- Owns shader resources and shader-facing helpers.
- Parameter animation is allowed.
- GDTF and DMX interpretation is not allowed.

### `scripts/controllers/`

- **Active**
- Owns user-facing and renderer-facing coordination that is not part of the native semantic pipeline.
- Controllers must remain thin and must not duplicate native runtime state.

### `scripts/ui/` and UI-oriented root scripts

- **Active**
- Own windows, panels, controls, monitoring views, settings, and user interaction.
- Diagnostic UI may display raw or semantic information.
- Displaying diagnostics does not make UI code the owner of that data.

### `scripts/project/`

- **Active**
- Owns project-level Godot services and lifecycle helpers.
- Must not absorb fixture semantics or live DMX resolution.

### `scripts/dmx_fixture_runtime.gd`

- **Active, migration-sensitive, and not the target authority**
- This is a current architectural hotspot.
- It may temporarily coordinate the existing runtime while migration work is incomplete.
- It must not receive new GDTF semantic features, new magic channel mappings, new universal caches, or new legacy fallback behavior.
- Its target replacement is a thin coordinator that:
  - Requests native structural installation.
  - Submits or forwards universe frames to native code.
  - Consumes typed native deltas.
  - Delegates rows to renderer appliers.
- A GDTF-first migration is not complete while this script builds the authoritative per-fixture DMX binding model or resolves live fixture semantics.

### `scripts/dmx_capabilities/` and related root capability scripts

- **Active and migration-sensitive**
- UI inspection and diagnostic presentation may remain.
- Production GDTF capability normalization and live semantic resolution must migrate to the native parser and compiler.
- Do not extend these paths as an alternate runtime engine.

### `scripts/gobo_vectorization/`, `dmx_gobo_range_resolver.gd`, and related gobo helpers

- **Active and migration-sensitive**
- Renderer-facing gobo setup may remain in Godot.
- CPU-heavy generation, GDTF wheel and slot interpretation, DMX range resolution, and cache-key semantics belong in native code.
- These scripts must not become the authoritative source of gobo selection or movement.
- No gobo image should be regenerated every frame for rotation, index, or shake.

### `load_scene.gd`

- **Active and migration-sensitive**
- Owns high-level scene-loading and viewer orchestration.
- It may call native loaders and install returned scene data.
- It must not grow additional GDTF, DMX, runtime, or renderer-domain responsibilities.
- Large responsibilities should be extracted into the correct existing module.

### `scene_registry.gd`

- **Active**
- Owns cached Godot references from stable scene, component, and render-target IDs to Nodes, RIDs, or renderer resources.
- It must avoid per-frame scene-tree searches.
- It must not assign semantic meaning to GDTF attributes.
- Structural compilation should provide the identities that the registry installs.

## C++ and Godot boundary ownership

The boundary is split into two contracts.

### Structural installation contract

This contract is used after:

- MVR load.
- GDTF load or fixture-type compilation.
- DMX mode change.
- Patch change.
- Geometry or component topology change.
- Renderer-target registration change.
- Resource topology change.

The structural contract may contain:

- Fixture instance IDs.
- Compiled fixture-type IDs.
- Component IDs.
- Geometry IDs.
- Emitter IDs.
- Wheel IDs.
- Wheel-slot IDs.
- Render-target IDs.
- Static transforms.
- Resource references or hashes.
- Component-to-target mappings.
- Protocol version.
- Schema generation.

Godot installs this data and caches renderer references.

### Live delta contract

This contract is used during live playback.

It may contain prepared dirty changes for:

- Geometry transforms.
- Emitter intensity and visibility.
- Linear color.
- Beam optics.
- Wheel and slot selection.
- Wheel motion.
- Prism state.
- Shutter and strobe output.
- Material or shader parameters.
- Supported generic visual outputs.

It must not contain data that requires Godot to evaluate GDTF semantics or decode DMX channels.

## Required production flow

```text
MVR and GDTF input
    -> native archive and file access
    -> project-owned MVR and GDTF parsers
    -> serialization-neutral semantic models
    -> compiled fixture types and selected DMX modes
    -> structural scene and component registry
    -> native compiled DMX programs
    -> native physical and render-state resolution
    -> native dirty-state generation
    -> versioned typed section deltas
    -> thin Godot section appliers
    -> cached Nodes, RIDs, materials, textures, and shaders
    -> renderer and GPU
```

The first required vertical proof is:

```text
Real GDTF
    -> parser
    -> compiled fixture type
    -> scene and component registry
    -> compiled Dimmer, Pan, and Tilt programs
    -> DMX frame
    -> native resolved values
    -> typed dirty deltas
    -> direct Godot render-domain application
```

This proof must not route through manually constructed legacy channel bindings.

## Documentation ownership

```text
docs/
|-- architecture.md
|-- gdtf-runtime-architecture.md
|-- dmx-visual-runtime.md
|-- gdtf-support-matrix.md
|-- peraviz-perastage-gdtf-contract.md
|-- adr-gdtf-parser-ownership.md
|-- godot_performance_guidelines.md
|-- contract/
|   `-- gdtf/
`-- other build, UI, rendering, and workflow documents
```

### Documentation rules

- `docs/architecture.md`
  - Owns stable target architecture and top-level data flow.
  - Must not describe planned behavior as already active.

- `docs/gdtf-runtime-architecture.md`
  - Owns GDTF-specific semantic, compiled-model, and runtime architecture.
  - Must separate target, active, migration-sensitive, and unsupported behavior.

- `docs/dmx-visual-runtime.md`
  - Owns the versioned structural and live boundary protocols.
  - Must define integer and float payload ownership, schema validation, and invalidation rules.

- `docs/gdtf-support-matrix.md`
  - Owns supported, partial, diagnostic-only, and unsupported GDTF features.
  - Must match tests and the active compiler.

- `docs/peraviz-perastage-gdtf-contract.md`
  - Owns the shared serialization-neutral semantic contract.
  - Must not include Godot renderer details or Perastage editor-only behavior.

- `docs/contract/gdtf/`
  - Owns deterministic cross-project semantic fixtures and snapshots.

## Test and guardrail ownership

```text
tests/
|-- check_peraviz_tree_modules.sh
|-- check_no_large_files.sh
|-- check_godot_boundary_lightweight.sh
|-- check_gdtf_component_runtime_guardrails.sh
`-- other repository architecture checks

native/tests/
|-- parser and compiled-model tests
|-- runtime core tests
|-- schema and protocol tests
|-- semantic contract tests
`-- end-to-end vertical tests
```

### Test rules

- Repository checks must inspect the real paths:
  - `scripts/`
  - `native/src/`
  - `native/tests/`
  - `project.godot`
  - `peraviz.gdextension`
  - Native registration and build files.
- A missing expected path must fail the check instead of returning success.
- Guardrails must check active APIs and dependency relationships, not only banned names.
- Tests for the GDTF-first runtime must use parser-owned and compiler-owned data.
- Manually constructed legacy fixture bindings may remain only in explicitly named legacy tests while that legacy path still exists.
- Legacy tests must not be accepted as proof that the replacement architecture works.
- Deleted legacy classes, APIs, files, and registrations should have guardrails preventing reintroduction.
- Architecture checks must remain small, deterministic, and readable.

## Generated files and source control

The following locations are not architectural source modules:

- `.godot/`
- Native build directories.
- CMake output directories.
- Imported Godot cache data.
- Temporary extracted MVR or GDTF content.
- Generated textures, atlases, or vectorization caches.
- Platform packaging output.
- Local profiler captures.

Generated content must not be used as the only copy of source data or runtime contracts.

## Rules for moving responsibilities

When moving a responsibility:

1. Update this document.
2. Update `docs/architecture.md` or the relevant protocol document.
3. Update explicit build registration.
4. Update native class registration when applicable.
5. Update or add tests and architecture guardrails.
6. Remove the previous active owner when the task is an architectural replacement.
7. Do not leave an undocumented automatic fallback.
8. Confirm that the production call graph uses the new owner.

A change is not complete merely because the new module exists. The old path must stop being authoritative.

## Current migration priorities

The following areas require special care during the GDTF-first runtime replacement:

- `scripts/runtime/visual_sections/` contains modular live visual section appliers for the native sectioned frame protocol.
- `native/src/gdtf_runtime/registry/official_attributes.json` pins the local GDTF attribute registry provenance used by shared Peraviz/Perastage tests.
- `docs/contract/gdtf/` stores deterministic semantic contract snapshots.

- `native/src/runtime/peraviz_visual_runtime.*` owns the component-oriented native visual runtime and emits typed dirty sections.
- `tests/check_gdtf_component_runtime_guardrails.sh` prevents deleted fixed-control and universal-applier runtime patterns from returning.
