# Peraviz PVZ Project Format

Peraviz `.pvz` files are zip-based project archives. The initial implementation is intentionally minimal and versioned as `format_version: 1` so future releases can extend the format without changing MVR or GDTF source files.

## Version 1 archive structure

```text
project.pvz
├── project.json
├── scene.mvr
├── visual_settings.json
├── dmx_settings.json
└── app_state.json
```

## Files

### `project.json`

Project metadata for the archive. Version 1 stores at least:

```json
{
  "format": "PeravizProject",
  "format_version": 1,
  "peraviz_version": "0.1.0",
  "scene_mvr": "scene.mvr"
}
```

### `scene.mvr`

A byte-for-byte copy of the currently loaded MVR scene file. Peraviz does not edit or rewrite the MVR content for this first project-archive foundation.

### `visual_settings.json`

Peraviz visual settings captured from the current runtime settings where available. The file is a JSON object and is ready for future expansion as additional visual-only project state becomes stable.

### `dmx_settings.json`

DMX and Art-Net project settings. Version 1 stores at least:

```json
{
  "universe_offset": -1,
  "auto_start_dmx": false,
  "dmx_enabled_when_saved": false
}
```

`auto_start_dmx` defaults to `false`; opening a project must not unexpectedly bind Art-Net unless a future user-facing workflow explicitly enables that behavior.

### `app_state.json`

Lightweight Peraviz application state. Version 1 stores a minimal object such as:

```json
{
  "last_loaded_file_type": "pvz"
}
```

## Compatibility rules

Readers should tolerate missing optional JSON files and missing optional keys. Safe defaults should be used instead of failing the project load. A project is invalid when the archive cannot be opened or does not contain `scene.mvr`.
