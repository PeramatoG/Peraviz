#include "dmx/artnet_dmx_parser.h"
#include "dmx/artnet_receiver.h"
#include "dmx/dmx_universe_cache.h"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <chrono>
#include <iostream>
#include <thread>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#endif
#include <vector>

namespace {

// Reports a test failure message and returns a non-zero exit code.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}

// Builds a minimal ArtDmx packet for parser tests.
std::vector<uint8_t> make_artdmx_packet(uint8_t sequence, uint8_t subuni, uint8_t net, uint16_t declared_length) {
    std::vector<uint8_t> packet(18 + declared_length, 0);
    const char header[8] = {'A', 'r', 't', '-', 'N', 'e', 't', '\0'};
    std::memcpy(packet.data(), header, sizeof(header));
    packet[8] = 0x00;
    packet[9] = 0x50;
    packet[10] = 0x00;
    packet[11] = 14;
    packet[12] = sequence;
    packet[14] = subuni;
    packet[15] = net;
    packet[16] = static_cast<uint8_t>((declared_length >> 8) & 0xff);
    packet[17] = static_cast<uint8_t>(declared_length & 0xff);
    for (uint16_t index = 0; index < declared_length; ++index) {
        packet[18 + index] = static_cast<uint8_t>((index + sequence) & 0xff);
    }
    return packet;
}


// Sends UDP packets to the local Art-Net receiver test port from one source socket.
bool send_udp_packets(uint16_t port, const std::vector<std::vector<uint8_t>> &packets) {
#ifdef _WIN32
    SOCKET socket_handle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socket_handle == INVALID_SOCKET) {
        return false;
    }
#else
    int socket_handle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socket_handle < 0) {
        return false;
    }
#endif
    sockaddr_in address {};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(0x7f000001UL);
    for (const std::vector<uint8_t> &packet : packets) {
        const int sent = sendto(socket_handle,
#ifdef _WIN32
                                reinterpret_cast<const char *>(packet.data()),
#else
                                packet.data(),
#endif
                                static_cast<int>(packet.size()),
                                0,
                                reinterpret_cast<sockaddr *>(&address),
                                sizeof(address));
        if (sent != static_cast<int>(packet.size())) {
#ifdef _WIN32
            closesocket(socket_handle);
#else
            close(socket_handle);
#endif
            return false;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
#ifdef _WIN32
    closesocket(socket_handle);
#else
    close(socket_handle);
#endif
    return true;
}

// Waits until a receiver universe reaches the requested counter.
bool wait_for_counter(peraviz::dmx::ArtNetReceiver &receiver, uint16_t universe_id, uint32_t counter) {
    for (int attempt = 0; attempt < 100; ++attempt) {
        peraviz::dmx::DmxFrame frame;
        if (receiver.try_get_frame(universe_id, frame) && frame.counter >= counter) {
            return true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return false;
}

// Verifies ArtDmx parser validation and field extraction.
int test_parser() {
    peraviz::dmx::ArtNetDmxParser parser;
    peraviz::dmx::ArtNetDmxFrameView frame;

    std::vector<uint8_t> packet = make_artdmx_packet(7, 0x34, 0x12, 4);
    if (!parser.parse(packet.data(), packet.size(), frame)) {
        return fail("Expected valid ArtDmx packet to parse");
    }
    if (frame.universe_id != 0x1234 || frame.sequence != 7 || frame.length != 4 || frame.data[3] != 10) {
        return fail("Parsed ArtDmx fields do not match expected values");
    }

    std::vector<uint8_t> invalid_header = packet;
    invalid_header[0] = 'X';
    if (parser.parse(invalid_header.data(), invalid_header.size(), frame)) {
        return fail("Invalid Art-Net header was accepted");
    }

    std::vector<uint8_t> invalid_opcode = packet;
    invalid_opcode[9] = 0x51;
    if (parser.parse(invalid_opcode.data(), invalid_opcode.size(), frame)) {
        return fail("Invalid ArtDmx opcode was accepted");
    }

    std::vector<uint8_t> invalid_version = packet;
    invalid_version[11] = 13;
    if (parser.parse(invalid_version.data(), invalid_version.size(), frame)) {
        return fail("Protocol version below 14 was accepted");
    }

    std::vector<uint8_t> short_packet = packet;
    short_packet.resize(17);
    if (parser.parse(short_packet.data(), short_packet.size(), frame)) {
        return fail("Short ArtDmx packet was accepted");
    }

    std::vector<uint8_t> long_packet = make_artdmx_packet(9, 1, 2, 600);
    if (!parser.parse(long_packet.data(), long_packet.size(), frame) || frame.length != 512 || frame.sequence != 9) {
        return fail("Long ArtDmx packet was not clamped to 512 channels");
    }

    return 0;
}

// Verifies double-buffer frame writes, metadata reads, and basic concurrent access.
int test_universe_cache() {
    peraviz::dmx::DmxUniverseCache cache;
    uint8_t first[4] = {1, 2, 3, 4};
    uint8_t second[4] = {5, 6, 7, 8};
    cache.write_frame(10, first, 4, 1, 100);
    cache.write_frame(10, second, 4, 2, 200);

    peraviz::dmx::DmxFrame frame;
    if (!cache.try_get_frame(10, frame)) {
        return fail("Expected cached DMX frame");
    }
    if (frame.length != 4 || frame.data[0] != 5 || frame.data[3] != 8 || frame.counter != 2 || frame.sequence != 2 || frame.content_hash == 0) {
        return fail("Cached DMX frame did not reflect latest write");
    }

    peraviz::dmx::DmxUniverseMetadata metadata;
    if (!cache.try_get_metadata(10, metadata) || metadata.counter != 2 || metadata.length != 4 || metadata.sequence != 2 || metadata.content_hash != frame.content_hash) {
        return fail("DMX universe metadata did not reflect latest write");
    }

    uint8_t partial[2] = {9, 10};
    cache.write_frame(10, partial, 2, 3, 300);
    if (!cache.try_get_frame(10, frame)) {
        return fail("Expected cached DMX frame after partial write");
    }
    if (frame.length != 4 || frame.data[0] != 9 || frame.data[1] != 10 || frame.data[2] != 7 ||
        frame.data[3] != 8 || frame.counter != 3) {
        return fail("Short DMX frame did not preserve previously received higher channel slots");
    }

    std::atomic<bool> running {true};
    std::thread writer([&cache, &running]() {
        uint8_t data[8] = {0};
        for (int iteration = 0; iteration < 2000; ++iteration) {
            data[0] = static_cast<uint8_t>(iteration & 0xff);
            cache.write_frame(static_cast<uint16_t>(iteration % 64), data, 8, static_cast<uint8_t>((iteration % 255) + 1), 1000 + iteration);
        }
        running.store(false);
    });

    while (running.load()) {
        peraviz::dmx::DmxFrame local_frame;
        for (uint16_t universe = 0; universe < 64; ++universe) {
            cache.try_get_frame(universe, local_frame);
        }
        cache.get_active_universes(5000, 5000);
    }
    writer.join();

    if (cache.get_active_slot_count() == 0 || cache.get_approximate_cache_bytes() == 0) {
        return fail("Cache slot metrics were not updated");
    }
    return 0;
}

// Verifies receiver burst draining and latest-wins sequence handling through UDP.
int test_receiver_sequence() {
    peraviz::dmx::ArtNetReceiver receiver;
    constexpr uint16_t kPort = 46454;
    if (!receiver.start("127.0.0.1", kPort)) {
        return fail("Failed to start Art-Net receiver test socket");
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    std::vector<uint8_t> seq_1 = make_artdmx_packet(1, 3, 0, 4);
    std::vector<uint8_t> seq_2 = make_artdmx_packet(2, 3, 0, 4);
    std::vector<uint8_t> seq_old = make_artdmx_packet(1, 3, 0, 4);
    std::vector<uint8_t> seq_disabled = make_artdmx_packet(0, 3, 0, 4);
    if (!send_udp_packets(kPort, {seq_1, seq_2, seq_old, seq_disabled})) {
        receiver.stop();
        return fail("Failed to send UDP ArtDmx test packets");
    }

    if (!wait_for_counter(receiver, 3, 4)) {
        receiver.stop();
        return fail("Receiver did not accept expected latest-wins packets");
    }

    const peraviz::dmx::ArtNetReceiverStats stats = receiver.get_stats(10000000, 10000000);
    receiver.stop();
    if (stats.packets_received < 4 || stats.packets_parsed < 4 || stats.frames_written != 4 ||
        stats.packets_dropped_out_of_order != 0) {
        return fail("Receiver latest-wins sequence or burst counters did not match expectations");
    }
    return 0;
}

} // namespace

// Runs DMX parser and universe cache tests.
int main() {
    if (const int rc = test_parser(); rc != 0) {
        return rc;
    }
    if (const int rc = test_universe_cache(); rc != 0) {
        return rc;
    }
    if (const int rc = test_receiver_sequence(); rc != 0) {
        return rc;
    }
    return 0;
}
