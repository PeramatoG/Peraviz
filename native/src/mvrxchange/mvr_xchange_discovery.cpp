#include "mvrxchange/mvr_xchange_discovery.h"

#include "mvrxchange/mvr_xchange_service_name.h"

#include <chrono>
#include <cstring>

#ifndef _WIN32
#include <arpa/inet.h>
#else
#include <ws2tcpip.h>
#endif

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#endif

#ifdef PERAVIZ_ENABLE_MVR_XCHANGE
#include <mdns.h>
#endif

namespace peraviz::mvrxchange {

namespace {
constexpr int kDiscoveryIntervalMs = 1000;

struct CallbackContext {
    MvrXchangeDiscovery *discovery = nullptr;
    const void *buffer = nullptr;
    size_t buffer_size = 0;
};

// Converts an mDNS string view into a C++ string.
std::string to_string(mdns_string_t value) {
    return value.str != nullptr && value.length > 0 ? std::string(value.str, value.length) : std::string();
}

// Formats an IPv4 socket address for station display.
std::string format_ipv4_address(const sockaddr_in &addr) {
    char address[INET_ADDRSTRLEN] = {};
    if (inet_ntop(AF_INET, &addr.sin_addr, address, sizeof(address)) == nullptr) {
        return std::string();
    }
    return address;
}

// Handles mDNS query records that describe MVR-xchange service instances.
int handle_mdns_record(int, const struct sockaddr *, size_t, mdns_entry_type_t, uint16_t, uint16_t rtype, uint16_t, uint32_t, const void *, size_t, size_t name_offset, size_t, size_t record_offset, size_t record_length, void *user_data) {
    auto *context = static_cast<CallbackContext *>(user_data);
    if (context == nullptr || context->discovery == nullptr || context->buffer == nullptr) {
        return 0;
    }

    char name_buffer[1024] = {};
    size_t readable_name_offset = name_offset;
    const mdns_string_t record_name = mdns_string_extract(context->buffer, context->buffer_size, &readable_name_offset, name_buffer, sizeof(name_buffer));
    const std::string owner_name = to_string(record_name);

    if (rtype == MDNS_RECORDTYPE_PTR) {
        char ptr_buffer[1024] = {};
        const mdns_string_t ptr_name = mdns_record_parse_ptr(context->buffer, context->buffer_size, record_offset, record_length, ptr_buffer, sizeof(ptr_buffer));
        context->discovery->upsert_placeholder_station(to_string(ptr_name));
    } else if (rtype == MDNS_RECORDTYPE_SRV) {
        char srv_buffer[1024] = {};
        const mdns_record_srv_t srv = mdns_record_parse_srv(context->buffer, context->buffer_size, record_offset, record_length, srv_buffer, sizeof(srv_buffer));
        context->discovery->upsert_service_endpoint(owner_name, to_string(srv.name), srv.port);
    } else if (rtype == MDNS_RECORDTYPE_TXT) {
        mdns_record_txt_t txt_records[32] = {};
        const size_t count = mdns_record_parse_txt(context->buffer, context->buffer_size, record_offset, record_length, txt_records, 32);
        std::map<std::string, std::string> txt;
        for (size_t i = 0; i < count; ++i) {
            txt[to_string(txt_records[i].key)] = to_string(txt_records[i].value);
        }
        context->discovery->upsert_service_txt(owner_name, txt);
    } else if (rtype == MDNS_RECORDTYPE_A) {
        sockaddr_in addr = {};
        if (mdns_record_parse_a(context->buffer, context->buffer_size, record_offset, record_length, &addr) != nullptr) {
            context->discovery->upsert_host_address(owner_name, format_ipv4_address(addr));
        }
    }
    return 0;
}

}

// Creates an idle discovery service.
MvrXchangeDiscovery::MvrXchangeDiscovery() = default;

// Stops discovery before destroying the service.
MvrXchangeDiscovery::~MvrXchangeDiscovery() {
    stop();
}

// Starts the non-blocking background discovery loop.
bool MvrXchangeDiscovery::start(const std::string &group, const std::string &bind_ip) {
    if (running_.load()) {
        return true;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        group_ = normalize_group_name(group);
        bind_ip_ = bind_ip;
        last_error_.clear();
        stations_.clear();
        stats_ = DiscoveryStats{};
        stats_.running = true;
    }
    running_.store(true);
    worker_ = std::thread(&MvrXchangeDiscovery::discovery_loop, this);
    return true;
}

// Stops the background discovery loop and waits for it to finish.
void MvrXchangeDiscovery::stop() {
    running_.store(false);
    if (worker_.joinable()) {
        worker_.join();
    }
    std::lock_guard<std::mutex> lock(mutex_);
    stats_.running = false;
}

// Returns whether discovery is currently active.
bool MvrXchangeDiscovery::is_running() const {
    return running_.load();
}

// Returns the most recent discovery error message.
std::string MvrXchangeDiscovery::get_last_error() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return last_error_;
}

// Returns a snapshot of currently known stations.
std::vector<StationInfo> MvrXchangeDiscovery::get_stations() const {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<StationInfo> out;
    out.reserve(stations_.size());
    for (const auto &entry : stations_) {
        out.push_back(entry.second);
    }
    return out;
}

// Returns discovery counters for diagnostics and UI status.
DiscoveryStats MvrXchangeDiscovery::get_stats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    DiscoveryStats out = stats_;
    out.running = running_.load();
    out.station_count = stations_.size();
    return out;
}

// Runs periodic mDNS queries away from the Godot main thread.
void MvrXchangeDiscovery::discovery_loop() {
#ifdef PERAVIZ_ENABLE_MVR_XCHANGE
#ifdef _WIN32
    WSADATA wsa_data;
    WSAStartup(MAKEWORD(2, 2), &wsa_data);
#endif
    int sock = mdns_socket_open_ipv4(nullptr);
    if (sock < 0) {
        std::lock_guard<std::mutex> lock(mutex_);
        last_error_ = "Unable to open mDNS IPv4 socket";
        running_.store(false);
        stats_.running = false;
        return;
    }
    char buffer[1024];
    while (running_.load()) {
        mdns_query_send(sock, MDNS_RECORDTYPE_PTR, kMvrXchangeServiceType, strlen(kMvrXchangeServiceType), buffer, sizeof(buffer), 0);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            ++stats_.query_count;
        }
        CallbackContext context{this, buffer, sizeof(buffer)};
        const size_t records = mdns_query_recv(sock, buffer, sizeof(buffer), handle_mdns_record, &context, 0);
        if (records > 0) {
            std::lock_guard<std::mutex> lock(mutex_);
            stats_.response_count += static_cast<uint64_t>(records);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(kDiscoveryIntervalMs));
    }
    mdns_socket_close(sock);
#ifdef _WIN32
    WSACleanup();
#endif
#else
    while (running_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(kDiscoveryIntervalMs));
    }
#endif
}

// Inserts or refreshes a station discovered from a service instance name.
void MvrXchangeDiscovery::upsert_placeholder_station(const std::string &service_name) {
    const ParsedServiceName parsed = parse_mvr_xchange_service_name(service_name);
    if (!parsed.valid || parsed.group != group_) {
        std::lock_guard<std::mutex> lock(mutex_);
        ++stats_.malformed_record_count;
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    StationInfo &station = stations_[service_name];
    station.station_name = parsed.station_name;
    station.group = parsed.group;
    station.service_name = service_name;
    station.last_seen_us = now_microseconds();
}


// Updates host and port details for a discovered service instance.
void MvrXchangeDiscovery::upsert_service_endpoint(const std::string &service_name, const std::string &host, uint16_t port) {
    const ParsedServiceName parsed = parse_mvr_xchange_service_name(service_name);
    if (!parsed.valid || parsed.group != group_) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    StationInfo &station = stations_[service_name];
    station.station_name = parsed.station_name;
    station.group = parsed.group;
    station.service_name = service_name;
    station.host = host;
    station.port = port;
    station.last_seen_us = now_microseconds();
}

// Updates TXT metadata for a discovered service instance.
void MvrXchangeDiscovery::upsert_service_txt(const std::string &service_name, const std::map<std::string, std::string> &txt) {
    const ParsedServiceName parsed = parse_mvr_xchange_service_name(service_name);
    if (!parsed.valid || parsed.group != group_) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    StationInfo &station = stations_[service_name];
    station.station_name = parsed.station_name;
    station.group = parsed.group;
    station.service_name = service_name;
    station.txt = txt;
    station.last_seen_us = now_microseconds();
}

// Updates address details on stations that reference a host.
void MvrXchangeDiscovery::upsert_host_address(const std::string &host, const std::string &address) {
    if (host.empty() || address.empty()) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto &entry : stations_) {
        if (entry.second.host == host) {
            entry.second.address = address;
            entry.second.last_seen_us = now_microseconds();
        }
    }
}

// Returns a monotonic timestamp in microseconds.
uint64_t MvrXchangeDiscovery::now_microseconds() const {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace peraviz::mvrxchange
