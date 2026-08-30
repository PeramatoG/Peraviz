#include "runtime/peraviz_visual_runtime.h"

namespace peraviz::runtime {

// Exposes the installed native source-program interests for setup-time receiver subscription.
std::vector<std::pair<uint16_t, std::vector<uint16_t>>> PeravizVisualRuntimeCore::realtime_interest_offsets() const {
    std::vector<std::pair<uint16_t, std::vector<uint16_t>>> result;
    result.reserve(universes_.size());
    for (const auto &[universe_id, universe] : universes_) {
        std::vector<uint16_t> offsets;
        offsets.reserve(universe.interest_offsets.size());
        for (const int offset : universe.interest_offsets) {
            if (offset >= 0 && offset < 512) offsets.push_back(static_cast<uint16_t>(offset));
        }
        result.push_back({static_cast<uint16_t>(universe_id), std::move(offsets)});
    }
    return result;
}

} // namespace peraviz::runtime
