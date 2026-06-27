# Peraviz v0.1.0 Release Notes

Changes since the initial Peraviz repository split.

## Highlights

- Peraviz can now remember the last opened MVR or PVZ project for a smoother return to recent work, without forcing startup auto-load on.
- Added the first read-only Fixture Inspection panel for reviewing loaded fixture information from the main User area.
- Introduced the first `.pvz` project archive foundation for saving Peraviz sessions with embedded MVR scene data and project settings.

## New features

- MVR-xchange can now advertise Peraviz as a TCP-mode station, join discovered stations, detect available MVR revisions, manually request an update, safely receive the MVR file, and load it through the existing scene import workflow.
- Added a first-phase MVR-xchange discovery panel for finding local stations such as Perastage without requesting or loading MVR files yet.
- Added a read-only Fixture Inspection panel in the User area so loaded MVR and PVZ scenes can be reviewed by fixture name, user-facing fixture ID, type, patch address, and DMX binding status without opening Debug tools.
- Added the first Peraviz project archive foundation, allowing sessions to be saved as reliably written `.pvz` files containing the current MVR and basic Peraviz settings.
- Peraviz now remembers the last opened MVR or PVZ project as a user preference, while keeping startup auto-load as an explicit opt-in choice instead of enabling it whenever a file is loaded or saved.
- Added an Advanced startup auto-load toggle so users who want Peraviz to reopen their last show automatically can enable that behavior deliberately.
- New `.pvz` archives now include a reserved `fixture_overrides.json` file so future fixture-level project data has a stable place in the archive without changing the base layout.

## Improvements

- Hardened the MVR-xchange viewer/client path with stricter UUID handling, safer received-file finalization, clearer request/receive/load state reporting, and documentation for the standard-compatible manual update workflow.

- Improved DMX unlinked fixture presentation so fixture names and available patch details are shown in user-facing summaries instead of exposing UUIDs by default.
- Made the DMX panel easier to scan by keeping the quick fixture summary visible while moving unlinked fixture technical details behind an optional details toggle.
- Made last loaded file recovery more predictable by preserving the user's startup auto-load choice and reporting clear messages when remembered files are missing or unsupported.

## Fixes

- Fixed an editor-time AppShell initialization issue that could report a placeholder-instance error while loading the Peraviz scene in Godot.

## Stability and reliability

- Project archive writes now include the current MVR, visual settings, DMX settings, app state, and reserved fixture override data in a consistent version 1 layout.
- PVZ loading tolerates missing optional JSON files from older archives while still validating that required scene data is present.

## Documentation

- Expanded MVR-xchange documentation with the current TCP join, commit detection, manual request, receive, and load workflow.
- Added MVR-xchange documentation that clarifies the Phase 1 discovery-only scope and Peraviz viewer role.
- Documented the initial `.pvz` project archive format and its version 1 archive structure, including reserved future fixture override data and compatibility expectations for older archives.
- Documented the Peraviz project architecture around MVR scene data, GDTF fixture definitions, future PVZ project data, and runtime fixture entities.
- Clarified the separation between `.pvz` project data and global user preferences, including how remembered last-file paths are treated as session preferences rather than project source content.

## Internal changes

- Cleaned up GDScript editor warnings in the MVR-xchange panel, received-file callback, and fixture light apply service so project reloads stay quieter for maintainers.
- Added Perastage-compatible runtime table schemas and in-memory row storage for fixtures, trusses, and scene objects to prepare Peraviz for future cell-based synchronization without adding Live Link transport or editing UI.
- Added a focused fixture row provider so fixture inspection UI now reads stable fixture metadata rows built from loaded MVR scene data, patch metadata, and DMX binding state instead of assembling fixture details in UI-facing code.
- Added a focused project archive service for reading and writing the initial `.pvz` archive files.
- Extended user preferences with lightweight session state for the last loaded file and project auto-load / DMX auto-start options.
- Peraviz now has a dedicated version source and release-notes draft workflow.
- Replaced wxWidgets-based native archive handling with a small libzip-backed archive layer, reducing Windows export dependencies for MVR and GDTF loading.
- Prevented native source and CMake build output from being scanned as Godot resources, avoiding accidental imports of compiled object files in the editor.
- Added reproducible Windows static native build presets, dependency verification guidance, and export documentation so Godot exports keep `peraviz_native.dll` under `bin/` without obsolete third-party runtime DLLs.
