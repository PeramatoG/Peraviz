#pragma once

#include "dmx_universe_cache.h"

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <vector>

namespace peraviz::dmx {

class DmxNetworkMetadataCache {
public:
    DmxNetworkMetadataCache();
    void observe(uint16_t universe, uint16_t length, uint8_t sequence, uint64_t now_us, uint32_t source_ipv4, uint16_t source_port);
    bool get(uint16_t universe, DmxUniverseMetadata &metadata) const;
    std::vector<uint16_t> active(uint64_t now_us, uint64_t window_us) const;
    size_t slot_count() const;
    size_t approximate_bytes() const;

private:
    struct Slot {
        std::atomic<uint16_t> length {0};
        std::atomic<uint64_t> last_rx_us {0};
        std::atomic<uint32_t> packets {0};
        std::atomic<uint8_t> sequence {0};
        std::atomic<uint32_t> source_ipv4 {0};
        std::atomic<uint16_t> source_port {0};
    };
    std::array<std::unique_ptr<Slot>, 32768> slots_ {};
    mutable std::shared_mutex slots_mutex_;
    mutable std::mutex active_mutex_;
    std::vector<uint16_t> active_ids_;
    std::atomic<size_t> slot_count_ {0};
};

} // namespace peraviz::dmx
