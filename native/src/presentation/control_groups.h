#pragma once
#include "runtime/visual_runtime_types.h"
#include <vector>

namespace peraviz::presentation {
// Setup-generation presentation membership; canonical physical IDs remain authoritative.
struct PresentationControlGroup {
    int32_t id = 0;
    std::vector<int32_t> physical_ids;
};
std::vector<PresentationControlGroup> compile_control_groups(const runtime::CompiledRuntimeScene &scene);
} // namespace peraviz::presentation
