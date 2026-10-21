#pragma once
#include "scene_model.h"
#ifdef PERAVIZ_ENABLE_DMX
#include "runtime/visual_runtime_types.h"
#include "presentation/render_emitter_groups.h"
#endif

namespace peraviz {
// Pure native result, transferred once from the single import task to the main thread.
struct SceneSetupPreparation {
    SceneModel model;
    int universe_offset = -1;
    double load_ms = 0, compile_ms = 0, controls_ms = 0, groups_ms = 0;
#ifdef PERAVIZ_ENABLE_DMX
    runtime::CompiledRuntimeScene compiled;
    presentation::ControlGroupAnalysis controls;
    std::vector<presentation::RenderEmitterGroup> groups;
#endif
};
SceneSetupPreparation prepare_scene_setup(const std::string &path, int universe_offset);
}
