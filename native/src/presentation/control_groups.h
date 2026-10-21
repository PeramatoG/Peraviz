#pragma once
#include "runtime/visual_runtime_types.h"
#include <vector>

namespace peraviz::presentation {
// Setup-generation presentation membership; canonical physical IDs remain authoritative.
struct PresentationControlGroup {
    int32_t id = 0;
    std::vector<int32_t> physical_ids;
};
struct ControlGroupFallbacks {
    uint32_t dimmer = 0, color = 0, optics = 0, projector_gobo = 0, wheel = 0, scaling = 0, ambiguous = 0;
};
struct ControlGroupAnalysis {
    std::vector<PresentationControlGroup> groups;
    ControlGroupFallbacks fallbacks;
};
// A zero/unknown target is ambiguous; a known unrelated target never vetoes another Beam.
bool has_projector_dependency(const runtime::CompiledRuntimeScene &scene, const runtime::CompiledBeamOpticalProfile &beam);
bool has_wheel_dependency(const runtime::CompiledRuntimeScene &scene, const runtime::CompiledBeamOpticalProfile &beam);
ControlGroupAnalysis analyze_control_groups(const runtime::CompiledRuntimeScene &scene);
std::vector<PresentationControlGroup> compile_control_groups(const runtime::CompiledRuntimeScene &scene);
} // namespace peraviz::presentation
