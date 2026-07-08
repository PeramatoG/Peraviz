#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "[runtime-architecture] $1" >&2
  failures=$((failures + 1))
}

require_path() {
  local path="$1"
  local type="$2"
  if [[ "$type" == "file" && ! -f "$path" ]]; then
    fail "Required file '$path' is missing."
  elif [[ "$type" == "directory" && ! -d "$path" ]]; then
    fail "Required directory '$path' is missing."
  fi
}

require_pattern() {
  local pattern="$1"
  local message="$2"
  shift 2
  if ! rg -q "$pattern" "$@"; then
    fail "$message"
  fi
}

reject_pattern() {
  local pattern="$1"
  local message="$2"
  shift 2
  local hits="$TMP_DIR/hits.txt"
  if rg -n "$pattern" "$@" >"$hits"; then
    echo "[runtime-architecture] $message" >&2
    cat "$hits" >&2
    failures=$((failures + 1))
  fi
}

if ! command -v rg >/dev/null 2>&1; then
  echo "[runtime-architecture] ripgrep (rg) is required." >&2
  exit 2
fi

require_path "project.godot" file
require_path "peraviz.gdextension" file
require_path "native/src/runtime" directory
require_path "scripts/runtime/visual_sections" directory
require_path "scripts/dmx_fixture_runtime.gd" file
require_path "native/src/register_types.cpp" file

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

require_pattern 'SectionedVisualFrame' 'Native sectioned visual frame type is missing.' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/visual_frame_schema.h
require_pattern 'descriptors' 'Visual frame descriptor payload is missing from the Godot bridge.' native/src/runtime/peraviz_visual_runtime_godot.cpp
require_pattern 'integers' 'Visual frame integer payload is missing from the Godot bridge.' native/src/runtime/peraviz_visual_runtime_godot.cpp
require_pattern 'floats' 'Visual frame float payload is missing from the Godot bridge.' native/src/runtime/peraviz_visual_runtime_godot.cpp
require_pattern 'SectionedVisualFrameApplier' 'Godot sectioned visual frame applier is missing.' scripts/dmx_fixture_runtime.gd scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd

reject_pattern 'register_class<godot::PeravizDmxUniverseDecoder>|ClassDB::register_class<PeravizDmxUniverseDecoder>' 'Old Godot universe decoder must not be registered as the live path.' native/src/register_types.cpp
reject_pattern 'decode_universe(_compact|_render_ready|_visual_render_ready)?\(' 'Live Godot scripts must not call old universe decoder APIs.' scripts/controllers scripts/runtime scripts/*.gd
reject_pattern 'visual_frame_buffers\.h|struct VisualFrame\b' 'Obsolete fixed native visual-frame buffer path must stay deleted.' native/src/runtime native/src/register_types.cpp
reject_pattern 'kVisualChannelCount|VisualChannel|std::array<float,\s*kVisualChannelCount>|kRuntimeControlCount|enum RuntimeControl|control_index_for_channel_type' 'Fixed native visual row/control layouts must not return.' native/src/runtime
reject_pattern 'LEGACY_|apply_visual_frame_to_fixture|update_live_visual_gobo_from_section|_apply_visual_frame_lighting\(' 'Section appliers must not reconstruct the removed universal fixed row.' scripts/runtime/visual_sections
reject_pattern 'PackedFloat32Array = _native_visual_runtime\.consume_latest_visual_frame|visual_frame\[0\]' 'Legacy fixed-row live GDScript consume path must stay removed.' scripts/dmx_fixture_runtime.gd scripts/runtime

if [[ "$failures" -ne 0 ]]; then
  echo "[runtime-architecture] Found $failures violation(s)." >&2
  exit 1
fi

echo "[runtime-architecture] Current sectioned runtime invariants passed."
