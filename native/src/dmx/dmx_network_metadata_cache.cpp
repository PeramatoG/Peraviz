#include "dmx_network_metadata_cache.h"

namespace peraviz::dmx {

// Creates an empty compact all-network metadata cache.
DmxNetworkMetadataCache::DmxNetworkMetadataCache() = default;

// Records cheap packet metadata without copying or hashing its DMX payload.
void DmxNetworkMetadataCache::observe(uint16_t universe, uint16_t length, uint8_t sequence, uint64_t now_us, uint32_t source_ipv4, uint16_t source_port) {
    Slot *slot = nullptr;
    {
        std::shared_lock<std::shared_mutex> lock(slots_mutex_);
        slot = slots_[universe].get();
    }
    if (!slot) {
        std::unique_lock<std::shared_mutex> lock(slots_mutex_);
        if (!slots_[universe]) {
            slots_[universe] = std::make_unique<Slot>();
            std::lock_guard<std::mutex> active_lock(active_mutex_);
            active_ids_.push_back(universe);
            slot_count_.fetch_add(1, std::memory_order_relaxed);
        }
        slot = slots_[universe].get();
    }
    slot->length.store(length, std::memory_order_relaxed);
    slot->sequence.store(sequence, std::memory_order_relaxed);
    slot->last_rx_us.store(now_us, std::memory_order_relaxed);
    slot->source_ipv4.store(source_ipv4, std::memory_order_relaxed);
    slot->source_port.store(source_port, std::memory_order_relaxed);
    slot->packets.fetch_add(1, std::memory_order_relaxed);
}

// Reads one universe's cheap status record without accessing a payload cache.
bool DmxNetworkMetadataCache::get(uint16_t universe, DmxUniverseMetadata &metadata) const {
    std::shared_lock<std::shared_mutex> lock(slots_mutex_);
    const Slot *slot = slots_[universe].get();
    if (!slot) return false;
    metadata.universe_id = universe;
    metadata.length = slot->length.load(std::memory_order_relaxed);
    metadata.last_rx_us = slot->last_rx_us.load(std::memory_order_relaxed);
    metadata.counter = slot->packets.load(std::memory_order_relaxed);
    metadata.sequence = slot->sequence.load(std::memory_order_relaxed);
    metadata.content_hash = 0;
    metadata.source_ipv4 = slot->source_ipv4.load(std::memory_order_relaxed);
    metadata.source_port = slot->source_port.load(std::memory_order_relaxed);
    return true;
}

// Returns recently observed universe IDs from compact metadata only.
std::vector<uint16_t> DmxNetworkMetadataCache::active(uint64_t now_us, uint64_t window_us) const {
    std::vector<uint16_t> ids;
    { std::lock_guard<std::mutex> lock(active_mutex_); ids = active_ids_; }
    std::vector<uint16_t> result;
    for (const uint16_t universe : ids) {
        DmxUniverseMetadata metadata;
        if (get(universe, metadata) && metadata.last_rx_us > 0 && now_us >= metadata.last_rx_us && now_us - metadata.last_rx_us <= window_us)
            result.push_back(universe);
    }
    return result;
}

// Returns the number of compact metadata slots allocated.
size_t DmxNetworkMetadataCache::slot_count() const { return slot_count_.load(std::memory_order_relaxed); }

// Returns an approximate allocation size for compact metadata slots.
size_t DmxNetworkMetadataCache::approximate_bytes() const { return slot_count() * sizeof(Slot); }

} // namespace peraviz::dmx
