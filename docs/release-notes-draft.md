# Peraviz v0.1.0 Release Notes

Changes since the initial Peraviz repository split.

## Highlights

## New features

- Added the first Peraviz project archive foundation, allowing sessions to be saved as reliably written `.pvz` files containing the current MVR and basic Peraviz settings. Peraviz now remembers the last opened MVR or project file, can automatically load it at startup, and includes Advanced options to auto-load the last project and auto-start DMX on project load when project settings allow it.

## Improvements

## Fixes

- Made last loaded file recovery more reliable by enabling startup auto-load by default for new preferences, re-enabling startup recovery whenever a supported file is loaded or saved, and reporting clear messages when remembered files are missing or unsupported.

## Stability and reliability

- Fixed an editor-time AppShell initialization issue that could report a placeholder-instance error while loading the Peraviz scene in Godot.

## Documentation

- Documented the initial `.pvz` project archive format and its version 1 archive structure.
- Documented the Peraviz project architecture around MVR scene data, GDTF fixture definitions, future PVZ project data, and runtime fixture entities.

## Internal changes

- Added a focused project archive service for reading and writing the initial `.pvz` archive files.
- Extended user preferences with lightweight session state for the last loaded file and project auto-load / DMX auto-start options.
- Peraviz now has a dedicated version source and release-notes draft workflow.
