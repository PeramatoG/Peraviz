#include "realtime_subscription.h"

#include <algorithm>

namespace peraviz::dmx {

// Compiles universe membership and relevant DMX offsets into immutable constant-time lookup tables.
std::shared_ptr<const RealtimeSubscription> RealtimeSubscription::build(
    const std::vector<std::pair<uint16_t, std::vector<uint16_t>>> &offsets_by_universe) {
    std::shared_ptr<RealtimeSubscription> result(new RealtimeSubscription());
    for (const auto &entry : offsets_by_universe) {
        if (entry.first >= kArtNetUniverseCount) {
            continue;
        }
        OffsetMask &mask = result->offsets_[entry.first];
        for (const uint16_t offset : entry.second) {
            if (offset < kDmxSlotCount) {
                mask.set(offset);
            }
        }
        if (mask.any() && !result->used_.test(entry.first)) {
            result->used_.set(entry.first);
            result->universes_.push_back(entry.first);
        }
    }
    std::sort(result->universes_.begin(), result->universes_.end());
    return result;
}

// Reports whether a universe participates in the compiled scene patch.
bool RealtimeSubscription::contains(uint16_t universe_id) const {
    return universe_id < kArtNetUniverseCount && used_.test(universe_id);
}

// Returns the immutable relevant-slot mask for one universe.
const RealtimeSubscription::OffsetMask &RealtimeSubscription::offsets(uint16_t universe_id) const {
    static const OffsetMask empty;
    return universe_id < kArtNetUniverseCount ? offsets_[universe_id] : empty;
}

// Returns the sorted set of universes used by the compiled scene.
const std::vector<uint16_t> &RealtimeSubscription::universes() const {
    return universes_;
}

} // namespace peraviz::dmx
