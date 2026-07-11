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
require_path "scripts/runtime/native_renderer_target_registry.gd" file
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
reject_pattern 'dimmer_target_id_by_fixture_|component_state_by_fixture_' 'Native Dimmer state must not collapse component properties by fixture.' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/peraviz_visual_runtime.h
reject_pattern 'entry\["dimmer_target_id"\]' 'Renderer manifest must expose target collections instead of one overwritable Dimmer field per fixture.' native/src/peraviz_loader.cpp
require_pattern 'normalized_value.*physical_value|physical_value.*normalized_value' 'Native runtime must keep normalized and physical evaluation values distinct.' native/src/runtime/peraviz_visual_runtime.h native/src/runtime/peraviz_visual_runtime.cpp
reject_pattern '"beam_resources"|beam_resources' 'Godot Dimmer target records must not label anchor lights as beam resources.' scripts/load_scene.gd scripts/runtime tests/gdscript
require_pattern 'LegacyConeBeamRenderer' 'Renderer-target regression coverage must exercise the Lightweight Prism backend.' tests/gdscript scripts/beam_renderers
require_pattern 'NativeRendererTargetRegistry' 'Native renderer target registry must be extracted into a focused runtime service.' scripts/runtime/native_renderer_target_registry.gd scripts/load_scene.gd
require_pattern 'func apply_beam_optics' 'Production beam renderers must expose a real BeamOptics API.' scripts/beam_renderers/beam_renderer_base.gd scripts/beam_renderers/legacy_cone_beam_renderer.gd
require_pattern 'CompiledBeamOpticalProfile' 'Static Beam optical profiles must be compiled in native setup data.' native/src/runtime/visual_runtime_types.h native/src/gdtf_runtime/runtime_scene_compiler.cpp
require_pattern 'beam_radius_params' 'Lightweight Prism shader must expose parametric near/far optics deformation.' scripts/shaders/legacy_beam_cone.gdshader scripts/beam_renderers/legacy_cone_beam_renderer.gd
require_path "tests/gdscript/test_lightweight_prism_beam_optics.gd" file
reject_pattern 'source_beam_radius.*lens_radius = max\(source_beam_radius' 'BeamRadius must not unconditionally overwrite measured lens radius.' scripts/load_scene.gd
reject_pattern 'VISUAL_CHANGE_ZOOM \| VISUAL_CHANGE_BEAM_TOPOLOGY' 'Zoom-only changes must not force topology rebuilds.' native/src/runtime/peraviz_visual_runtime.cpp scripts/runtime/fixture_light_apply_service.gd
require_pattern 'CompiledSemantic::Zoom|CompiledSemantic::Zoom' 'Zoom must be part of the compiled native semantic path.' native/src/gdtf_runtime/runtime_scene_compiler.cpp native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/visual_runtime_types.h
require_pattern 'VisualSectionType::BeamOptics' 'BeamOptics rows must remain a native sectioned visual-frame path.' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/visual_frame_schema.cpp
require_pattern 'apply_beam_optics\(loader, fixture_uuid, optics_target_id' 'BeamOptics application must use cached target IDs rather than fixture-wide traversal.' scripts/runtime/fixture_light_apply_service.gd scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd
reject_pattern 'VisualChangeZoom \| VisualChangeBeamTopology' 'Zoom-only changes must not be marked as topology rebuilds.' native/src/runtime/peraviz_visual_runtime.cpp scripts/runtime/fixture_light_apply_service.gd
reject_pattern 'var _native_(pan|tilt|dimmer|geometry)_|var _native_target_resolution|var _native_target_registry_summary|func _register_native_axis_target|func _register_native_dimmer_target|func _build_native_geometry_target_map' 'load_scene.gd must delegate native target registry ownership to the focused service.' scripts/load_scene.gd

if [[ "$failures" -ne 0 ]]; then
  echo "[runtime-architecture] Found $failures violation(s)." >&2
  exit 1
fi

echo "[runtime-architecture] Current sectioned runtime invariants passed."
