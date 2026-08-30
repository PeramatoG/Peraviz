#include "dmx/dmx_universe_cache.h"
#include "dmx/artnet_receiver.h"
#include "dmx/dmx_platform.h"
#include "dmx/monitor_capture_budget.h"
#include "runtime/realtime_dmx_coordinator.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif

namespace {

// Builds a synthetic compiled scene with one relevant Dimmer slot per patched universe.
peraviz::runtime::CompiledRuntimeScene make_load_scene(int relevant_universes) {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    for (int index = 0; index < relevant_universes; ++index) {
        const int universe = index;
        const int fixture_id = index + 1;
        const int program_id = 1000 + index;
        scene.fixtures.push_back({fixture_id, "fixture-" + std::to_string(index), "load", "mode", universe, 1, 1000.0, 25.0, 1.0, 1.0});
        scene.source_programs.push_back({program_id, CompiledSemantic::Dimmer, {{universe, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
        scene.properties.push_back({2000 + index, fixture_id, 3000 + index, 4000 + index, CompiledSemantic::Dimmer, {{program_id, 1.0}}});
    }
    return scene;
}

// Returns an observed percentile from bounded benchmark samples.
uint64_t percentile(std::vector<uint64_t> samples, double fraction) {
    if (samples.empty()) return 0;
    std::sort(samples.begin(), samples.end());
    const size_t index = std::min(samples.size() - 1, static_cast<size_t>(fraction * static_cast<double>(samples.size() - 1)));
    return samples[index];
}

} // namespace

// Runs an advisory production-structure load scenario and prints deterministic work counters plus latency observations.
int run_realtime_dmx_load_harness(int argc, char **argv) {
    const int relevant_universes = argc > 2 ? std::max(1, std::atoi(argv[2])) : 256;
    const int unrelated_universes = argc > 3 ? std::max(0, std::atoi(argv[3])) : 2000;
    const int burst = argc > 4 ? std::max(1, std::atoi(argv[4])) : 1000;
    const int iterations = argc > 5 ? std::max(1, std::atoi(argv[5])) : 100;
    const bool monitor_enabled = argc > 6 && std::string(argv[6]) == "monitor-on";

    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_load_scene(relevant_universes));
    peraviz::dmx::RealtimeUniverseMailbox mailbox;
    peraviz::runtime::RealtimeDmxCoordinator coordinator;
    coordinator.install_subscription(runtime, mailbox);
    peraviz::dmx::DmxUniverseCache monitor_cache;
    const uint64_t monitor_generation = monitor_enabled ? monitor_cache.begin_capture_session() : 0;
    std::array<uint8_t, 512> frame {};
    std::vector<uint64_t> latency_us;
    latency_us.reserve(static_cast<size_t>(iterations));
    uint64_t monitor_captures = 0;
    uint64_t monitor_skips = 0;
    uint64_t visual_descriptors = 0;
    peraviz::dmx::MonitorCaptureBudget monitor_budget;

    for (int iteration = 0; iteration < iterations; ++iteration) {
        monitor_budget.begin_drain();
        for (int unrelated = 0; unrelated < unrelated_universes; ++unrelated) {
            const uint16_t universe = static_cast<uint16_t>((relevant_universes + unrelated) % 32768);
            mailbox.publish(universe, frame.data(), frame.size(), 0, static_cast<uint64_t>(iteration + 1));
            const uint64_t synthetic_now_us = static_cast<uint64_t>(iteration) * 100000ULL + static_cast<uint64_t>(unrelated);
            if (monitor_enabled && monitor_budget.try_acquire(synthetic_now_us)) {
                monitor_cache.write_frame(universe, frame.data(), frame.size(), 0, static_cast<uint64_t>(iteration + 1), monitor_generation);
                ++monitor_captures;
            } else if (monitor_enabled) {
                ++monitor_skips;
            }
        }
        const uint16_t relevant = static_cast<uint16_t>(iteration % relevant_universes);
        for (int change = 0; change < burst; ++change) {
            frame[0] = static_cast<uint8_t>((iteration + change + 1) & 0xff);
            mailbox.publish(relevant, frame.data(), frame.size(), 0, static_cast<uint64_t>(iteration + change + 1));
        }
        const auto start = std::chrono::steady_clock::now();
        const peraviz::runtime::RealtimePumpResult pumped = coordinator.pump(runtime, mailbox);
        const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count();
        if (pumped.states_submitted != 1) return 2;
        latency_us.push_back(static_cast<uint64_t>(std::max<int64_t>(elapsed, 0)));
        visual_descriptors += runtime.consume_latest_visual_frame().descriptors.size();
        if (mailbox.publish(relevant, frame.data(), frame.size(), 0, 0) || coordinator.pump(runtime, mailbox).states_submitted != 0) return 3;
    }

    const peraviz::dmx::RealtimeMailboxStats stats = mailbox.stats();
    std::cout << "realtime_dmx_load relevant_universes=" << relevant_universes
              << " unrelated_universes=" << unrelated_universes << " burst=" << burst
              << " iterations=" << iterations << " monitor=" << (monitor_enabled ? "on" : "off") << '\n'
              << "pump_us_p50=" << percentile(latency_us, 0.50) << " pump_us_p95=" << percentile(latency_us, 0.95)
              << " pump_us_max=" << percentile(latency_us, 1.0) << '\n'
              << "relevant_packets=" << stats.relevant_packets << " irrelevant_packets=" << stats.irrelevant_packets
              << " unchanged_relevant=" << stats.unchanged_relevant_packets << " mailbox_overwrites=" << stats.coalesced_states
              << " dirty_states_consumed=" << stats.dirty_states_consumed << '\n'
              << "monitor_captures=" << monitor_captures << " monitor_skips=" << monitor_skips
              << " visual_descriptor_ints=" << visual_descriptors << '\n';
    return 0;
}

namespace {

// Builds one valid ArtDmx packet for the advisory UDP transport scenario.
std::vector<uint8_t> make_load_artdmx(uint16_t universe, uint8_t value) {
    std::vector<uint8_t> packet(18 + 512, 0);
    const char header[8] = {'A', 'r', 't', '-', 'N', 'e', 't', '\0'};
    std::copy(header, header + 8, packet.begin());
    packet[8] = 0x00; packet[9] = 0x50; packet[11] = 14;
    packet[14] = static_cast<uint8_t>(universe & 0xffU);
    packet[15] = static_cast<uint8_t>((universe >> 8U) & 0x7fU);
    packet[16] = 2; packet[17] = 0;
    packet[18] = value;
    return packet;
}

// Sends one benchmark datagram through a persistent numeric UDP source.
bool send_load_packet(peraviz::dmx::SocketHandle socket_handle, uint16_t port, const std::vector<uint8_t> &packet) {
    sockaddr_in address {};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(0x7f000001UL);
    const int sent = sendto(socket_handle,
#ifdef _WIN32
                            reinterpret_cast<const char *>(packet.data()),
#else
                            packet.data(),
#endif
                            static_cast<int>(packet.size()), 0, reinterpret_cast<sockaddr *>(&address), sizeof(address));
    return sent == static_cast<int>(packet.size());
}

} // namespace

// Runs an advisory UDP ArtDmx-to-native-frame scenario using the production receiver and coordinator.
int run_realtime_dmx_udp_load_harness(int argc, char **argv) {
    const int unrelated = argc > 2 ? std::max(0, std::atoi(argv[2])) : 1000;
    const int burst = argc > 3 ? std::max(1, std::atoi(argv[3])) : 100;
    const int iterations = argc > 4 ? std::max(1, std::atoi(argv[4])) : 20;
    const bool monitor = argc > 5 && std::string(argv[5]) == "monitor-on";
    constexpr uint16_t kPort = 46510;
    peraviz::dmx::ArtNetReceiver receiver;
    receiver.set_monitor_capture_enabled(monitor);
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_load_scene(2));
    peraviz::runtime::RealtimeDmxCoordinator coordinator;
    coordinator.install_subscription(runtime, receiver.realtime_mailbox());
    if (!receiver.start("127.0.0.1", kPort)) return 10;
    const peraviz::dmx::SocketHandle sender = static_cast<peraviz::dmx::SocketHandle>(::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP));
#ifdef _WIN32
    if (sender == static_cast<peraviz::dmx::SocketHandle>(INVALID_SOCKET)) return 11;
#else
    if (sender < 0) return 11;
#endif
    std::vector<uint64_t> rx_to_native_us;
    uint64_t expected_packets = 0;
    for (int iteration = 0; iteration < iterations; ++iteration) {
        for (int index = 0; index < unrelated; ++index) {
            const uint16_t universe = static_cast<uint16_t>(100 + (index % 32000));
            if (!send_load_packet(sender, kPort, make_load_artdmx(universe, static_cast<uint8_t>(iteration)))) return 12;
            ++expected_packets;
        }
        for (int change = 0; change < burst; ++change) {
            if (!send_load_packet(sender, kPort, make_load_artdmx(1, static_cast<uint8_t>(iteration + change + 1)))) return 13;
            ++expected_packets;
        }
        for (int wait = 0; wait < 400; ++wait) {
            if (receiver.get_stats(0, 0).packets_received >= expected_packets) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        const uint64_t now_us = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
        const peraviz::runtime::RealtimePumpResult result = coordinator.pump(runtime, receiver.realtime_mailbox());
        if (result.states_submitted != 1) return 14;
        if (result.oldest_receive_us > 0 && now_us >= result.oldest_receive_us) rx_to_native_us.push_back(now_us - result.oldest_receive_us);
        runtime.consume_latest_visual_frame();
    }
    receiver.stop();
    peraviz::dmx::close_socket(sender);
    const auto stats = receiver.get_stats(0, 0);
    std::cout << "realtime_dmx_udp unrelated=" << unrelated << " burst=" << burst << " iterations=" << iterations
              << " monitor=" << (monitor ? "on" : "off") << '\n'
              << "rx_to_native_us_p50=" << percentile(rx_to_native_us, 0.50) << " rx_to_native_us_p95=" << percentile(rx_to_native_us, 0.95)
              << " rx_to_native_us_max=" << percentile(rx_to_native_us, 1.0) << '\n'
              << "datagrams_received=" << stats.packets_received << " accepted_artdmx=" << stats.valid_artdmx_accepted
              << " relevant=" << stats.relevant_packets << " irrelevant=" << stats.irrelevant_packets
              << " overwrites=" << stats.mailbox_overwrites << " monitor_captures=" << stats.monitor_payload_captures
              << " monitor_skips=" << stats.monitor_payload_skipped_budget << " max_drain=" << stats.max_datagrams_drained_per_wake << '\n';
    return 0;
}
