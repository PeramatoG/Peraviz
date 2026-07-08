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

Future MVR writing must be implemented against the official MVR specification. Peraviz should not write partial or non-standard MVR mutations as a shortcut.

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
- Pan / tilt visual inversion.
- Debug or advanced visualizer options.

Global preferences such as recently opened paths and auto-start settings are user preferences, not project source data, and should remain outside `.pvz` archives.

## Editing ownership rules

Editing features must first identify the owning data layer:

- Patch, position, rotation, fixture name, and fixture number belong to MVR.
- Fixture modes, geometry, wheels, gobos, and capabilities belong to GDTF.
- Visual environment, camera, Art-Net settings, visual-only overrides, and UI state belong to Peraviz project data.
- Live DMX values are runtime state and should not be saved as fixture definitions.

If the owning source layer is not writable yet, the feature should remain read-only or save only an explicit Peraviz override that does not pretend to modify the source file.
