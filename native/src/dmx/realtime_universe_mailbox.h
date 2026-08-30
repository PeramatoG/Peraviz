#pragma once

#include "dmx_universe_cache.h"
#include "realtime_subscription.h"

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

namespace peraviz::dmx {

struct RealtimeMailboxStats {
    uint64_t relevant_packets = 0;
    uint64_t irrelevant_packets = 0;
    uint64_t unchanged_relevant_packets = 0;
    uint64_t state_updates = 0;
    uint64_t coalesced_states = 0;
};

class RealtimeUniverseMailbox {
public:
    RealtimeUniverseMailbox();
    void set_subscription(std::shared_ptr<const RealtimeSubscription> subscription);
    bool publish(uint16_t universe_id, const uint8_t *data, uint16_t length, uint8_t sequence, uint64_t now_us);
    std::vector<uint16_t> dirty_universes() const;
    bool consume(uint16_t universe_id, DmxFrame &out_frame);
    bool held(uint16_t universe_id, DmxFrame &out_frame) const;
    std::vector<DmxFrame> held_states() const;
    RealtimeMailboxStats stats() const;

private:
    struct Slot {
        mutable std::mutex mutex;
        DmxFrame held;
        bool initialized = false;
        std::atomic<bool> dirty {false};
    };
    std::shared_ptr<const RealtimeSubscription> subscription_;
    std::array<std::unique_ptr<Slot>, kArtNetUniverseCount> slots_ {};
    mutable std::mutex setup_mutex_;
    std::atomic<uint64_t> relevant_packets_ {0};
    std::atomic<uint64_t> irrelevant_packets_ {0};
    std::atomic<uint64_t> unchanged_relevant_packets_ {0};
    std::atomic<uint64_t> state_updates_ {0};
    std::atomic<uint64_t> coalesced_states_ {0};
};

} // namespace peraviz::dmx
