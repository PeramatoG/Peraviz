#include "mvrxchange/mvr_xchange_local_station.h"

#include "mvrxchange/mvr_xchange_packet.h"
#include "mvrxchange/mvr_xchange_service_name.h"

#include <chrono>
#include <cstring>
#include <sstream>
#include <vector>

#ifndef _WIN32
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#else
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#endif

namespace peraviz::mvrxchange {
namespace {
constexpr uint16_t kMdnsPort = 5353;
constexpr const char *kMdnsMulticastIpv4 = "224.0.0.251";

// Closes a platform socket handle.
void close_socket_handle(int socket_fd) {
    if (socket_fd < 0) {
        return;
    }
#ifdef _WIN32
    closesocket(socket_fd);
#else
    close(socket_fd);
#endif
}

// Sends a complete string over a connected TCP socket.
bool send_all(int socket_fd, const std::string &data) {
    size_t sent = 0;
    while (sent < data.size()) {
        const int count = static_cast<int>(send(socket_fd, data.data() + sent, static_cast<int>(data.size() - sent), 0));
        if (count <= 0) {
            return false;
        }
        sent += static_cast<size_t>(count);
    }
    return true;
}

// Reads all available TCP bytes until the peer closes or times out.
std::string read_all(int socket_fd) {
    std::string data;
    char buffer[8192];
    for (;;) {
        const int count = static_cast<int>(recv(socket_fd, buffer, sizeof(buffer), 0));
        if (count <= 0) {
            break;
        }
        data.append(buffer, static_cast<size_t>(count));
    }
    return data;
}

// Encodes a DNS name as RFC1035 labels.
void encode_dns_name(std::string &out, const std::string &name) {
    size_t start = 0;
    while (start < name.size()) {
        size_t dot = name.find('.', start);
        if (dot == std::string::npos) {
            dot = name.size();
        }
        if (dot > start) {
            const size_t length = dot - start;
            out.push_back(static_cast<char>(length));
            out.append(name.data() + start, length);
        }
        start = dot + 1;
    }
    out.push_back('\0');
}

// Appends a big-endian 16-bit integer to a DNS buffer.
void append_u16(std::string &out, uint16_t value) {
    out.push_back(static_cast<char>((value >> 8U) & 0xffU));
    out.push_back(static_cast<char>(value & 0xffU));
}

// Appends a big-endian 32-bit integer to a DNS buffer.
void append_u32(std::string &out, uint32_t value) {
    out.push_back(static_cast<char>((value >> 24U) & 0xffU));
    out.push_back(static_cast<char>((value >> 16U) & 0xffU));
    out.push_back(static_cast<char>((value >> 8U) & 0xffU));
    out.push_back(static_cast<char>(value & 0xffU));
}

// Appends a DNS resource record to a response packet.
void append_record(std::string &out, const std::string &name, uint16_t type, const std::string &rdata) {
    encode_dns_name(out, name);
    append_u16(out, type);
    append_u16(out, 1);
    append_u32(out, 120);
    append_u16(out, static_cast<uint16_t>(rdata.size()));
    out.append(rdata);
}

// Returns a usable IPv4 address for mDNS A records.
std::string select_advertised_ip(const std::string &bind_ip) {
    if (!bind_ip.empty()) {
        return bind_ip;
    }
    int sock = static_cast<int>(socket(AF_INET, SOCK_DGRAM, 0));
    if (sock < 0) {
        return "127.0.0.1";
    }
    sockaddr_in remote = {};
    remote.sin_family = AF_INET;
    remote.sin_port = htons(53);
    inet_pton(AF_INET, "8.8.8.8", &remote.sin_addr);
    connect(sock, reinterpret_cast<sockaddr *>(&remote), sizeof(remote));
    sockaddr_in local = {};
    socklen_t length = sizeof(local);
    std::string result = "127.0.0.1";
    if (getsockname(sock, reinterpret_cast<sockaddr *>(&local), &length) == 0) {
        char address[INET_ADDRSTRLEN] = {};
        if (inet_ntop(AF_INET, &local.sin_addr, address, sizeof(address)) != nullptr) {
            result = address;
        }
    }
    close_socket_handle(sock);
    return result;
}

// Builds a minimal mDNS response advertising the local MVR-xchange service.
std::string build_mdns_response(const std::string &service_name, const std::string &host_name, const std::string &station_uuid, uint16_t port, const std::string &ip) {
    std::string out;
    append_u16(out, 0);
    append_u16(out, 0x8400);
    append_u16(out, 0);
    append_u16(out, 4);
    append_u16(out, 0);
    append_u16(out, 0);

    std::string ptr_data;
    encode_dns_name(ptr_data, service_name);
    append_record(out, kMvrXchangeServiceType, 12, ptr_data);

    std::string srv_data;
    append_u16(srv_data, 0);
    append_u16(srv_data, 0);
    append_u16(srv_data, port);
    encode_dns_name(srv_data, host_name);
    append_record(out, service_name, 33, srv_data);

    std::string txt_data;
    const std::string station_txt = "StationName=Peraviz";
    const std::string uuid_txt = "StationUUID=" + station_uuid;
    txt_data.push_back(static_cast<char>(station_txt.size()));
    txt_data.append(station_txt);
    txt_data.push_back(static_cast<char>(uuid_txt.size()));
    txt_data.append(uuid_txt);
    append_record(out, service_name, 16, txt_data);

    in_addr addr = {};
    inet_pton(AF_INET, ip.c_str(), &addr);
    append_record(out, host_name, 1, std::string(reinterpret_cast<const char *>(&addr), 4));
    return out;
}

}

// Creates an idle local MVR-xchange station.
MvrXchangeLocalStation::MvrXchangeLocalStation() = default;

// Stops the local station before destruction.
MvrXchangeLocalStation::~MvrXchangeLocalStation() {
    stop();
}

// Starts the local TCP server and mDNS responder.
bool MvrXchangeLocalStation::start(const std::string &group, const std::string &bind_ip, const std::string &station_uuid, MessageCallback callback) {
    if (running_.load()) {
        return true;
    }
#ifdef _WIN32
    WSADATA wsa_data;
    WSAStartup(MAKEWORD(2, 2), &wsa_data);
#endif
    group_ = normalize_group_name(group);
    bind_ip_ = bind_ip;
    station_uuid_ = station_uuid;
    service_name_ = station_name_ + "@" + group_ + "." + kMvrXchangeServiceType;
    callback_ = callback;
    server_fd_ = static_cast<int>(socket(AF_INET, SOCK_STREAM, 0));
    if (server_fd_ < 0) {
        set_last_error("Unable to open MVR-xchange TCP server socket");
        return false;
    }
    int yes = 1;
    setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char *>(&yes), sizeof(yes));
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = bind_ip.empty() ? htonl(INADDR_ANY) : inet_addr(bind_ip.c_str());
    addr.sin_port = 0;
    if (bind(server_fd_, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0 || listen(server_fd_, 8) != 0) {
        close_socket_handle(server_fd_);
        server_fd_ = -1;
        set_last_error("Unable to bind MVR-xchange TCP server");
        return false;
    }
    sockaddr_in bound = {};
    socklen_t bound_length = sizeof(bound);
    getsockname(server_fd_, reinterpret_cast<sockaddr *>(&bound), &bound_length);
    port_ = ntohs(bound.sin_port);
    running_.store(true);
    tcp_worker_ = std::thread(&MvrXchangeLocalStation::tcp_loop, this);
    mdns_worker_ = std::thread(&MvrXchangeLocalStation::mdns_loop, this);
    return true;
}

// Stops the local TCP server and mDNS responder.
void MvrXchangeLocalStation::stop() {
    running_.store(false);
    close_socket_handle(server_fd_);
    server_fd_ = -1;
    if (tcp_worker_.joinable()) {
        tcp_worker_.join();
    }
    if (mdns_worker_.joinable()) {
        mdns_worker_.join();
    }
#ifdef _WIN32
    WSACleanup();
#endif
}

// Returns whether the local station is active.
bool MvrXchangeLocalStation::is_running() const {
    return running_.load();
}

// Returns the advertised TCP port.
uint16_t MvrXchangeLocalStation::port() const {
    return port_;
}

// Returns the advertised service name.
std::string MvrXchangeLocalStation::service_name() const {
    return service_name_;
}

// Returns the most recent local station error.
std::string MvrXchangeLocalStation::last_error() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return last_error_;
}

// Accepts inbound TCP connections from other MVR-xchange stations.
void MvrXchangeLocalStation::tcp_loop() {
    while (running_.load()) {
        sockaddr_in client_addr = {};
        socklen_t client_length = sizeof(client_addr);
        const int client_fd = static_cast<int>(accept(server_fd_, reinterpret_cast<sockaddr *>(&client_addr), &client_length));
        if (client_fd < 0) {
            if (running_.load()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            continue;
        }
        handle_tcp_client(client_fd);
    }
}

// Responds to mDNS queries with the local MVR-xchange service records.
void MvrXchangeLocalStation::mdns_loop() {
    const std::string advertised_ip = select_advertised_ip(bind_ip_);
    const std::string host_name = "Peraviz-" + station_uuid_.substr(0, 8) + ".local.";
    const std::string response = build_mdns_response(service_name_, host_name, station_uuid_, port_, advertised_ip);
    int sock = static_cast<int>(socket(AF_INET, SOCK_DGRAM, 0));
    if (sock < 0) {
        set_last_error("Unable to open mDNS responder socket");
        return;
    }
    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char *>(&yes), sizeof(yes));
    sockaddr_in bind_addr = {};
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    bind_addr.sin_port = htons(kMdnsPort);
    bind(sock, reinterpret_cast<sockaddr *>(&bind_addr), sizeof(bind_addr));
    ip_mreq mreq = {};
    inet_pton(AF_INET, kMdnsMulticastIpv4, &mreq.imr_multiaddr);
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
    setsockopt(sock, IPPROTO_IP, IP_ADD_MEMBERSHIP, reinterpret_cast<const char *>(&mreq), sizeof(mreq));
    sockaddr_in multicast = {};
    multicast.sin_family = AF_INET;
    multicast.sin_port = htons(kMdnsPort);
    inet_pton(AF_INET, kMdnsMulticastIpv4, &multicast.sin_addr);
    sendto(sock, response.data(), static_cast<int>(response.size()), 0, reinterpret_cast<sockaddr *>(&multicast), sizeof(multicast));
    char buffer[1500];
    while (running_.load()) {
        sockaddr_in from = {};
        socklen_t from_length = sizeof(from);
        const int count = static_cast<int>(recvfrom(sock, buffer, sizeof(buffer), 0, reinterpret_cast<sockaddr *>(&from), &from_length));
        if (count <= 0) {
            continue;
        }
        sendto(sock, response.data(), static_cast<int>(response.size()), 0, reinterpret_cast<sockaddr *>(&from), from_length);
    }
    close_socket_handle(sock);
}

// Handles one inbound MVR-xchange TCP message.
void MvrXchangeLocalStation::handle_tcp_client(int client_fd) {
#ifdef _WIN32
    DWORD timeout_ms = 1000;
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeout_ms), sizeof(timeout_ms));
#else
    timeval timeout = {};
    timeout.tv_sec = 1;
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif
    const std::string data = read_all(client_fd);
    for (const MvrXchangePacket &packet : parse_mvr_packages(data)) {
        if (packet.package_type != kMvrPackageTypeJson) {
            continue;
        }
        const std::string type = json_string_value(packet.payload, {"Type"});
        if (type == "MVR_JOIN") {
            send_all(client_fd, build_mvr_package(kMvrPackageTypeJson, build_join_ret_message(station_name_, station_uuid_, true, std::string())));
        }
        if (callback_) {
            callback_(type, packet.payload);
        }
    }
    close_socket_handle(client_fd);
}

// Stores a local station error.
void MvrXchangeLocalStation::set_last_error(const std::string &message) {
    std::lock_guard<std::mutex> lock(mutex_);
    last_error_ = message;
}

} // namespace peraviz::mvrxchange
