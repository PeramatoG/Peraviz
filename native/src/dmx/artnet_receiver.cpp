#include "artnet_receiver.h"

#include <array>
#include <chrono>

namespace peraviz::dmx {
namespace {

// Returns a monotonic timestamp in microseconds.
uint64_t now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace

// Constructs an Art-Net receiver with default state.
ArtNetReceiver::ArtNetReceiver() = default;

// Stops the receiver when the native receiver is destroyed.
ArtNetReceiver::~ArtNetReceiver() {
    stop();
}

// Starts the receiver thread and begins listening for Art-Net packets.
bool ArtNetReceiver::start(const std::string &bind_ip, uint16_t port) {
    if (running_.load(std::memory_order_acquire)) {
        return true;
    }

    if (!socket_initializer_.is_valid()) {
        std::lock_guard<std::mutex> lock(error_mutex_);
        last_error_ = socket_initializer_.error_message();
        return false;
    }

    std::string error_message;
    const UdpSocketBindOptions bind_options {true};
    if (!socket_.open_and_bind(bind_ip, port, bind_options, error_message) ||
        !socket_.set_non_blocking(true, error_message) ||
        !socket_.set_receive_buffer(4 * 1024 * 1024, error_message)) {
        std::lock_guard<std::mutex> lock(error_mutex_);
        last_error_ = error_message;
        socket_.close();
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(error_mutex_);
        last_error_.clear();
    }

    sequence_tracker_.reset();
    running_.store(true, std::memory_order_release);
    worker_ = std::thread(&ArtNetReceiver::run, this);
    return true;
}

// Stops the receiver thread and closes the listening socket.
void ArtNetReceiver::stop() {
    running_.store(false, std::memory_order_release);
    socket_.close();
    if (worker_.joinable()) {
        worker_.join();
    }
}

// Returns whether the receiver background loop is currently running.
bool ArtNetReceiver::is_running() const {
    return running_.load(std::memory_order_acquire);
}

// Tries to fetch the latest DMX frame for a universe.
bool ArtNetReceiver::try_get_frame(uint16_t universe_id, DmxFrame &out_frame) const {
    return cache_.try_get_frame(universe_id, out_frame);
}

// Tries to fetch DMX universe metadata without copying channel data.
bool ArtNetReceiver::try_get_metadata(uint16_t universe_id, DmxUniverseMetadata &out_metadata) const {
    return metadata_cache_.get(universe_id, out_metadata);
}


// Replaces the immutable scene subscription used by the RX latest-state mailbox.
void ArtNetReceiver::set_realtime_subscription(std::shared_ptr<const RealtimeSubscription> subscription) {
    realtime_mailbox_.set_subscription(std::move(subscription));
}

// Drains only queued scene states and snapshots them without scanning the subscription.
std::vector<DmxFrame> ArtNetReceiver::consume_realtime_frames() {
    return realtime_mailbox_.consume_dirty_frames();
}

// Returns fresh held subscribed snapshots for native runtime generation rehydration.
std::vector<DmxFrame> ArtNetReceiver::get_realtime_held_states() const {
    return realtime_mailbox_.held_states();
}

// Provides the pure native coordinator access to the receiver-owned scene mailbox.
RealtimeUniverseMailbox &ArtNetReceiver::realtime_mailbox() {
    return realtime_mailbox_;
}

// Enables or disables optional full-payload capture for the Technical Monitor.
void ArtNetReceiver::set_monitor_capture_enabled(bool enabled) {
    if (!enabled) {
        monitor_capture_session_.store(0, std::memory_order_release);
        return;
    }
    if (monitor_capture_session_.load(std::memory_order_acquire) == 0) {
        monitor_capture_session_.store(cache_.begin_capture_session(), std::memory_order_release);
    }
}

// Returns runtime counters collected by the receiver.
ArtNetReceiverStats ArtNetReceiver::get_stats(uint64_t now_us, uint64_t active_window_us) const {
    ArtNetReceiverStats stats;
    stats.running = is_running();
    stats.accepted_artdmx_per_second = accepted_artdmx_per_second_.load(std::memory_order_relaxed);
    stats.packets_received = packets_received_.load(std::memory_order_relaxed);
    stats.valid_artdmx_packets = valid_artdmx_packets_.load(std::memory_order_relaxed);
    stats.packets_ignored_malformed = packets_ignored_malformed_.load(std::memory_order_relaxed);
    stats.packets_dropped_out_of_order = packets_dropped_out_of_order_.load(std::memory_order_relaxed);
    stats.valid_artdmx_accepted = valid_artdmx_accepted_.load(std::memory_order_relaxed);
    stats.drain_wake_count = drain_wake_count_.load(std::memory_order_relaxed);
    stats.max_datagrams_drained_per_wake = max_datagrams_drained_per_wake_.load(std::memory_order_relaxed);
    stats.source_changes = source_changes_.load(std::memory_order_relaxed);
    const RealtimeMailboxStats mailbox_stats = realtime_mailbox_.stats();
    stats.relevant_packets = mailbox_stats.relevant_packets;
    stats.irrelevant_packets = mailbox_stats.irrelevant_packets;
    stats.relevant_unchanged_packets = mailbox_stats.unchanged_relevant_packets;
    stats.relevant_state_updates = mailbox_stats.state_updates;
    stats.mailbox_overwrites = mailbox_stats.coalesced_states;
    stats.scene_dirty_states_consumed = mailbox_stats.dirty_states_consumed;
    stats.monitor_payload_captures = monitor_payload_captures_.load(std::memory_order_relaxed);
    stats.monitor_payload_skipped_budget = monitor_payload_skipped_budget_.load(std::memory_order_relaxed);
    stats.active_slot_count = metadata_cache_.slot_count();
    stats.approximate_cache_bytes = metadata_cache_.approximate_bytes() + cache_.get_approximate_cache_bytes();
    stats.last_packet_us = last_packet_us_.load(std::memory_order_relaxed);
    stats.active_universes = metadata_cache_.active(now_us, active_window_us);
    return stats;
}

// Returns the last runtime error reported by the receiver.
std::string ArtNetReceiver::get_last_error() const {
    std::lock_guard<std::mutex> lock(error_mutex_);
    return last_error_;
}

// Background loop that receives, parses, and stores Art-Net DMX frames.
void ArtNetReceiver::run() {
    std::array<uint8_t, 1024> receive_buffer {};
    while (running_.load(std::memory_order_acquire)) {
        std::string wait_error;
        const bool readable = socket_.wait_readable(10, wait_error);
        if (!wait_error.empty()) {
            std::lock_guard<std::mutex> lock(error_mutex_);
            last_error_ = wait_error;
            continue;
        }
        if (!readable) {
            continue;
        }

        drain_wake_count_.fetch_add(1, std::memory_order_relaxed);
        uint64_t datagrams_drained = 0;
        monitor_capture_budget_.begin_drain();
        while (running_.load(std::memory_order_acquire)) {
            UdpSenderEndpoint sender;
            std::string receive_error;
            const int bytes_read = socket_.recv_from(receive_buffer.data(), receive_buffer.size(), sender, receive_error);
            if (bytes_read < 0) {
                std::lock_guard<std::mutex> lock(error_mutex_);
                last_error_ = receive_error;
                break;
            }
            if (bytes_read == 0) {
                break;
            }
            ++datagrams_drained;

            packets_received_.fetch_add(1, std::memory_order_relaxed);

            ArtNetDmxFrameView frame_view;
            if (!parser_.parse(receive_buffer.data(), static_cast<size_t>(bytes_read), frame_view)) {
                packets_ignored_malformed_.fetch_add(1, std::memory_order_relaxed);
                continue;
            }
            valid_artdmx_packets_.fetch_add(1, std::memory_order_relaxed);

            if (!should_accept_frame(frame_view, {sender.ipv4, sender.port})) {
                packets_dropped_out_of_order_.fetch_add(1, std::memory_order_relaxed);
                continue;
            }

            const uint64_t packet_time_us = now_microseconds();
            metadata_cache_.observe(frame_view.universe_id, frame_view.length, frame_view.sequence, packet_time_us, sender.ipv4, sender.port);
            realtime_mailbox_.publish(frame_view.universe_id, frame_view.data, frame_view.length, frame_view.sequence, packet_time_us);
            const uint64_t monitor_session = monitor_capture_session_.load(std::memory_order_acquire);
            if (monitor_session != 0) {
                if (monitor_capture_budget_.try_acquire(packet_time_us)) {
                    cache_.write_frame(frame_view.universe_id, frame_view.data, frame_view.length, frame_view.sequence, packet_time_us,
                                       monitor_session);
                    monitor_payload_captures_.fetch_add(1, std::memory_order_relaxed);
                } else {
                    monitor_payload_skipped_budget_.fetch_add(1, std::memory_order_relaxed);
                }
            }
            valid_artdmx_accepted_.fetch_add(1, std::memory_order_relaxed);
            record_packet_time(packet_time_us);
        }
        uint64_t previous_max = max_datagrams_drained_per_wake_.load(std::memory_order_relaxed);
        while (datagrams_drained > previous_max && !max_datagrams_drained_per_wake_.compare_exchange_weak(previous_max, datagrams_drained, std::memory_order_relaxed)) {}
    }
}

// Applies latest-wins source tracking for a parsed frame.
bool ArtNetReceiver::should_accept_frame(const ArtNetDmxFrameView &frame_view, ArtNetEndpoint endpoint) {
    const ArtNetSequenceDecision decision = sequence_tracker_.accept(frame_view.universe_id, frame_view.sequence, endpoint);
    if (decision.source_changed) {
        // Peraviz intentionally uses latest-valid-source-wins instead of Art-Net merge.
        source_changes_.fetch_add(1, std::memory_order_relaxed);
    }
    return decision.accepted;
}

// Records packet timing and updates the packets-per-second rolling counter.
void ArtNetReceiver::record_packet_time(uint64_t packet_time_us) {
    last_packet_us_.store(packet_time_us, std::memory_order_relaxed);

    uint64_t window_start = second_window_us_.load(std::memory_order_relaxed);
    if (window_start == 0) {
        second_window_us_.store(packet_time_us, std::memory_order_relaxed);
        packets_in_window_.store(1, std::memory_order_relaxed);
        return;
    }

    if (packet_time_us - window_start >= 1000000ULL) {
        accepted_artdmx_per_second_.store(packets_in_window_.load(std::memory_order_relaxed), std::memory_order_relaxed);
        second_window_us_.store(packet_time_us, std::memory_order_relaxed);
        packets_in_window_.store(1, std::memory_order_relaxed);
    } else {
        packets_in_window_.fetch_add(1, std::memory_order_relaxed);
    }
}

} // namespace peraviz::dmx
