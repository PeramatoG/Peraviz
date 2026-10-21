#pragma once
#include "runtime/visual_runtime_types.h"
#include <tuple>

namespace peraviz::presentation {
using WheelSetSignature = std::tuple<uint32_t, uint32_t, int32_t, double, double>;
using WheelControlSignature = std::tuple<int32_t, int32_t, int32_t, bool, float, std::vector<WheelSetSignature>>;
// Peraviz setup proof only: wheel selection remains canonical native Color/Wheel state.
struct WheelPresentationEligibility {
    std::vector<WheelControlSignature> controls;
    const char *rejection = nullptr;
    bool approximate = false;
    // A missing proof always retains individual presentation.
    bool supported() const { return rejection == nullptr; }
};
WheelPresentationEligibility analyze_wheel_presentation(const runtime::CompiledRuntimeScene &scene,
    const runtime::CompiledBeamOpticalProfile &beam);
}
