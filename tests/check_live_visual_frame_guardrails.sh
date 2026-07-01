#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

if rg -n "register_class<godot::PeravizDmxUniverseDecoder>" native/src/register_types.cpp; then
  fail "PeravizDmxUniverseDecoder must not be registered for live Godot DMX playback."
fi

if rg -n "decode_universe(_compact|_render_ready|_visual_render_ready)?\(" scripts/controllers scripts/runtime scripts/*.gd; then
  fail "Live Godot DMX scripts must not call legacy universe decoder APIs."
fi

if rg -n "_apply_compact_universe_updates\(" scripts/controllers scripts/runtime scripts/*.gd | rg -v "scripts/dmx_fixture_runtime.gd:.*func _apply_compact_universe_updates"; then
  fail "Live Godot DMX scripts must not fall back to compact per-fixture callback updates."
fi

echo "Live visual-frame guardrails passed."
