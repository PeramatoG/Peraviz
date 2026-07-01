#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "${GODOT_BIN}" ]]; then
  if command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="godot4"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
  else
    echo "SKIP: Godot executable not found; set GODOT_BIN to run the live gobo resolver regression." >&2
    exit 0
  fi
fi

"${GODOT_BIN}" --headless --path . --script tests/gdscript/test_dmx_gobo_controls_resolver.gd
