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
    uint64_t dirty_states_consumed = 0;
};

class RealtimeUniverseMailbox {
public:
    RealtimeUniverseMailbox();
    void set_subscription(std::shared_ptr<const RealtimeSubscription> subscription);
    bool publish(uint16_t universe_id, const uint8_t *data, uint16_t length, uint8_t sequence, uint64_t now_us);
    std::vector<DmxFrame> consume_dirty_frames();
    bool held(uint16_t universe_id, DmxFrame &out_frame) const;
    std::vector<DmxFrame> held_states() const;
    size_t pending_dirty_count() const;
    RealtimeMailboxStats stats() const;

private:
    struct Slot {
        DmxFrame held;
        uint64_t generation = 0;
        bool initialized = false;
        bool dirty = false;
        bool queued = false;
        uint64_t token_id = 0;
    };
    struct DirtyToken {
        uint16_t universe = 0;
        uint64_t generation = 0;
        uint64_t token_id = 0;
    };

    void enqueue_dirty_locked(uint16_t universe, Slot &slot);
    bool consume_token_locked(const DirtyToken &token, DmxFrame &out_frame);

    std::shared_ptr<const RealtimeSubscription> subscription_;
    std::array<std::unique_ptr<Slot>, kArtNetUniverseCount> slots_ {};
    mutable std::mutex state_mutex_;
    std::array<DirtyToken, kArtNetUniverseCount> dirty_tokens_ {};
    size_t dirty_head_ = 0;
    size_t dirty_count_ = 0;
    uint64_t subscription_generation_ = 0;
    uint64_t next_token_id_ = 0;
    std::atomic<uint64_t> relevant_packets_ {0};
    std::atomic<uint64_t> irrelevant_packets_ {0};
    std::atomic<uint64_t> unchanged_relevant_packets_ {0};
    std::atomic<uint64_t> state_updates_ {0};
    std::atomic<uint64_t> coalesced_states_ {0};
    std::atomic<uint64_t> dirty_states_consumed_ {0};
};

} // namespace peraviz::dmx
