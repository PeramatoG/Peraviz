#!/usr/bin/env bash
set -euo pipefail

require_pattern() {
  local pattern="$1"
  local file="$2"
  if ! rg -q "$pattern" "$file"; then
    echo "Missing expected live gobo pattern '$pattern' in $file" >&2
    exit 1
  fi
}

require_pattern "get_live_visual_gobo_controls_for_fixture" scripts/dmx_fixture_runtime.gd
require_pattern "_build_static_gobo_controls" scripts/dmx_fixture_runtime.gd
require_pattern "_build_live_visual_gobo_runtime_bindings" scripts/dmx_fixture_runtime.gd
require_pattern "_append_native_gobo_bindings" scripts/dmx_fixture_runtime.gd
require_pattern "_first_selectable_gobo_wheel" scripts/dmx_fixture_runtime.gd
require_pattern "NATIVE_CHANNEL_GOBO.*channel_index_0" scripts/dmx_fixture_runtime.gd
require_pattern "primary_slot_index" scripts/dmx_fixture_runtime.gd
require_pattern "slots.is_empty" scripts/dmx_fixture_runtime.gd
require_pattern "skip_gobo_projection" scripts/runtime/fixture_light_apply_service.gd
require_pattern "skip_gobo_projection" scripts/load_scene.gd
require_pattern "peraviz_gobo_texture" scripts/load_scene.gd
require_pattern "peraviz_last_beam_gobo_consumed" scripts/beam_renderers/legacy_cone_beam_renderer.gd
require_pattern "peraviz_last_beam_gobo_consumed" scripts/beam_renderers/volumetric_gobo_prism_shape_provider.gd
require_pattern "build_beam_mesh\(gobo_texture" scripts/beam_renderers/legacy_cone_beam_renderer.gd
require_pattern "build_beam_mesh\(gobo_texture" scripts/beam_renderers/volumetric_gobo_prism_shape_provider.gd
require_pattern "DmxGoboControlsResolverScript" scripts/fixture_gobo_projector.gd
require_pattern "DmxGoboControlsResolverScript" scripts/runtime/fixture_light_apply_service.gd
require_pattern "_live_visual_gobo_source_wheels" scripts/dmx_fixture_runtime.gd
require_pattern "_append_native_zoom_binding" scripts/dmx_fixture_runtime.gd
require_pattern "reserve_gobo_wheel_channels_from_zoom" native/src/dmx/fixture_dmx_binding.cpp
require_pattern "capabilities" tests/gdscript/test_dmx_gobo_controls_resolver.gd
require_pattern "gobo_runtime_bindings" tests/gdscript/test_dmx_gobo_controls_resolver.gd
require_pattern "should resolve exactly one source wheel" tests/gdscript/test_dmx_gobo_controls_resolver.gd
require_pattern "should fall back to 8-bit zoom" tests/gdscript/test_dmx_gobo_controls_resolver.gd

echo "Live visual-frame gobo bridge invariants are present."
