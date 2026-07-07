#!/usr/bin/env bash
set -euo pipefail
rg -q 'SectionedVisualFrame' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'descriptors' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'integers' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'floats' native/src/runtime/peraviz_visual_runtime_godot.cpp
rg -q 'SectionedVisualFrameApplier' scripts/dmx_fixture_runtime.gd scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd
if rg -q 'PackedFloat32Array = _native_visual_runtime\.consume_latest_visual_frame|visual_frame\[0\]' scripts/dmx_fixture_runtime.gd; then
  echo 'Legacy fixed-row live GDScript consume path is still referenced.' >&2
  exit 1
fi
if rg -q 'kVisualChannelCount = 13|fixed 25-float' native/src/runtime/peraviz_visual_runtime.cpp native/src/runtime/peraviz_visual_runtime_godot.cpp scripts/runtime/visual_sections; then
  echo 'Legacy fixed-row live protocol constants are present in the active sectioned path.' >&2
  exit 1
fi
