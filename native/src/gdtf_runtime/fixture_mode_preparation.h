#pragma once

#include "gdtf_runtime/runtime_scene_compiler.h"
#include "gdtf_scene_builder.h"
#include "presentation/render_emitter_groups.h"

namespace peraviz::gdtf_runtime {

struct FixtureModePreparation {
    SceneModel::FixturePatch patch;
    GdtfGeometryBuildResult geometry;
    runtime::CompiledRuntimeScene compiled;
    presentation::ControlGroupAnalysis controls;
    std::vector<presentation::RenderEmitterGroup> groups;
    std::vector<std::string> warnings;
    std::string error;
    bool reuse_geometry = false;
    bool unchanged = false;
};

FixtureModePreparation prepare_fixture_mode(
    const SceneModel &scene, const std::string &uuid, const std::string &name,
    const GdtfModeCatalog &catalog, GdtfModelDetail detail, int universe_offset,
    const RuntimeRoutingOptions &routing, FixtureTypeCache &cache);

} // namespace peraviz::gdtf_runtime
