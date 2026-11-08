#pragma once

#include "runtime/visual_runtime_types.h"
#include "scene_model.h"
#include <unordered_set>

namespace peraviz::gdtf_runtime {

// Peraviz setup overrides, keyed by stable MVR fixture UUID; canonical patches stay read-only.
struct RuntimeRoutingOptions {
    std::unordered_set<std::string> auto_span_fixture_uuids;
};

runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset,
    const RuntimeRoutingOptions &routing = {});

} // namespace peraviz::gdtf_runtime
