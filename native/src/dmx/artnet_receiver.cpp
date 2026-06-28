#include "artnet_receiver.h"

#include <array>
#include <chrono>

namespace peraviz::dmx {
namespace {

constexpr int kMaxDatagramsPerWake = 256;

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
    if (!socket_.open_and_bind(bind_ip, port, error_message) ||
        !socket_.set_reuse_address(true, error_message) ||
        !socket_.set_non_blocking(true, error_message) ||
        !socket_.set_receive_buffer(4 * 1024 * 1024, error_message)) {
        std::lock_guard<std::mutex> lock(error_mutex_);
        last_error_ = error_message;
        socket_.close();
        return false;
    }

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
    return cache_.try_get_metadata(universe_id, out_metadata);
}

// Returns runtime counters collected by the receiver.
ArtNetReceiverStats ArtNetReceiver::get_stats(uint64_t now_us, uint64_t active_window_us) const {
    ArtNetReceiverStats stats;
    stats.running = is_running();
    stats.packets_per_second = packets_per_second_.load(std::memory_order_relaxed);
    stats.total_packets = total_packets_.load(std::memory_order_relaxed);
    stats.packets_received = packets_received_.load(std::memory_order_relaxed);
    stats.packets_parsed = packets_parsed_.load(std::memory_order_relaxed);
    stats.packets_ignored_malformed = packets_ignored_malformed_.load(std::memory_order_relaxed);
    stats.packets_dropped_out_of_order = packets_dropped_out_of_order_.load(std::memory_order_relaxed);
    stats.packets_dropped_by_overload = packets_dropped_by_overload_.load(std::memory_order_relaxed);
    stats.frames_written = frames_written_.load(std::memory_order_relaxed);
    stats.source_changes = source_changes_.load(std::memory_order_relaxed);
    stats.active_slot_count = cache_.get_active_slot_count();
    stats.approximate_cache_bytes = cache_.get_approximate_cache_bytes();
    stats.last_packet_us = last_packet_us_.load(std::memory_order_relaxed);
    stats.active_universes = cache_.get_active_universes(now_us, active_window_us);
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

        int datagrams_read = 0;
        while (running_.load(std::memory_order_acquire) && datagrams_read < kMaxDatagramsPerWake) {
            std::string sender_ip;
            uint16_t sender_port = 0;
            std::string receive_error;
            const int bytes_read = socket_.recv_from(receive_buffer.data(), receive_buffer.size(), sender_ip, sender_port, receive_error);
            if (bytes_read < 0) {
                std::lock_guard<std::mutex> lock(error_mutex_);
                last_error_ = receive_error;
                break;
            }
            if (bytes_read == 0) {
                break;
            }

            ++datagrams_read;
            packets_received_.fetch_add(1, std::memory_order_relaxed);

            ArtNetDmxFrameView frame_view;
            if (!parser_.parse(receive_buffer.data(), static_cast<size_t>(bytes_read), frame_view)) {
                packets_ignored_malformed_.fetch_add(1, std::memory_order_relaxed);
                continue;
            }
            packets_parsed_.fetch_add(1, std::memory_order_relaxed);

            if (!should_accept_frame(frame_view, sender_ip, sender_port)) {
                packets_dropped_out_of_order_.fetch_add(1, std::memory_order_relaxed);
                continue;
            }

            const uint64_t packet_time_us = now_microseconds();
            cache_.write_frame(frame_view.universe_id, frame_view.data, frame_view.length, frame_view.sequence, packet_time_us);
            frames_written_.fetch_add(1, std::memory_order_relaxed);
            total_packets_.fetch_add(1, std::memory_order_relaxed);
            record_packet_time(packet_time_us);
        }

        if (datagrams_read >= kMaxDatagramsPerWake) {
            packets_dropped_by_overload_.fetch_add(1, std::memory_order_relaxed);
        }
    }
}

// Applies latest-wins source tracking for a parsed frame.
bool ArtNetReceiver::should_accept_frame(const ArtNetDmxFrameView &frame_view, const std::string &sender_ip, uint16_t sender_port) {
    const std::string endpoint = sender_ip + ":" + std::to_string(sender_port);
    std::lock_guard<std::mutex> lock(source_state_mutex_);
    UniverseSourceState &state = source_states_[frame_view.universe_id];
    if (!state.endpoint.empty() && state.endpoint != endpoint) {
        // Peraviz intentionally uses latest-valid-source-wins instead of Art-Net merge.
        source_changes_.fetch_add(1, std::memory_order_relaxed);
        state.has_sequence = false;
    }
    state.endpoint = endpoint;
    state.has_sequence = frame_view.sequence != 0;
    state.last_sequence = frame_view.sequence;
    return true;
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
        packets_per_second_.store(packets_in_window_.load(std::memory_order_relaxed), std::memory_order_relaxed);
        second_window_us_.store(packet_time_us, std::memory_order_relaxed);
        packets_in_window_.store(1, std::memory_order_relaxed);
    } else {
        packets_in_window_.fetch_add(1, std::memory_order_relaxed);
    }
}

} // namespace peraviz::dmx
