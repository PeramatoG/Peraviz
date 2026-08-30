#include "realtime_universe_mailbox.h"

#include <algorithm>
#include <cstring>

namespace peraviz::dmx {

// Creates an empty latest-state mailbox with no scene subscription.
RealtimeUniverseMailbox::RealtimeUniverseMailbox() = default;

// Atomically replaces the subscription and retires every queued token from the previous generation.
void RealtimeUniverseMailbox::set_subscription(std::shared_ptr<const RealtimeSubscription> subscription) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    const auto previous = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    ++subscription_generation_;
    dirty_head_ = 0;
    dirty_count_ = 0;
    for (size_t universe = 0; universe < slots_.size(); ++universe) {
        Slot *slot = slots_[universe].get();
        const bool now_used = subscription && subscription->contains(static_cast<uint16_t>(universe));
        if (!now_used) {
            if (slot) { slot->dirty = false; slot->queued = false; slot->generation = subscription_generation_; }
            continue;
        }
        if (!slot) {
            slots_[universe] = std::make_unique<Slot>();
            slot = slots_[universe].get();
        }
        const bool has_new_offsets = !previous || !previous->contains(static_cast<uint16_t>(universe)) ||
            (subscription->offsets(static_cast<uint16_t>(universe)) & ~previous->offsets(static_cast<uint16_t>(universe))).any();
        if (has_new_offsets) slot->initialized = false;
        slot->dirty = false;
        slot->queued = false;
        slot->generation = subscription_generation_;
    }
    std::atomic_store_explicit(&subscription_, std::move(subscription), std::memory_order_release);
}

// Enqueues one bounded generation-tagged dirty token for a clean-to-dirty transition.
void RealtimeUniverseMailbox::enqueue_dirty_locked(uint16_t universe, Slot &slot) {
    if (slot.queued || dirty_count_ >= dirty_tokens_.size()) return;
    const size_t tail = (dirty_head_ + dirty_count_) % dirty_tokens_.size();
    slot.token_id = ++next_token_id_;
    dirty_tokens_[tail] = {universe, slot.generation, slot.token_id};
    ++dirty_count_;
    slot.queued = true;
}

// Publishes only changed relevant slots and queues at most one token per dirty universe.
bool RealtimeUniverseMailbox::publish(uint16_t universe_id, const uint8_t *data, uint16_t length, uint8_t sequence, uint64_t now_us) {
    if (data == nullptr) {
        irrelevant_packets_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    std::lock_guard<std::mutex> lock(state_mutex_);
    const auto subscription = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    if (!subscription || !subscription->contains(universe_id)) {
        irrelevant_packets_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    relevant_packets_.fetch_add(1, std::memory_order_relaxed);
    Slot *slot = slots_[universe_id].get();
    if (!slot || slot->generation != subscription_generation_) return false;
    const uint16_t safe_length = std::min<uint16_t>(length, kDmxSlotCount);
    bool changed = !slot->initialized;
    if (!changed) {
        const auto &mask = subscription->offsets(universe_id);
        for (size_t offset = 0; offset < mask.size(); ++offset) {
            if (!mask.test(offset)) continue;
            const uint8_t incoming = offset < safe_length ? data[offset] : 0;
            const uint8_t previous = offset < slot->held.length ? slot->held.data[offset] : 0;
            if (incoming != previous) { changed = true; break; }
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
    if (slot->dirty) {
        coalesced_states_.fetch_add(1, std::memory_order_relaxed);
    } else {
        slot->dirty = true;
        enqueue_dirty_locked(universe_id, *slot);
    }
    state_updates_.fetch_add(1, std::memory_order_relaxed);
    return true;
}

// Consumes one generation-valid token while holding snapshot and dirty ownership atomically.
bool RealtimeUniverseMailbox::consume_token_locked(const DirtyToken &token, DmxFrame &out_frame) {
    Slot *slot = slots_[token.universe].get();
    if (!slot || slot->generation != token.generation || slot->token_id != token.token_id || !slot->dirty || !slot->queued) return false;
    out_frame = slot->held;
    slot->dirty = false;
    slot->queued = false;
    dirty_states_consumed_.fetch_add(1, std::memory_order_relaxed);
    return true;
}

// Drains only queued dirty IDs and snapshots each latest state exactly once.
std::vector<DmxFrame> RealtimeUniverseMailbox::consume_dirty_frames() {
    size_t tokens_to_consume = 0;
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        tokens_to_consume = dirty_count_;
    }
    std::vector<DmxFrame> frames;
    frames.reserve(tokens_to_consume);
    for (size_t index = 0; index < tokens_to_consume; ++index) {
        std::lock_guard<std::mutex> lock(state_mutex_);
        if (dirty_count_ == 0) break;
        const DirtyToken token = dirty_tokens_[dirty_head_];
        dirty_head_ = (dirty_head_ + 1) % dirty_tokens_.size();
        --dirty_count_;
        DmxFrame frame;
        if (consume_token_locked(token, frame)) frames.push_back(frame);
    }
    return frames;
}


// Copies the latest held state independently of dirty consumption.
bool RealtimeUniverseMailbox::held(uint16_t universe_id, DmxFrame &out_frame) const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    const Slot *slot = universe_id < slots_.size() ? slots_[universe_id].get() : nullptr;
    if (!slot || !slot->initialized) return false;
    const auto subscription = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    if (!subscription || !subscription->contains(universe_id) || slot->generation != subscription_generation_) return false;
    out_frame = slot->held;
    return true;
}

// Copies all fresh held snapshots covered by the current immutable subscription.
std::vector<DmxFrame> RealtimeUniverseMailbox::held_states() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    std::vector<DmxFrame> result;
    const auto subscription = std::atomic_load_explicit(&subscription_, std::memory_order_acquire);
    if (!subscription) return result;
    result.reserve(subscription->universes().size());
    for (const uint16_t universe : subscription->universes()) {
        const Slot *slot = slots_[universe].get();
        if (slot && slot->initialized && slot->generation == subscription_generation_) result.push_back(slot->held);
    }
    return result;
}

// Returns the number of queued generation-valid dirty IDs in constant time.
size_t RealtimeUniverseMailbox::pending_dirty_count() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return dirty_count_;
}

// Returns a stable snapshot of bounded realtime mailbox counters.
RealtimeMailboxStats RealtimeUniverseMailbox::stats() const {
    return {relevant_packets_.load(), irrelevant_packets_.load(), unchanged_relevant_packets_.load(), state_updates_.load(), coalesced_states_.load(), dirty_states_consumed_.load()};
}

} // namespace peraviz::dmx
