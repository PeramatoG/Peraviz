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
3. The native visual runtime layer keeps persistent render-ready fixture state, compares incoming values with small numeric tolerances, and emits only fixtures whose visual state changed.
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


### Realtime DMX visual apply path

The live DMX path uses a visual attribute-mask batch route for render-ready native rows. `DmxFixtureRuntime` converts changed DMX channel masks into visual masks such as dimmer, pan/tilt, color, zoom, beam shape/intensity, gobo, prism, strobe, light, emissive, and material. The compact row stays flat, but the row mask now describes the visual attributes to touch instead of relying on capability presence or a dimmer-only special case.

`DmxController` keeps pending visual batches latest-state-wins. If a newer batch arrives before the previous one is applied, rows are coalesced by integer fixture ID, visual masks are merged, and the newest state values are kept. This prevents the renderer from accumulating stale visual states while preserving independent attributes such as pan/tilt and dimmer when they arrive in separate worker iterations.

At scene binding time, Peraviz registers fixture render handles once by integer fixture ID. The main-thread batch apply uses pre-resolved pan/tilt axes, lights, and emissive materials. Pan/tilt rows only write axis transforms, dimmer rows only update visibility/energy/beam intensity/emissive energy, color rows only update light/beam/material color, and zoom rows update spotlight angle without forcing unrelated color, dimmer, or gobo work. Complex gobo/prism topology remains isolated and reported separately while the legacy per-fixture Dictionary callback path stays available for debug/manual compatibility and unsupported migration gaps.

The Technical Monitor includes a dedicated Realtime DMX Metrics panel with copyable JSON and optional JSONL logging. It separates receiver packet age from main-thread status refresh gap, worker loop gap, visual apply duration, monitor refresh duration, batch rows, coalescing counters, per-attribute apply counters, and legacy fallback counters so `last_packet_ms_ago` is not mistaken for visual latency.


The batch bridge keeps a persistent per-fixture visual state table on the Godot side while the native decoder migration continues. The first valid DMX row for a fixture initializes dimmer, pan, tilt, zoom, beam angle, render-ready color, light energy, beam energy, and emissive energy, then forces one full visual apply so dimmer-only first packets still have valid color/material/beam state. Later rows update only the attributes indicated by the visual mask and reuse cached state for dependencies. Metrics distinguish attempted writes from applied writes and report first-DMX initialization plus missing/rebuilt handles against the 16.6 ms frame budget. No interpolation or smoothing is used.

#### Realtime DMX stress-test metric capture

For all-on/off, pan-only, tilt-only, pan+tilt, CMY color-only, zoom-only, gobo-only, prism-only, strobe-only, and mixed fixture-group tests, open **DMX > Technical Monitor > Realtime DMX Metrics** and press **Copy metrics JSON** after each run. Repeat the same sequence with the Technical Monitor closed and compare `apply.visual_apply_block_ms`, `apply.ui_monitor_refresh_usec`, `receiver.main_thread_status_refresh_gap_ms`, `worker.dmx_worker_loop_gap_ms`, `apply.coalesced_rows`, and the per-attribute counters. If the receiver packet age grows while the main-thread gap and apply duration stay low, investigate native receiver/socket pressure; if the main-thread gap or monitor refresh duration grows, the stall is on the Godot/UI side.
