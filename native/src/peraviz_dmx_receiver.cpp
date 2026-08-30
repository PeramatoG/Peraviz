#include "peraviz_dmx_receiver.h"
#include "runtime/peraviz_visual_runtime_godot.h"
#include "dmx/realtime_subscription.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <vector>

namespace godot {

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
    ClassDB::bind_method(D_METHOD("configure_visual_runtime", "runtime"), &PeravizDmxReceiver::configure_visual_runtime);
    ClassDB::bind_method(D_METHOD("pump_visual_runtime", "runtime"), &PeravizDmxReceiver::pump_visual_runtime);
    ClassDB::bind_method(D_METHOD("set_monitor_capture_enabled", "enabled"), &PeravizDmxReceiver::set_monitor_capture_enabled);
    ClassDB::bind_method(D_METHOD("record_godot_apply_completion"), &PeravizDmxReceiver::record_godot_apply_completion);
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
    out["accepted_artdmx_per_sec"] = static_cast<int64_t>(stats.accepted_artdmx_per_second);
    out["packets_per_sec"] = static_cast<int64_t>(stats.accepted_artdmx_per_second); // Deprecated compatibility alias.
    out["total_packets"] = static_cast<int64_t>(stats.valid_artdmx_accepted); // Deprecated compatibility alias.
    out["packets_received"] = static_cast<int64_t>(stats.packets_received);
    out["valid_artdmx_packets"] = static_cast<int64_t>(stats.valid_artdmx_packets);
    out["packets_parsed"] = static_cast<int64_t>(stats.valid_artdmx_packets); // Deprecated compatibility alias.
    out["malformed_packets"] = static_cast<int64_t>(stats.packets_ignored_malformed);
    out["out_of_order_dropped"] = static_cast<int64_t>(stats.packets_dropped_out_of_order);
    out["drain_wake_count"] = static_cast<int64_t>(stats.drain_wake_count);
    out["max_datagrams_drained_per_wake"] = static_cast<int64_t>(stats.max_datagrams_drained_per_wake);
    out["overload_dropped"] = static_cast<int64_t>(0); // Deprecated compatibility alias; the drain loop does not infer packet loss.
    out["valid_artdmx_accepted"] = static_cast<int64_t>(stats.valid_artdmx_accepted);
    out["frames_written"] = static_cast<int64_t>(stats.valid_artdmx_accepted); // Deprecated compatibility alias.
    out["source_changes"] = static_cast<int64_t>(stats.source_changes);
    out["relevant_packets"] = static_cast<int64_t>(stats.relevant_packets);
    out["irrelevant_packets"] = static_cast<int64_t>(stats.irrelevant_packets);
    out["relevant_unchanged_packets"] = static_cast<int64_t>(stats.relevant_unchanged_packets);
    out["relevant_state_updates"] = static_cast<int64_t>(stats.relevant_state_updates);
    out["mailbox_overwrites"] = static_cast<int64_t>(stats.mailbox_overwrites);
    out["scene_dirty_states_consumed"] = static_cast<int64_t>(stats.scene_dirty_states_consumed);
    out["monitor_payload_captures"] = static_cast<int64_t>(stats.monitor_payload_captures);
    out["monitor_payload_skipped_budget"] = static_cast<int64_t>(stats.monitor_payload_skipped_budget);
    out["scene_states_consumed"] = static_cast<int64_t>(scene_states_consumed_);
    out["production_raw_bridge_bytes"] = static_cast<int64_t>(0);
    out["rx_to_native_p50_us"] = static_cast<int64_t>(latency_percentile(rx_to_native_buckets_, 0.50));
    out["rx_to_native_p95_us"] = static_cast<int64_t>(latency_percentile(rx_to_native_buckets_, 0.95));
    out["rx_to_native_max_us"] = static_cast<int64_t>(rx_to_native_max_us_);
    out["native_to_apply_p50_us"] = static_cast<int64_t>(latency_percentile(native_to_apply_buckets_, 0.50));
    out["native_to_apply_p95_us"] = static_cast<int64_t>(latency_percentile(native_to_apply_buckets_, 0.95));
    out["native_to_apply_max_us"] = static_cast<int64_t>(native_to_apply_max_us_);
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

// Installs the visual runtime's authoritative compiled source interests in the receiver mailbox.
bool PeravizDmxReceiver::configure_visual_runtime(Ref<PeravizVisualRuntime> runtime) {
    if (runtime.is_null()) return false;
    const peraviz::runtime::RealtimePumpResult result = coordinator_.install_subscription(runtime->native_core(), receiver_->realtime_mailbox());
    rehydrated_states_pending_ = result.states_submitted;
    const uint64_t now_us = now_microseconds();
    if (result.oldest_receive_us > 0 && now_us >= result.oldest_receive_us) observe_latency(rx_to_native_buckets_, now_us - result.oldest_receive_us, rx_to_native_max_us_);
    return true;
}

// Pumps deduplicated latest universe states directly between native receiver and visual runtime cores.
int PeravizDmxReceiver::pump_visual_runtime(Ref<PeravizVisualRuntime> runtime) {
    if (runtime.is_null()) return 0;
    int consumed = rehydrated_states_pending_;
    rehydrated_states_pending_ = 0;
    const peraviz::runtime::RealtimePumpResult result = coordinator_.pump(runtime->native_core(), receiver_->realtime_mailbox());
    consumed += result.states_submitted;
    const uint64_t now_us = now_microseconds();
    if (result.oldest_receive_us > 0 && now_us >= result.oldest_receive_us) observe_latency(rx_to_native_buckets_, now_us - result.oldest_receive_us, rx_to_native_max_us_);
    scene_states_consumed_ += static_cast<uint64_t>(consumed);
    if (consumed > 0) last_native_pump_us_ = now_microseconds();
    return consumed;
}

// Controls optional all-universe full-payload capture for the Technical Monitor.
void PeravizDmxReceiver::set_monitor_capture_enabled(bool enabled) {
    receiver_->set_monitor_capture_enabled(enabled);
}

// Records the bounded native-frame-to-Godot-apply age after renderer mutation completes.
void PeravizDmxReceiver::record_godot_apply_completion() {
    const uint64_t now_us = now_microseconds();
    if (last_native_pump_us_ > 0 && now_us >= last_native_pump_us_) {
        observe_latency(native_to_apply_buckets_, now_us - last_native_pump_us_, native_to_apply_max_us_);
        last_native_pump_us_ = 0;
    }
}

// Adds a latency sample to a bounded power-of-two microsecond histogram.
void PeravizDmxReceiver::observe_latency(std::array<uint64_t, 32> &buckets, uint64_t value_us, uint64_t &maximum_us) {
    size_t bucket = 0;
    uint64_t upper = 1;
    while (bucket + 1 < buckets.size() && value_us > upper) { ++bucket; upper <<= 1U; }
    ++buckets[bucket];
    maximum_us = std::max(maximum_us, value_us);
}

// Estimates one percentile from a bounded power-of-two microsecond histogram.
uint64_t PeravizDmxReceiver::latency_percentile(const std::array<uint64_t, 32> &buckets, double percentile) {
    uint64_t total = 0;
    for (const uint64_t count : buckets) total += count;
    if (total == 0) return 0;
    const uint64_t target = static_cast<uint64_t>(std::ceil(static_cast<double>(total) * percentile));
    uint64_t cumulative = 0;
    for (size_t index = 0; index < buckets.size(); ++index) {
        cumulative += buckets[index];
        if (cumulative >= target) return uint64_t {1} << index;
    }
    return uint64_t {1} << (buckets.size() - 1);
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
    out["source_ipv4"] = static_cast<int64_t>(metadata.source_ipv4);
    out["source_port"] = static_cast<int64_t>(metadata.source_port);
    return out;
}


// Returns a monotonic timestamp in microseconds.
uint64_t PeravizDmxReceiver::now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace godot
