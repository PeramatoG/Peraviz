#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Reports one architecture-check failure without stopping the remaining checks.
fail() {
  echo "[godot-boundary] $1" >&2
  failures=$((failures + 1))
}

# Requires one repository path used by this check.
require_path() {
  local path="$1"
  local expected_type="$2"

  case "$expected_type" in
    directory)
      if [[ ! -d "$path" ]]; then
        fail "Required directory '$path' is missing. Update the repository layout or this check explicitly."
      fi
      ;;
    file)
      if [[ ! -f "$path" ]]; then
        fail "Required file '$path' is missing. Update the repository layout or this check explicitly."
      fi
      ;;
    *)
      fail "Internal check error: unknown expected path type '$expected_type' for '$path'."
      ;;
  esac
}

# Rejects one source pattern in the supplied paths and prints all matching lines.
reject_pattern() {
  local pattern="$1"
  local message="$2"
  shift 2

  local output_file="$TEMP_DIR/hits.txt"
  : >"$output_file"

  if rg -n \
    --glob '*.gd' \
    --glob '*.cs' \
    --glob '*.tscn' \
    --glob '*.cpp' \
    --glob '*.cc' \
    --glob '*.cxx' \
    --glob '*.h' \
    --glob '*.hpp' \
    --glob '!**/.godot/**' \
    --glob '!**/build/**' \
    --glob '!**/generated/**' \
    "$pattern" "$@" >"$output_file"; then
    echo "[godot-boundary] $message" >&2
    cat "$output_file" >&2
    failures=$((failures + 1))
  fi
}

if ! command -v rg >/dev/null 2>&1; then
  echo "[godot-boundary] ripgrep (rg) is required to run this architecture check." >&2
  exit 2
fi

# The Godot project currently lives at the repository root.
require_path "project.godot" file
require_path "peraviz.gdextension" file
require_path "scripts" directory
require_path "scripts/runtime" directory
require_path "native/src" directory
require_path "native/src/runtime" directory

# Do not continue with partial scopes because a missing path could hide violations.
if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

godot_paths=("scripts")
if [[ -f "test.gd" ]]; then
  godot_paths+=("test.gd")
fi
if [[ -f "test.tscn" ]]; then
  godot_paths+=("test.tscn")
fi
if [[ -d "scenes" ]]; then
  godot_paths+=("scenes")
fi

native_boundary_paths=(
  "native/src/runtime"
  "native/src/register_types.cpp"
  "native/src/register_types.h"
)

# Godot must not own live network receivers for Art-Net, sACN, or DMX.
reject_pattern \
  '\b(PacketPeerUDP|UDPServer)\b' \
  "Live UDP or protocol receiving was found in Godot source. Network receiving belongs in native C++." \
  "${godot_paths[@]}"

# The final Godot path must not define magic channel identities.
reject_pattern \
  '\bNATIVE_CHANNEL_[A-Z0-9_]+\b' \
  "Magic native channel constants were found in Godot source. Runtime semantics must come from compiled native programs." \
  "${godot_paths[@]}"

# Fixed compact-control layouts are legacy runtime architecture.
reject_pattern \
  '\b(NATIVE_VISUAL_CHANNEL_COUNT|NATIVE_VISUAL_RENDER_VALUE_COUNT|NATIVE_COMPACT_[A-Z0-9_]+|COMPACT_HAS_[A-Z0-9_]+|COMPACT_[A-Z0-9_]+_NORM)\b' \
  "Fixed compact-control or fixed render-ready layouts were found in Godot source." \
  "${godot_paths[@]}"

# Godot must not build the authoritative per-fixture DMX binding model.
reject_pattern \
  '\b(build_fixture_dmx_bindings|_register_native_visual_runtime_bindings|set_fixture_bindings)\b' \
  "Legacy fixture-binding construction was found in Godot source. Compiled native scene data must own runtime programs." \
  "${godot_paths[@]}"

# Godot must not provide render parameters through per-fixture Dictionaries.
reject_pattern \
  '\bset_fixture_render_params\b' \
  "Legacy per-fixture render-parameter setup was found in Godot source. Structural compiled data must own these values." \
  "${godot_paths[@]}"

# The live Godot path must not decode channel layout or physical ranges.
reject_pattern \
  'get\("(channel_type|fine_address|ultra_fine_address|bit_depth|scale_min|scale_max)"' \
  "Godot-side live binding or channel decoding was found. DMX layout and physical mapping belong in native C++." \
  "scripts/runtime" "scripts/dmx_fixture_runtime.gd"

# Known duplicate fixture-state and legacy gobo caches must not remain authoritative.
reject_pattern \
  '\b(_native_channel_values|_native_render_ready_values|_fixture_apply_plans|_fixture_output_buffers|_live_visual_gobo_controls_by_fixture|_static_gobo_controls_by_fixture)\b' \
  "Legacy duplicate fixture-state or gobo caches were found in the active Godot runtime path." \
  "scripts/runtime" "scripts/dmx_fixture_runtime.gd"

# Production runtime scripts must not resolve GDTF wheel ranges or enrich bindings.
reject_pattern \
  '\b(DmxGoboRangeResolver|enrich_bindings_with_vector_gobos|_build_static_gobo_controls|_build_cached_live_gobo_controls)\b' \
  "Godot-side GDTF gobo semantic resolution was found in the active runtime path." \
  "scripts/runtime" "scripts/dmx_fixture_runtime.gd"

# The native Godot bridge must not expose legacy Dictionary-based setup APIs.
reject_pattern \
  '\b(set_fixture_bindings|set_fixture_render_params|parse_binding|parse_render_params)\b' \
  "Legacy Dictionary-based setup APIs were found in the native Godot boundary." \
  "${native_boundary_paths[@]}"

# The native runtime must not translate magic channel types into semantics.
reject_pattern \
  '\b(LegacySemanticBinding|semantic_parameter_for_legacy_channel_type)\b' \
  "Legacy magic-channel semantic translation was found in the native runtime." \
  "native/src/runtime"

if [[ "$failures" -ne 0 ]]; then
  echo "[godot-boundary] Found $failures architecture boundary violation(s)." >&2
  exit 1
fi

echo "[godot-boundary] Godot remains a thin rendering client and the inspected boundary paths are clean."
