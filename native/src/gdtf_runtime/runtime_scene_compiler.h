#pragma once

#include "runtime/visual_runtime_types.h"
#include "scene_model.h"

namespace peraviz::gdtf_runtime {

runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset);

} // namespace peraviz::gdtf_runtime
