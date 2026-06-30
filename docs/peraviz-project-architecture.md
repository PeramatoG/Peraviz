# Peraviz Project Architecture

## Purpose

This document defines the intended Peraviz data model and runtime direction before new editing features are added. It is a planning document for ownership, persistence, and UI decisions. The first `.pvz` foundation has now been implemented as a zip archive containing a copied MVR and JSON metadata/settings files; MVR writing and GDTF mutation remain out of scope.

Peraviz is intended to be a real-time visualizer and runtime scene application based on MVR, GDTF, Godot, and live DMX. It loads an MVR scene, interprets GDTF fixture definitions, builds Godot runtime scene entities, and reacts to live DMX as the scene runs. Peraviz should therefore be designed as an active runtime visualizer, not only as a passive file viewer.

## Data layers

### 1. MVR scene data

MVR is the scene-level source for data that describes fixture instances and their placement in a show file. Peraviz should treat MVR as the owner of:

- Fixture instances.
- Fixture name.
- Fixture ID / fixture number where available.
- Patch.
- Position.
- Rotation.
- Scene hierarchy.
- References to GDTF files.

Patch, position, rotation, fixture name, and fixture ID / fixture number are scene data. They should eventually be editable in Peraviz and saveable back into an MVR file when explicit editing support is implemented.

Future MVR writing must be implemented in native C++ and must follow the official and current MVR specification. Peraviz should not write partial, non-standard, or compatibility-breaking MVR mutations as a shortcut.

### 2. GDTF fixture definition data

GDTF is the fixture-definition source for data that describes what a fixture type is and how it behaves. Peraviz should treat GDTF as the owner of:

- Fixture type.
- Geometry.
- DMX modes.
- Channels.
- Capabilities.
- Wheels and gobos.
- Physical and visual behavior.

GDTF files must remain read-only for now. Peraviz may parse and cache GDTF-derived data for runtime use, but current workflows must not modify source GDTF files.

Future GDTF mutation may be considered later, but only with an explicit compatibility and audit policy. Any such workflow must follow the official and current GDTF specification, document exactly what may be changed, preserve traceability, and avoid silently rewriting fixture definitions.

### 3. Peraviz project data

The `.pvz` format starts as a zip-based Peraviz project archive. Format version 1 contains:

- `project.json` with Peraviz project metadata.
- `scene.mvr`, copied from the currently loaded MVR file.
- `visual_settings.json` for Peraviz visual settings.
- `dmx_settings.json` for DMX / Art-Net runtime settings.
- `app_state.json` for lightweight application state.

The `.pvz` format should store Peraviz-specific runtime and visual state, including:

- Visual environment settings.
- Camera state.
- Art-Net / DMX settings.
- UI / application state.
- Visual-only fixture overrides.
- Pan / tilt visual inversion.
- Debug / advanced options.

A `.pvz` file does not replace MVR. It wraps an MVR and adds Peraviz runtime and visual state that does not belong in MVR or GDTF source files.

#### Global user preferences

Project archives and global user preferences have separate persistence responsibilities. A `.pvz` file stores project content plus Peraviz visual and runtime project state. Global session preferences are stored outside project archives in `user://user_preferences.cfg`.

Global preferences may remember session-level values such as `last_file_path`, `last_file_type`, `auto_load_last_file`, and `auto_start_dmx`. Remembered paths are not project data and should not be written into `.pvz` as source-of-truth content.

### 4. Runtime fixture entities

Each fixture should be treated as a runtime scene entity, similar to a game-engine actor or character. The runtime fixture entity is the object Peraviz updates, selects, visualizes, and controls while the scene is running.

Each runtime fixture entity combines:

- MVR fixture instance data.
- GDTF fixture definition data.
- Live DMX state.
- Peraviz visual / runtime overrides.
- Godot scene nodes.

DMX acts as the runtime controller for these entities, similar to how a game character might be controlled by player input or AI. The fixture entity should keep source ownership clear: DMX drives live state, MVR supplies scene placement and identity, GDTF supplies fixture behavior, Peraviz project data supplies visual/runtime preferences, and Godot nodes render the result.

## Editing ownership rules

Editing features must preserve data ownership across MVR, GDTF, `.pvz`, and runtime state.

- Patch edits belong to the MVR layer.
- Position and rotation edits belong to the MVR layer.
- Fixture name and fixture ID / fixture number edits belong to the MVR layer.
- Pan / tilt visual inversion belongs to the Peraviz project layer unless a future GDTF mutation workflow explicitly changes that.
- Visual environment settings belong to the Peraviz project layer.
- Live DMX values are runtime state and should not be saved as fixture definitions.

When an edit is added, the UI and persistence path should first identify the owning layer. If the owning layer is not writable yet, the feature should remain read-only or be saved only in an appropriate Peraviz project override.

## Live DMX runtime direction

The live DMX path should keep expensive state work outside the Godot scene tree whenever possible. The intended hot path is:

1. The native Art-Net receiver owns packet reception and latest-frame universe caching.
2. The native DMX decoder consumes only dirty patched universes and normalizes registered fixture channels into fixed-stride numeric rows.
3. The native visual runtime layer keeps persistent render-ready fixture state, compares incoming values with small numeric tolerances, and emits only fixtures whose visual state changed. Dimmer visibility crossings are also marked as beam-topology work so hidden prewarmed beams can be revalidated when a console raises intensity.
4. GDScript receives one compact `PackedFloat32Array` batch per changed universe and applies the existing node, light, material, gobo, prism, and beam updates only for the filtered fixture rows.

This keeps dictionaries, fixture lookup, and SceneTree work out of the decode/filter stage. Godot-side code may still own scene creation, fixture registration, UI, debug tools, and the final render object updates, but it should not rebuild controls or call fixture callbacks for DMX packets that do not produce visible fixture changes.

The current incremental native path preserves the existing compact row layout so legacy fixture apply code continues to work while the renderer can be moved further toward RenderingServer, MultiMesh, instance uniforms, and shader-driven beam updates in smaller focused steps.

## UI direction

Future UI should expose fixture data using user-facing fields that map to lighting workflows:

- Fixture name.
- Fixture ID / fixture number.
- Fixture type.
- Universe.
- Address.
- Mode.
- Channel footprint.
- Position.
- Rotation.

UUIDs may be used internally for stable references, joins, and debugging, but they should not be the primary user-facing identifier except in debug views.

UI growth should follow the existing Shell / Panels / Windows / Controllers / Policies structure. Default screens must stay clean, while advanced and debug views should be opt-in. Fixture tables and editing surfaces should be introduced through focused panels or windows, coordinated by controllers, and guarded by policies that keep normal runtime visualization uncluttered.

## Future implementation sequence

Recommended sequence for future work:

1. Document and stabilize the data ownership model.
2. Add a fixture registry / model that exposes user-facing fixture rows.
3. Add a read-only fixture table UI.
4. Add Peraviz visual overrides for pan / tilt inversion.
5. Add a `.pvz` project save/load foundation. Implemented initially as format version 1 with copied MVR content and JSON metadata/settings files.
6. Add MVR writing for patch, position, rotation, fixture name, and fixture ID / fixture number.
7. Only later consider GDTF mutation with a formal mutation policy.
