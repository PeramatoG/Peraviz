#include "dmx_universe_cache.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <shared_mutex>

namespace peraviz::dmx {

// Creates a cache for the latest DMX frame per universe.
DmxUniverseCache::DmxUniverseCache() {
    slots_.resize(32768);
}

// Writes the latest DMX frame for one universe into the double-buffered slot.
void DmxUniverseCache::write_frame(uint16_t universe_id,
                                   const uint8_t *data,
                                   uint16_t length,
                                   uint8_t sequence,
                                   uint64_t now_us) {
    if (universe_id >= slots_.size() || data == nullptr) {
        return;
    }

    UniverseSlot *slot = get_or_create_slot(universe_id);
    if (slot == nullptr) {
        return;
    }

    const uint16_t safe_length = std::min<uint16_t>(length, 512);
    std::unique_lock<std::shared_mutex> frame_lock(slot->frame_mutex);
    const uint8_t current_front = slot->front_index.load(std::memory_order_relaxed);
    const uint8_t next_front = static_cast<uint8_t>(1 - current_front);

    if (safe_length > 0) {
        std::memcpy(slot->buffers[next_front].data(), data, safe_length);
    }

    slot->length.store(safe_length, std::memory_order_relaxed);
    slot->last_rx_us.store(now_us, std::memory_order_relaxed);
    slot->sequence.store(sequence, std::memory_order_relaxed);
    slot->counter.fetch_add(1, std::memory_order_relaxed);
    slot->front_index.store(next_front, std::memory_order_release);
}

// Tries to fetch the latest DMX frame for a universe.
bool DmxUniverseCache::try_get_frame(uint16_t universe_id, DmxFrame &out_frame) const {
    const UniverseSlot *slot = get_slot(universe_id);
    if (slot == nullptr) {
        return false;
    }

    std::shared_lock<std::shared_mutex> frame_lock(slot->frame_mutex);
    const uint8_t front_index = slot->front_index.load(std::memory_order_acquire);
    const uint16_t length = slot->length.load(std::memory_order_relaxed);

    out_frame.universe_id = universe_id;
    out_frame.length = length;
    if (length > 0) {
        std::memcpy(out_frame.data.data(), slot->buffers[front_index].data(), length);
    }
    out_frame.last_rx_us = slot->last_rx_us.load(std::memory_order_relaxed);
    out_frame.counter = slot->counter.load(std::memory_order_relaxed);
    out_frame.sequence = slot->sequence.load(std::memory_order_relaxed);
    return true;
}

// Tries to fetch metadata without copying the universe DMX payload.
bool DmxUniverseCache::try_get_metadata(uint16_t universe_id, DmxUniverseMetadata &out_metadata) const {
    const UniverseSlot *slot = get_slot(universe_id);
    if (slot == nullptr) {
        return false;
    }
    std::shared_lock<std::shared_mutex> frame_lock(slot->frame_mutex);
    out_metadata.universe_id = universe_id;
    out_metadata.length = slot->length.load(std::memory_order_relaxed);
    out_metadata.last_rx_us = slot->last_rx_us.load(std::memory_order_relaxed);
    out_metadata.counter = slot->counter.load(std::memory_order_relaxed);
    out_metadata.sequence = slot->sequence.load(std::memory_order_relaxed);
    return true;
}

// Returns the list of universes that currently have cached data.
std::vector<uint16_t> DmxUniverseCache::get_active_universes(uint64_t now_us, uint64_t active_window_us) const {
    std::vector<uint16_t> active;
    std::shared_lock<std::shared_mutex> lock(slots_mutex_);
    for (size_t universe_id = 0; universe_id < slots_.size(); ++universe_id) {
        const std::unique_ptr<UniverseSlot> &slot = slots_[universe_id];
        if (!slot) {
            continue;
        }
        const uint64_t last_rx_us = slot->last_rx_us.load(std::memory_order_relaxed);
        if (last_rx_us == 0 || now_us < last_rx_us) {
            continue;
        }
        if (now_us - last_rx_us <= active_window_us) {
            active.push_back(static_cast<uint16_t>(universe_id));
        }
    }
    return active;
}

// Returns the number of universe slots allocated by the cache.
size_t DmxUniverseCache::get_active_slot_count() const {
    return active_slot_count_.load(std::memory_order_relaxed);
}

// Returns an approximate byte size for allocated universe cache slots.
size_t DmxUniverseCache::get_approximate_cache_bytes() const {
    return get_active_slot_count() * sizeof(UniverseSlot);
}

// Returns an existing universe slot or creates a new one under exclusive ownership protection.
DmxUniverseCache::UniverseSlot *DmxUniverseCache::get_or_create_slot(uint16_t universe_id) {
    {
        std::shared_lock<std::shared_mutex> read_lock(slots_mutex_);
        const std::unique_ptr<UniverseSlot> &slot = slots_[universe_id];
        if (slot) {
            return slot.get();
        }
    }

    std::unique_lock<std::shared_mutex> write_lock(slots_mutex_);
    std::unique_ptr<UniverseSlot> &slot = slots_[universe_id];
    if (!slot) {
        slot = std::make_unique<UniverseSlot>();
        active_slot_count_.fetch_add(1, std::memory_order_relaxed);
    }
    return slot.get();
}

// Returns an existing universe slot while protecting the slot vector from concurrent creation.
const DmxUniverseCache::UniverseSlot *DmxUniverseCache::get_slot(uint16_t universe_id) const {
    if (universe_id >= slots_.size()) {
        return nullptr;
    }
    std::shared_lock<std::shared_mutex> lock(slots_mutex_);
    return slots_[universe_id].get();
}

} // namespace peraviz::dmx
