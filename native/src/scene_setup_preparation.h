#pragma once
#include "scene_model.h"
#include "asset_cache.h"
#include <atomic>
#include <memory>
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
// Progress is setup-only and monotonic; the main thread polls without sharing mutable scene data.
enum class SceneSetupPhase : int32_t { ArchiveGeometry = 0, CompileMode, ControlGroups, RenderGroups, Complete };
using SceneSetupProgress = std::shared_ptr<std::atomic<SceneSetupPhase>>;
SceneSetupPreparation prepare_scene_setup(const std::string &path, int universe_offset, SceneSetupProgress progress = {}, GdtfModelDetail model_detail = GdtfModelDetail::Default);
}
