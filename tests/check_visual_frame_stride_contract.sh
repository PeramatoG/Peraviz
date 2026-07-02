#!/usr/bin/env bash
set -euo pipefail

extract_cpp_const() {
  local name="$1"
  rg -o "constexpr int ${name} = [0-9]+" native/src/runtime/visual_frame_buffers.h | awk '{print $5}' | tr -d ';'
}

extract_gd_const() {
  local name="$1"
  local file="$2"
  rg -o "const ${name}: int = [0-9]+" "$file" | awk '{print $5}' | tr -d ';'
}

cpp_header="$(extract_cpp_const kVisualFrameHeaderCount)"
cpp_channels="$(extract_cpp_const kVisualChannelCount)"
cpp_render="$(extract_cpp_const kVisualRenderValueCount)"
gd_header="$(extract_gd_const NATIVE_VISUAL_FRAME_HEADER_COUNT scripts/dmx_fixture_runtime.gd)"
gd_channels="$(extract_gd_const NATIVE_VISUAL_CHANNEL_COUNT scripts/dmx_fixture_runtime.gd)"
gd_render="$(extract_gd_const NATIVE_VISUAL_RENDER_VALUE_COUNT scripts/dmx_fixture_runtime.gd)"
light_header="$(extract_gd_const VISUAL_FRAME_HEADER_COUNT scripts/runtime/fixture_light_apply_service.gd)"
light_channels="$(extract_gd_const VISUAL_FRAME_CHANNEL_COUNT scripts/runtime/fixture_light_apply_service.gd)"
light_render="$(extract_gd_const VISUAL_FRAME_RENDER_VALUE_COUNT scripts/runtime/fixture_light_apply_service.gd)"

[[ "$cpp_header" == "$gd_header" && "$cpp_header" == "$light_header" ]] || { echo "Visual frame header count mismatch" >&2; exit 1; }
[[ "$cpp_channels" == "$gd_channels" && "$cpp_channels" == "$light_channels" ]] || { echo "Visual frame channel count mismatch" >&2; exit 1; }
[[ "$cpp_render" == "$gd_render" && "$cpp_render" == "$light_render" ]] || { echo "Visual frame render value count mismatch" >&2; exit 1; }
[[ $((cpp_header + cpp_channels + cpp_render)) -eq 25 ]] || { echo "Visual frame stride must remain 25" >&2; exit 1; }

echo "Visual frame stride contract is aligned."
