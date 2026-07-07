#!/usr/bin/env bash
set -euo pipefail

rg -q 'SectionedVisualFrame' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'descriptors' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'integers' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'floats' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'SectionedVisualFrameApplier' scripts/dmx_fixture_runtime.gd scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd

if rg -q 'visual_frame_buffers\.h' native/src/runtime/peraviz_visual_runtime.h native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/visual_frame_schema.h; then
  echo 'Active sectioned runtime must not include legacy visual_frame_buffers.h.' >&2
  exit 1
fi
if rg -q 'kVisualChannelCount|VisualChannel|std::array<float,\s*kVisualChannelCount>' native/src/runtime/peraviz_visual_runtime.h native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/visual_frame_schema.h; then
  echo 'Active runtime still references the universal visual-channel row.' >&2
  exit 1
fi
if rg -q 'LEGACY_|apply_visual_frame_to_fixture|update_live_visual_gobo_from_section' scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd scripts/dmx_fixture_runtime.gd; then
  echo 'Sectioned Godot path still reconstructs or forwards the legacy fixed row.' >&2
  exit 1
fi
if rg -q 'PackedFloat32Array = _native_visual_runtime\.consume_latest_visual_frame|visual_frame\[0\]' scripts/dmx_fixture_runtime.gd; then
  echo 'Legacy fixed-row live GDScript consume path is still referenced.' >&2
  exit 1
fi
