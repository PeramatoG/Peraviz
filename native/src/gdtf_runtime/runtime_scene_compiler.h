#pragma once

#include "runtime/visual_runtime_types.h"
#include "scene_model.h"
#include "gdtf_runtime/auto_span_policy.h"

namespace peraviz::gdtf_runtime {

runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset,
    const RuntimeRoutingOptions &routing = {}, FixtureTypeCache *cache = nullptr);

} // namespace peraviz::gdtf_runtime
