#include "scene_setup_preparation.h"
#include "mvr_scene_loader.h"
#include "scene_setup_options.h"
#ifdef PERAVIZ_ENABLE_DMX
#include "gdtf_runtime/runtime_scene_compiler.h"
#endif
#include <chrono>

namespace peraviz {
// Parses and classifies CPU-only data; no SceneTree, resources or RenderingServer access.
SceneSetupPreparation prepare_scene_setup(const std::string &path, int universe_offset, SceneSetupProgress progress, GdtfModelDetail model_detail) {
    using Clock = std::chrono::steady_clock;
    const auto elapsed = [](Clock::time_point start) { return std::chrono::duration<double, std::milli>(Clock::now()-start).count(); };
    SceneSetupPreparation out;
    out.universe_offset=universe_offset;
    auto start=Clock::now();
    out.model=load_mvr(path,false,false,model_detail);
    out.load_ms=elapsed(start);
#ifdef PERAVIZ_ENABLE_DMX
    start=Clock::now();
    if (progress) progress->store(SceneSetupPhase::CompileMode, std::memory_order_relaxed);
    out.compiled=gdtf_runtime::compile_runtime_scene(out.model,universe_offset);
    out.compile_ms=elapsed(start);
    const auto options=SceneSetupOptions::read();
    start=Clock::now();
    if (progress) progress->store(SceneSetupPhase::ControlGroups, std::memory_order_relaxed);
    out.controls=presentation::analyze_control_groups(out.compiled,options.indexed_classification);
    out.controls_ms=elapsed(start);
    start=Clock::now();
    if (progress) progress->store(SceneSetupPhase::RenderGroups, std::memory_order_relaxed);
    out.groups=presentation::compile_render_emitter_groups(out.compiled,out.model,out.controls.groups,options.indexed_classification);
    out.groups_ms=elapsed(start);
#endif
    if (progress) progress->store(SceneSetupPhase::Complete, std::memory_order_relaxed);
    return out;
}
}
