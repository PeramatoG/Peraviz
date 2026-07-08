#!/usr/bin/env bash
set -euo pipefail

failures=0

reject() {
  local pattern="$1"
  local message="$2"
  shift 2
  if rg -n "$pattern" "$@" >/tmp/peraviz_guard_hits.txt; then
    echo "[guardrail] $message" >&2
    cat /tmp/peraviz_guard_hits.txt >&2
    failures=$((failures + 1))
  fi
}

reject 'kRuntimeControlCount|enum RuntimeControl|control_index_for_channel_type|std::array<float,\s*13>|std::array<float,\s*9>|floor\([^\n]*255|row\.fixture_id,\s*1' 'Fixed-control runtime patterns must not return.' native/src/runtime
reject '_fixture_states|_apply_lighting_section|_native_channel_values|_native_render_ready_values|_fixture_output_buffers|_fixture_apply_plans|get_live_visual_gobo_controls_for_fixture|_native_gobo_source_wheel' 'Legacy per-frame fixture state and gobo bridge patterns must not return to active appliers.' scripts/runtime/visual_sections scripts/runtime/fixture_light_apply_service.gd
reject '_apply_visual_frame_lighting\(' 'Section appliers must use direct render-domain methods instead of the universal lighting apply method.' scripts/runtime/visual_sections
reject 'struct VisualFrame\b|visual_frame_buffers\.h' 'Obsolete visual frame buffer types must stay deleted.' native/src

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
