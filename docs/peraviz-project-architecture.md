# Peraviz Project Architecture

## Purpose

This document defines the intended Peraviz data model and runtime direction before new editing features are added. It is a planning document for ownership, persistence, and UI decisions; it does not introduce `.pvz` save/load, MVR writing, or GDTF mutation by itself.

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

The planned `.pvz` format is a future zip-based Peraviz project archive. A `.pvz` should contain:

- An MVR file.
- Peraviz-specific JSON configuration files.

The `.pvz` format should store Peraviz-specific runtime and visual state, including:

- Visual environment settings.
- Camera state.
- Art-Net / DMX settings.
- UI / application state.
- Visual-only fixture overrides.
- Pan / tilt visual inversion.
- Debug / advanced options.

A `.pvz` file does not replace MVR. It wraps an MVR and adds Peraviz runtime and visual state that does not belong in MVR or GDTF source files.

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
5. Add a `.pvz` project save/load foundation.
6. Add MVR writing for patch, position, rotation, fixture name, and fixture ID / fixture number.
7. Only later consider GDTF mutation with a formal mutation policy.
