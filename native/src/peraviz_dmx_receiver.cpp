#include "peraviz_dmx_receiver.h"

#include <algorithm>
#include <chrono>
#include <cstring>

namespace godot {
namespace {

// Computes a stable hash for selected DMX channels only.
uint32_t compute_interest_hash(const peraviz::dmx::DmxFrame &frame, const PackedInt32Array &offsets) {
    uint32_t hash = 2166136261U;
    for (int64_t i = 0; i < offsets.size(); ++i) {
        const int64_t offset = offsets[i];
        const uint8_t value = offset >= 0 && offset < frame.length ? frame.data[static_cast<size_t>(offset)] : 0;
        hash ^= value;
        hash *= 16777619U;
        hash ^= static_cast<uint32_t>(offset);
        hash *= 16777619U;
    }
    return hash;
}

} // namespace

// Registers class methods so they are callable from Godot scripts.
void PeravizDmxReceiver::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "bind_ip", "port"), &PeravizDmxReceiver::start, DEFVAL(String("0.0.0.0")), DEFVAL(6454));
    ClassDB::bind_method(D_METHOD("stop"), &PeravizDmxReceiver::stop);
    ClassDB::bind_method(D_METHOD("is_running"), &PeravizDmxReceiver::is_running);
    ClassDB::bind_method(D_METHOD("get_last_error"), &PeravizDmxReceiver::get_last_error);
    ClassDB::bind_method(D_METHOD("get_active_universes", "active_window_ms"), &PeravizDmxReceiver::get_active_universes, DEFVAL(2000));
    ClassDB::bind_method(D_METHOD("get_stats"), &PeravizDmxReceiver::get_stats);
    ClassDB::bind_method(D_METHOD("get_universe_data", "universe_id"), &PeravizDmxReceiver::get_universe_data);
    ClassDB::bind_method(D_METHOD("get_universe_metadata", "universe_id"), &PeravizDmxReceiver::get_universe_metadata);
    ClassDB::bind_method(D_METHOD("get_changed_universe_frames", "last_counters"), &PeravizDmxReceiver::get_changed_universe_frames);
}

// Initializes the wrapper with a dedicated Art-Net receiver instance.
PeravizDmxReceiver::PeravizDmxReceiver()
    : receiver_(std::make_unique<peraviz::dmx::ArtNetReceiver>()) {
}

// Constructs the Godot-facing DMX receiver wrapper.
PeravizDmxReceiver::~PeravizDmxReceiver() {
    stop();
}

// Starts the receiver thread and begins listening for Art-Net packets.
bool PeravizDmxReceiver::start(const String &bind_ip, int port) {
    const int safe_port = std::max(1, std::min(port, 65535));
    return receiver_->start(std::string(bind_ip.utf8().get_data()), static_cast<uint16_t>(safe_port));
}

// Stops the receiver thread and closes the listening socket.
void PeravizDmxReceiver::stop() {
    receiver_->stop();
}

// Returns whether the receiver background loop is currently running.
bool PeravizDmxReceiver::is_running() const {
    return receiver_->is_running();
}

// Returns the last runtime error reported by the receiver.
String PeravizDmxReceiver::get_last_error() const {
    return String(receiver_->get_last_error().c_str());
}

// Returns the list of universes that currently have cached data.
PackedInt32Array PeravizDmxReceiver::get_active_universes(int active_window_ms) const {
    const uint64_t safe_window_us = static_cast<uint64_t>(std::max(active_window_ms, 0)) * 1000ULL;
    const peraviz::dmx::ArtNetReceiverStats stats = receiver_->get_stats(now_microseconds(), safe_window_us);

    PackedInt32Array universe_array;
    universe_array.resize(static_cast<int64_t>(stats.active_universes.size()));
    for (int64_t i = 0; i < universe_array.size(); ++i) {
        universe_array[i] = stats.active_universes[static_cast<size_t>(i)];
    }
    return universe_array;
}

// Returns runtime counters collected by the receiver.
Dictionary PeravizDmxReceiver::get_stats() const {
    const uint64_t now_us = now_microseconds();
    const peraviz::dmx::ArtNetReceiverStats stats = receiver_->get_stats(now_us, 2000ULL * 1000ULL);

    Dictionary out;
    out["running"] = stats.running;
    out["packets_per_sec"] = static_cast<int64_t>(stats.packets_per_second);
    out["total_packets"] = static_cast<int64_t>(stats.total_packets);
    out["packets_received"] = static_cast<int64_t>(stats.packets_received);
    out["packets_parsed"] = static_cast<int64_t>(stats.packets_parsed);
    out["malformed_packets"] = static_cast<int64_t>(stats.packets_ignored_malformed);
    out["out_of_order_dropped"] = static_cast<int64_t>(stats.packets_dropped_out_of_order);
    out["overload_dropped"] = static_cast<int64_t>(stats.packets_dropped_by_overload);
    out["frames_written"] = static_cast<int64_t>(stats.frames_written);
    out["source_changes"] = static_cast<int64_t>(stats.source_changes);
    out["active_slot_count"] = static_cast<int64_t>(stats.active_slot_count);
    out["approx_cache_bytes"] = static_cast<int64_t>(stats.approximate_cache_bytes);
    PackedInt32Array active_universes;
    active_universes.resize(static_cast<int64_t>(stats.active_universes.size()));
    for (int64_t i = 0; i < active_universes.size(); ++i) {
        active_universes[i] = stats.active_universes[static_cast<size_t>(i)];
    }
    out["active_universes"] = active_universes;

    int64_t last_packet_ms_ago = -1;
    if (stats.last_packet_us > 0 && now_us >= stats.last_packet_us) {
        last_packet_ms_ago = static_cast<int64_t>((now_us - stats.last_packet_us) / 1000ULL);
    }
    out["last_packet_ms_ago"] = last_packet_ms_ago;
    return out;
}

// Returns the latest DMX channel data for a universe as an array.
PackedByteArray PeravizDmxReceiver::get_universe_data(int universe_id) const {
    PackedByteArray bytes;
    if (universe_id < 0 || universe_id > 32767) {
        return bytes;
    }

    peraviz::dmx::DmxFrame frame;
    if (!receiver_->try_get_frame(static_cast<uint16_t>(universe_id), frame)) {
        return bytes;
    }

    bytes.resize(frame.length);
    for (int64_t i = 0; i < frame.length; ++i) {
        bytes[i] = frame.data[static_cast<size_t>(i)];
    }
    return bytes;
}


// Returns metadata for one universe without copying its DMX payload.
Dictionary PeravizDmxReceiver::get_universe_metadata(int universe_id) const {
    Dictionary out;
    if (universe_id < 0 || universe_id > 32767) {
        return out;
    }

    peraviz::dmx::DmxUniverseMetadata metadata;
    if (!receiver_->try_get_metadata(static_cast<uint16_t>(universe_id), metadata)) {
        return out;
    }

    out["universe_id"] = static_cast<int64_t>(metadata.universe_id);
    out["counter"] = static_cast<int64_t>(metadata.counter);
    out["length"] = static_cast<int64_t>(metadata.length);
    out["last_rx_us"] = static_cast<int64_t>(metadata.last_rx_us);
    out["sequence"] = static_cast<int64_t>(metadata.sequence);
    out["content_hash"] = static_cast<int64_t>(metadata.content_hash);
    return out;
}

// Returns only universe frames whose counters or content hashes differ from caller-provided state.
Dictionary PeravizDmxReceiver::get_changed_universe_frames(const Dictionary &last_counters) const {
    Dictionary out;
    const Array universe_keys = last_counters.keys();
    for (int64_t i = 0; i < universe_keys.size(); ++i) {
        const Variant key = universe_keys[i];
        const int universe_id = static_cast<int>(static_cast<int64_t>(key));
        if (universe_id < 0 || universe_id > 32767) {
            continue;
        }

        peraviz::dmx::DmxFrame frame;
        if (!receiver_->try_get_frame(static_cast<uint16_t>(universe_id), frame)) {
            continue;
        }
        const Variant last_state = last_counters[key];
        int64_t interest_hash = -1;
        if (last_state.get_type() == Variant::DICTIONARY) {
            const Dictionary last_state_dict = static_cast<Dictionary>(last_state);
            const Variant interest_offsets_value = last_state_dict.get("interest_offsets", PackedInt32Array());
            if (interest_offsets_value.get_type() == Variant::PACKED_INT32_ARRAY) {
                const PackedInt32Array interest_offsets = static_cast<PackedInt32Array>(interest_offsets_value);
                interest_hash = static_cast<int64_t>(compute_interest_hash(frame, interest_offsets));
                if (interest_hash == static_cast<int64_t>(last_state_dict.get("interest_hash", -1))) {
                    continue;
                }
            } else if (static_cast<int64_t>(frame.content_hash) == static_cast<int64_t>(last_state_dict.get("content_hash", -1))) {
                continue;
            }
        } else if (static_cast<int64_t>(frame.counter) == static_cast<int64_t>(last_state)) {
            continue;
        }

        PackedByteArray bytes;
        bytes.resize(frame.length);
        if (frame.length > 0) {
            std::memcpy(bytes.ptrw(), frame.data.data(), static_cast<size_t>(frame.length));
        }

        Dictionary entry;
        entry["data"] = bytes;
        entry["counter"] = static_cast<int64_t>(frame.counter);
        entry["length"] = static_cast<int64_t>(frame.length);
        entry["last_rx_us"] = static_cast<int64_t>(frame.last_rx_us);
        entry["sequence"] = static_cast<int64_t>(frame.sequence);
        entry["content_hash"] = static_cast<int64_t>(frame.content_hash);
        entry["interest_hash"] = interest_hash;
        out[universe_id] = entry;
    }
    return out;
}

// Returns a monotonic timestamp in microseconds.
uint64_t PeravizDmxReceiver::now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace godot
