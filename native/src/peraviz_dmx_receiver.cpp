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
    ClassDB::bind_method(D_METHOD("record_godot_apply_completion", "captured_receive_us"), &PeravizDmxReceiver::record_godot_apply_completion,DEFVAL(0));
    ClassDB::bind_method(D_METHOD("set_performance_trace_enabled", "enabled"), &PeravizDmxReceiver::set_performance_trace_enabled);
    ClassDB::bind_method(D_METHOD("consume_interval_latency"), &PeravizDmxReceiver::consume_interval_latency);
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
    if (receiver_->is_running()) return true;
    rx_to_native_ = {};
    native_to_apply_ = {};
    rx_to_apply_ = {};
    last_native_pump_us_ = 0;
    oldest_pending_receive_us_ = 0;
    return receiver_->start(std::string(bind_ip.utf8().get_data()), static_cast<uint16_t>(safe_port));
}

// Stops the receiver thread and closes the listening socket.
void PeravizDmxReceiver::stop() {
    receiver_->stop();
    last_native_pump_us_ = 0;
    oldest_pending_receive_us_ = 0;
    rehydrated_states_pending_ = 0;
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
    append_latency(out, "rx_to_native", rx_to_native_.lifetime);
    append_latency(out, "native_to_apply", native_to_apply_.lifetime);
    append_latency(out, "rx_to_apply", rx_to_apply_.lifetime);
    if (performance_trace_enabled_) {
        append_latency(out, "rx_to_native_lifetime", rx_to_native_.lifetime);
        append_latency(out, "native_to_apply_lifetime", native_to_apply_.lifetime);
        append_latency(out, "rx_to_apply_lifetime", rx_to_apply_.lifetime);
    }
    out["mailbox_coalesced_states"] = static_cast<int64_t>(stats.mailbox_overwrites);
    out["mailbox_pending_dirty"] = static_cast<int64_t>(stats.mailbox_pending_dirty);
    out["mailbox_pending_high_water"] = static_cast<int64_t>(stats.mailbox_pending_high_water);
    out["mailbox_allocated_slots"] = static_cast<int64_t>(stats.mailbox_allocated_slots);
    out["mailbox_subscribed_universes"] = static_cast<int64_t>(stats.mailbox_subscribed_universes);
    out["mailbox_approx_bytes"] = static_cast<int64_t>(stats.mailbox_approximate_bytes);
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
    oldest_pending_receive_us_ = 0;
    last_native_pump_us_ = 0;
    const peraviz::runtime::RealtimePumpResult result = runtime->pump_mailbox(receiver_->realtime_mailbox(), true);
    rehydrated_states_pending_ = result.states_submitted;
    const uint64_t now_us = now_microseconds();
    if (result.oldest_receive_us > 0 && now_us >= result.oldest_receive_us) {
        rx_to_native_.observe(now_us - result.oldest_receive_us, performance_trace_enabled_);
        oldest_pending_receive_us_ = result.oldest_receive_us;
    }
    return true;
}

// Pumps deduplicated latest universe states directly between native receiver and visual runtime cores.
int PeravizDmxReceiver::pump_visual_runtime(Ref<PeravizVisualRuntime> runtime) {
    if (runtime.is_null()) return 0;
    int consumed = rehydrated_states_pending_;
    rehydrated_states_pending_ = 0;
    const peraviz::runtime::RealtimePumpResult result = runtime->pump_mailbox(receiver_->realtime_mailbox(), false);
    consumed += result.states_submitted;
    const uint64_t now_us = now_microseconds();
    if (result.oldest_receive_us > 0 && now_us >= result.oldest_receive_us) rx_to_native_.observe(now_us - result.oldest_receive_us, performance_trace_enabled_);
    scene_states_consumed_ += static_cast<uint64_t>(consumed);
    if (consumed > 0) {
        last_native_pump_us_ = now_us;
        if (result.oldest_receive_us > 0 && (oldest_pending_receive_us_ == 0 || result.oldest_receive_us < oldest_pending_receive_us_)) {
            oldest_pending_receive_us_ = result.oldest_receive_us;
        }
    }
    return consumed;
}

// Controls optional all-universe full-payload capture for the Technical Monitor.
void PeravizDmxReceiver::set_monitor_capture_enabled(bool enabled) {
    receiver_->set_monitor_capture_enabled(enabled);
}

// Records the bounded native-frame-to-Godot-apply age after renderer mutation completes.
void PeravizDmxReceiver::record_godot_apply_completion(int64_t captured_receive_us) {
    const uint64_t now_us = now_microseconds();
    if (last_native_pump_us_ > 0 && now_us >= last_native_pump_us_) {
        native_to_apply_.observe(now_us - last_native_pump_us_, performance_trace_enabled_);
        last_native_pump_us_ = 0;
    }
    const uint64_t received=captured_receive_us>0?uint64_t(captured_receive_us):oldest_pending_receive_us_;
    if (received > 0 && now_us >= received) {
        rx_to_apply_.observe(now_us - received, performance_trace_enabled_);
        oldest_pending_receive_us_ = 0;
    }
}

// Enables interval sampling without putting diagnostic Dictionaries in the playback pump.
void PeravizDmxReceiver::set_performance_trace_enabled(bool enabled) {
    performance_trace_enabled_ = enabled;
    rx_to_native_.interval = {};
    native_to_apply_.interval = {};
    rx_to_apply_.interval = {};
}

// Consumes only the trace reporter's interval; status/monitor reads never reset it.
Dictionary PeravizDmxReceiver::consume_interval_latency() {
    Dictionary out;
    append_latency(out, "rx_to_native_interval", rx_to_native_.consume_interval());
    append_latency(out, "native_to_apply_interval", native_to_apply_.consume_interval());
    append_latency(out, "rx_to_apply_interval", rx_to_apply_.consume_interval());
    return out;
}

// Serializes one explicitly named fixed histogram at a diagnostic reporting boundary.
void PeravizDmxReceiver::append_latency(Dictionary &out, const String &prefix, const peraviz::dmx::LatencyHistogram &histogram) {
    out[prefix + String("_p50_us")] = static_cast<int64_t>(histogram.percentile(50));
    out[prefix + String("_p95_us")] = static_cast<int64_t>(histogram.percentile(95));
    out[prefix + String("_max_us")] = static_cast<int64_t>(histogram.maximum_us);
    out[prefix + String("_samples")] = static_cast<int64_t>(histogram.samples);
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
