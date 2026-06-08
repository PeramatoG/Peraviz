# Peraviz v0.1.0 Release Notes

Changes since the initial Peraviz repository split.

## Highlights

## New features

- Added the first Peraviz project archive foundation, allowing sessions to be saved as reliably written `.pvz` files containing the current MVR and basic Peraviz settings. Peraviz now remembers the last opened MVR or project file and includes a top-bar option to auto-load the last show by default for new preferences, plus an Advanced option to auto-start DMX on project load when project settings allow it.

## Improvements

## Fixes

- Made last loaded file recovery more predictable by keeping startup auto-load user-configurable, preserving the setting when supported files are loaded or saved, and reporting clear messages when remembered files are missing or unsupported.

## Stability and reliability

- Fixed an editor-time AppShell initialization issue that could report a placeholder-instance error while loading the Peraviz scene in Godot.

## Documentation

- Documented the initial `.pvz` project archive format and its version 1 archive structure, including reserved future fixture override data and compatibility expectations for older archives.
- Documented the Peraviz project architecture around MVR scene data, GDTF fixture definitions, future PVZ project data, and runtime fixture entities.
- Clarified the separation between `.pvz` project data and global user preferences, including how remembered last-file paths are treated as session preferences rather than project source content.

## Internal changes

- Added a focused project archive service for reading and writing the initial `.pvz` archive files.
- Extended user preferences with lightweight session state for the last loaded file and project auto-load / DMX auto-start options.
- Peraviz now has a dedicated version source and release-notes draft workflow.
