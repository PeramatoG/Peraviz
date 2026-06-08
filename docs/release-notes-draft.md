# Peraviz v0.1.0 Release Notes

Changes since the initial Peraviz repository split.

## Highlights

## New features

- Added the first Peraviz project archive foundation, allowing sessions to be saved as `.pvz` files containing the current MVR and basic Peraviz settings.

## Improvements

## Fixes

## Stability and reliability

- Fixed an editor-time AppShell initialization issue that could report a placeholder-instance error while loading the Peraviz scene in Godot.

## Documentation

- Documented the initial `.pvz` project archive format and its version 1 archive structure.
- Documented the Peraviz project architecture around MVR scene data, GDTF fixture definitions, future PVZ project data, and runtime fixture entities.

## Internal changes

- Added a focused project archive service for reading and writing the initial `.pvz` archive files.
- Peraviz now has a dedicated version source and release-notes draft workflow.
