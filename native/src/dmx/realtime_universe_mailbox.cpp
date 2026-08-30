#include "realtime_universe_mailbox.h"

#include <algorithm>
#include <cstring>

namespace peraviz::dmx {

// Creates an empty latest-state mailbox with no scene subscription.
RealtimeUniverseMailbox::RealtimeUniverseMailbox() = default;

// Atomically replaces the immutable scene subscription and preallocates its bounded universe slots.
void RealtimeUniverseMailbox::set_subscription(std::shared_ptr<const RealtimeSubscription> subscription) {
    std::lock_guard<std::mutex> lock(setup_mutex_);
    for (const uint16_t universe : subscription ? subscription->universes() : std::vector<uint16_t> {}) {
        if (!slots_[universe]) {
            slots_[universe] = std::make_unique<Slot>();
        }
    }
    std::atomic_store_explicit(&subscription_, std::move(subscription), std::memory_order_release);
}

// Publishes only changed relevant slots while retaining one latest held state per subscribed universe.
bool RealtimeUniverseMailbox::publish(uint16_t universe_id, const uint8_t *data, uint16_t length, uint8_t sequence, uint64_t now_us) {
    const auto subscription = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    if (!subscription || !subscription->contains(universe_id) || data == nullptr) {
        irrelevant_packets_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    relevant_packets_.fetch_add(1, std::memory_order_relaxed);
    Slot *slot = slots_[universe_id].get();
    if (!slot) {
        return false;
    }
    const uint16_t safe_length = std::min<uint16_t>(length, kDmxSlotCount);
    std::lock_guard<std::mutex> lock(slot->mutex);
    bool changed = !slot->initialized;
    if (!changed) {
        const auto &mask = subscription->offsets(universe_id);
        for (size_t offset = 0; offset < mask.size(); ++offset) {
            if (!mask.test(offset)) continue;
            const uint8_t incoming = offset < safe_length ? data[offset] : 0;
            const uint8_t previous = offset < slot->held.length ? slot->held.data[offset] : 0;
            if (incoming != previous) {
                changed = true;
                break;
            }
        }
    }
    slot->held.last_rx_us = now_us;
    slot->held.sequence = sequence;
    if (!changed) {
        unchanged_relevant_packets_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    slot->held.universe_id = universe_id;
    slot->held.length = safe_length;
    std::fill(slot->held.data.begin(), slot->held.data.end(), 0);
    std::memcpy(slot->held.data.data(), data, safe_length);
    ++slot->held.counter;
    slot->initialized = true;
    if (slot->dirty.exchange(true, std::memory_order_acq_rel)) {
        coalesced_states_.fetch_add(1, std::memory_order_relaxed);
    }
    state_updates_.fetch_add(1, std::memory_order_relaxed);
    return true;
}

// Returns deduplicated dirty universe identifiers by scanning only the compiled subscription.
std::vector<uint16_t> RealtimeUniverseMailbox::dirty_universes() const {
    std::vector<uint16_t> result;
    const auto subscription = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    if (!subscription) return result;
    for (const uint16_t universe : subscription->universes()) {
        const Slot *slot = slots_[universe].get();
        if (slot && slot->dirty.load(std::memory_order_acquire)) result.push_back(universe);
    }
    return result;
}

// Consumes one pending state without discarding its held rehydration snapshot.
bool RealtimeUniverseMailbox::consume(uint16_t universe_id, DmxFrame &out_frame) {
    Slot *slot = universe_id < slots_.size() ? slots_[universe_id].get() : nullptr;
    if (!slot || !slot->dirty.exchange(false, std::memory_order_acq_rel)) return false;
    std::lock_guard<std::mutex> lock(slot->mutex);
    out_frame = slot->held;
    return true;
}

// Copies the latest held state independently of dirty consumption.
bool RealtimeUniverseMailbox::held(uint16_t universe_id, DmxFrame &out_frame) const {
    const Slot *slot = universe_id < slots_.size() ? slots_[universe_id].get() : nullptr;
    if (!slot) return false;
    std::lock_guard<std::mutex> lock(slot->mutex);
    if (!slot->initialized) return false;
    out_frame = slot->held;
    return true;
}

// Returns a stable snapshot of bounded realtime mailbox counters.
RealtimeMailboxStats RealtimeUniverseMailbox::stats() const {
    return {relevant_packets_.load(), irrelevant_packets_.load(), unchanged_relevant_packets_.load(), state_updates_.load(), coalesced_states_.load()};
}

} // namespace peraviz::dmx
