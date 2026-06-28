#pragma once

#include "artnet_dmx_parser.h"
#include "dmx_platform.h"
#include "dmx_universe_cache.h"
#include "udp_socket.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <unordered_map>
#include <string>
#include <thread>
#include <vector>

namespace peraviz::dmx {

struct ArtNetReceiverStats {
    bool running = false;
    uint32_t packets_per_second = 0;
    uint64_t total_packets = 0;
    uint64_t packets_received = 0;
    uint64_t packets_parsed = 0;
    uint64_t packets_ignored_malformed = 0;
    uint64_t packets_dropped_out_of_order = 0;
    uint64_t packets_dropped_by_overload = 0;
    uint64_t frames_written = 0;
    uint64_t source_changes = 0;
    size_t active_slot_count = 0;
    size_t approximate_cache_bytes = 0;
    uint64_t last_packet_us = 0;
    std::vector<uint16_t> active_universes;
};

class ArtNetReceiver {
public:
    ArtNetReceiver();
    ~ArtNetReceiver();

    bool start(const std::string &bind_ip = "0.0.0.0", uint16_t port = 6454);
    void stop();
    bool is_running() const;

    bool try_get_frame(uint16_t universe_id, DmxFrame &out_frame) const;
    bool try_get_metadata(uint16_t universe_id, DmxUniverseMetadata &out_metadata) const;
    std::vector<uint16_t> get_dirty_universes() const;
    bool consume_frame(uint16_t universe_id, DmxFrame &out_frame);
    ArtNetReceiverStats get_stats(uint64_t now_us, uint64_t active_window_us) const;
    std::string get_last_error() const;

private:
    void run();
    bool should_accept_frame(const ArtNetDmxFrameView &frame_view, const std::string &sender_ip, uint16_t sender_port);
    void record_packet_time(uint64_t packet_time_us);

    SocketSystemInitializer socket_initializer_;
    UdpSocket socket_;
    ArtNetDmxParser parser_;
    DmxUniverseCache cache_;
    std::thread worker_;

    std::atomic<bool> running_ {false};
    std::atomic<uint64_t> packets_received_ {0};
    std::atomic<uint64_t> packets_parsed_ {0};
    std::atomic<uint64_t> packets_ignored_malformed_ {0};
    std::atomic<uint64_t> packets_dropped_out_of_order_ {0};
    std::atomic<uint64_t> packets_dropped_by_overload_ {0};
    std::atomic<uint64_t> frames_written_ {0};
    std::atomic<uint64_t> source_changes_ {0};
    std::atomic<uint64_t> total_packets_ {0};
    std::atomic<uint64_t> last_packet_us_ {0};
    std::atomic<uint64_t> second_window_us_ {0};
    std::atomic<uint32_t> packets_in_window_ {0};
    std::atomic<uint32_t> packets_per_second_ {0};

    mutable std::mutex error_mutex_;
    std::string last_error_;

    struct UniverseSourceState {
        std::string endpoint;
        uint8_t last_sequence = 0;
        bool has_sequence = false;
    };

    mutable std::mutex source_state_mutex_;
    std::unordered_map<uint16_t, UniverseSourceState> source_states_;
};

} // namespace peraviz::dmx
