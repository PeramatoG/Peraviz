#pragma once

#include <array>
#include <bitset>
#include <cstdint>
#include <memory>
#include <utility>
#include <vector>

namespace peraviz::dmx {

constexpr size_t kArtNetUniverseCount = 32768;
constexpr size_t kDmxSlotCount = 512;

class RealtimeSubscription {
public:
    using OffsetMask = std::bitset<kDmxSlotCount>;

    static std::shared_ptr<const RealtimeSubscription> build(
        const std::vector<std::pair<uint16_t, std::vector<uint16_t>>> &offsets_by_universe);
    bool contains(uint16_t universe_id) const;
    const OffsetMask &offsets(uint16_t universe_id) const;
    const std::vector<uint16_t> &universes() const;

private:
    std::bitset<kArtNetUniverseCount> used_;
    std::array<OffsetMask, kArtNetUniverseCount> offsets_ {};
    std::vector<uint16_t> universes_;
};

} // namespace peraviz::dmx
