#pragma once

#include "artnet_dmx_parser.h"
#include "artnet_sequence_tracker.h"
#include "dmx_platform.h"
#include "dmx_universe_cache.h"
#include "dmx_network_metadata_cache.h"
#include "realtime_universe_mailbox.h"
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
    uint64_t rx_drain_saturation_events = 0;
    uint64_t frames_written = 0;
    uint64_t source_changes = 0;
    uint64_t relevant_packets = 0;
    uint64_t irrelevant_packets = 0;
    uint64_t relevant_unchanged_packets = 0;
    uint64_t relevant_state_updates = 0;
    uint64_t mailbox_overwrites = 0;
    uint64_t monitor_payload_captures = 0;
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
    void set_realtime_subscription(std::shared_ptr<const RealtimeSubscription> subscription);
    bool consume_realtime_frame(uint16_t universe_id, DmxFrame &out_frame);
    std::vector<uint16_t> get_realtime_dirty_universes() const;
    std::vector<DmxFrame> get_realtime_held_states() const;
    void set_monitor_capture_enabled(bool enabled);
    ArtNetReceiverStats get_stats(uint64_t now_us, uint64_t active_window_us) const;
    std::string get_last_error() const;

private:
    void run();
    bool should_accept_frame(const ArtNetDmxFrameView &frame_view, ArtNetEndpoint endpoint);
    void record_packet_time(uint64_t packet_time_us);

    SocketSystemInitializer socket_initializer_;
    UdpSocket socket_;
    ArtNetDmxParser parser_;
    DmxUniverseCache cache_;
    DmxNetworkMetadataCache metadata_cache_;
    RealtimeUniverseMailbox realtime_mailbox_;
    std::thread worker_;

    std::atomic<bool> running_ {false};
    std::atomic<uint64_t> packets_received_ {0};
    std::atomic<uint64_t> packets_parsed_ {0};
    std::atomic<uint64_t> packets_ignored_malformed_ {0};
    std::atomic<uint64_t> packets_dropped_out_of_order_ {0};
    std::atomic<uint64_t> frames_written_ {0};
    std::atomic<uint64_t> source_changes_ {0};
    std::atomic<uint64_t> monitor_payload_captures_ {0};
    std::atomic<bool> monitor_capture_enabled_ {false};
    std::atomic<uint64_t> total_packets_ {0};
    std::atomic<uint64_t> last_packet_us_ {0};
    std::atomic<uint64_t> second_window_us_ {0};
    std::atomic<uint32_t> packets_in_window_ {0};
    std::atomic<uint32_t> packets_per_second_ {0};

    mutable std::mutex error_mutex_;
    std::string last_error_;

    ArtNetSequenceTracker sequence_tracker_;
};

} // namespace peraviz::dmx
