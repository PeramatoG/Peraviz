#include "mvrxchange/mvr_xchange_transfer.h"

#include "mvrxchange/mvr_xchange_packet.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
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

// Returns a monotonic timestamp in microseconds.
uint64_t now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

// Closes a platform socket handle.
void close_socket_handle(int socket_fd) {
#ifdef _WIN32
    closesocket(socket_fd);
#else
    close(socket_fd);
#endif
}

// Connects to a station endpoint using TCP.
int connect_tcp(const StationInfo &station, std::string &error) {
    const std::string host = !station.address.empty() ? station.address : station.host;
    if (host.empty() || station.port == 0) {
        error = "Station has no TCP endpoint";
        return -1;
    }
    addrinfo hints = {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo *result = nullptr;
    const std::string port = std::to_string(station.port);
    if (getaddrinfo(host.c_str(), port.c_str(), &hints, &result) != 0 || result == nullptr) {
        error = "Unable to resolve station address";
        return -1;
    }
    int socket_fd = -1;
    for (addrinfo *ptr = result; ptr != nullptr; ptr = ptr->ai_next) {
        socket_fd = static_cast<int>(socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol));
        if (socket_fd < 0) {
            continue;
        }
        if (connect(socket_fd, ptr->ai_addr, static_cast<int>(ptr->ai_addrlen)) == 0) {
            break;
        }
        close_socket_handle(socket_fd);
        socket_fd = -1;
    }
    freeaddrinfo(result);
    if (socket_fd >= 0) {
#ifdef _WIN32
        DWORD timeout_ms = 1000;
        setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeout_ms), sizeof(timeout_ms));
#else
        timeval timeout = {};
        timeout.tv_sec = 1;
        setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif
    }
    if (socket_fd < 0) {
        error = "Unable to connect to station";
    }
    return socket_fd;
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

// Reads all available TCP bytes until the peer closes the transfer.
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

// Returns true when bytes look like a ZIP-based MVR archive.
bool looks_like_zip(const std::string &payload) {
    return payload.size() >= 4 && payload[0] == 'P' && payload[1] == 'K';
}

}

// Creates an idle transfer client.
MvrXchangeTransferClient::MvrXchangeTransferClient() {
    std::ostringstream stream;
    stream << "00000000-0000-4000-8000-" << std::hex << std::setw(12) << std::setfill('0') << (now_microseconds() & 0xffffffffffffULL);
    station_uuid_ = stream.str();
}

// Stops any active transfer before destruction.
MvrXchangeTransferClient::~MvrXchangeTransferClient() {
    stop();
}

// Starts the local advertised station required by TCP mode discovery.
bool MvrXchangeTransferClient::start_local_station(const std::string &group, const std::string &bind_ip) {
    return local_station_.start(group, bind_ip, station_uuid_, [this](const std::string &type, const std::string &payload) {
        if (type == "MVR_COMMIT") {
            StationInfo station;
            station.service_name = json_string_value(payload, {"StationUUID"});
            station.station_name = station.service_name;
            MvrXchangeCommitInfo commit = parse_commit_message(payload, station);
            if (commit.service_name.empty()) {
                commit.service_name = commit.station_name;
            }
            {
                std::lock_guard<std::mutex> lock(mutex_);
                commits_[commit.service_name] = commit;
            }
            push_event({"commit_available", commit.service_name, commit.station_name, commit.file_uuid, std::string(), commit.message, 0});
        }
    });
}

// Stops the local advertised station.
void MvrXchangeTransferClient::stop_local_station() {
    local_station_.stop();
}

// Replaces the current station snapshot from discovery.
void MvrXchangeTransferClient::set_stations(const std::vector<StationInfo> &stations) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const StationInfo &station : stations) {
        stations_[station.service_name] = station;
    }
}

// Starts an asynchronous join operation for a station.
bool MvrXchangeTransferClient::join_station(const std::string &service_name) {
    return start_worker(service_name, std::string(), std::string(), false);
}

// Requests the most recent known MVR for a station.
bool MvrXchangeTransferClient::request_latest_mvr(const std::string &service_name, const std::string &target_path) {
    std::string file_uuid;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto commit = commits_.find(service_name);
        if (commit == commits_.end()) {
            return false;
        }
        file_uuid = commit->second.file_uuid;
    }
    return request_mvr(service_name, file_uuid, target_path);
}

// Starts an asynchronous MVR request for a specific file UUID.
bool MvrXchangeTransferClient::request_mvr(const std::string &service_name, const std::string &file_uuid, const std::string &target_path) {
    return start_worker(service_name, file_uuid, target_path, true);
}

// Returns tracked commits.
std::vector<MvrXchangeCommitInfo> MvrXchangeTransferClient::get_commits() const {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<MvrXchangeCommitInfo> out;
    for (const auto &entry : commits_) {
        out.push_back(entry.second);
    }
    return out;
}

// Returns and clears queued transfer events.
std::vector<MvrXchangeEvent> MvrXchangeTransferClient::poll_events() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<MvrXchangeEvent> out;
    while (!events_.empty()) {
        out.push_back(events_.front());
        events_.pop();
    }
    return out;
}

// Returns transfer counters.
TransferStats MvrXchangeTransferClient::get_stats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    TransferStats stats;
    stats.busy = busy_.load();
    stats.commit_count = commits_.size();
    stats.event_count = event_count_;
    return stats;
}

// Returns the most recent transfer error.
std::string MvrXchangeTransferClient::get_last_error() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return last_error_;
}

// Waits for any active worker to finish.
void MvrXchangeTransferClient::stop() {
    local_station_.stop();
    if (worker_.joinable()) {
        worker_.join();
    }
    busy_.store(false);
}

// Starts the worker thread when the requested station exists.
bool MvrXchangeTransferClient::start_worker(const std::string &service_name, const std::string &file_uuid, const std::string &target_path, bool request_file) {
    if (busy_.exchange(true)) {
        set_last_error("MVR-xchange transfer is already busy");
        return false;
    }
    if (worker_.joinable()) {
        worker_.join();
    }
    StationInfo station;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto found = stations_.find(service_name);
        if (found == stations_.end()) {
            busy_.store(false);
            last_error_ = "Unknown MVR-xchange station";
            return false;
        }
        station = found->second;
    }
    worker_ = std::thread(&MvrXchangeTransferClient::worker_main, this, station, file_uuid, target_path, request_file);
    return true;
}

// Runs a join or request transaction on a background thread.
void MvrXchangeTransferClient::worker_main(StationInfo station, std::string file_uuid, std::string target_path, bool request_file) {
#ifdef _WIN32
    WSADATA wsa_data;
    WSAStartup(MAKEWORD(2, 2), &wsa_data);
#endif
    MvrXchangeEvent started;
    started.type = request_file ? "transfer_started" : "join_started";
    started.service_name = station.service_name;
    started.station_name = station.station_name;
    started.file_uuid = file_uuid;
    started.path = target_path;
    push_event(started);

    std::string error;
    const int socket_fd = connect_tcp(station, error);
    if (socket_fd < 0) {
        set_last_error(error);
        push_event({request_file ? "transfer_failed" : "join_failed", station.service_name, station.station_name, file_uuid, target_path, error, 0});
        busy_.store(false);
        return;
    }
    const std::string json = request_file ? build_request_message(station_uuid_, file_uuid) : build_join_message("Peraviz", station_uuid_);
    if (!send_all(socket_fd, build_mvr_package(kMvrPackageTypeJson, json))) {
        error = "Unable to send MVR-xchange message";
        close_socket_handle(socket_fd);
        set_last_error(error);
        push_event({request_file ? "transfer_failed" : "join_failed", station.service_name, station.station_name, file_uuid, target_path, error, 0});
        busy_.store(false);
        return;
    }
    const std::string received = read_all(socket_fd);
    close_socket_handle(socket_fd);

    const std::vector<MvrXchangePacket> packets = parse_mvr_packages(received);
    if (!request_file) {
        push_event({"join_succeeded", station.service_name, station.station_name, file_uuid, std::string(), "Joined", 0});
        for (const MvrXchangePacket &packet : packets) {
            if (packet.package_type != kMvrPackageTypeJson) {
                continue;
            }
            const MvrXchangeCommitInfo commit = parse_commit_message(packet.payload, station);
            if (!commit.file_uuid.empty() || packet.payload.find("MVR_COMMIT") != std::string::npos || packet.payload.find("Commits") != std::string::npos) {
                {
                    std::lock_guard<std::mutex> lock(mutex_);
                    commits_[station.service_name] = commit;
                }
                push_event({"commit_available", station.service_name, station.station_name, commit.file_uuid, std::string(), commit.message, 0});
            }
        }
    } else {
        std::string payload;
        for (const MvrXchangePacket &packet : packets) {
            if (packet.package_type == kMvrPackageTypeMvr) {
                payload.append(packet.payload);
            } else if (packet.package_type == kMvrPackageTypeJson && packet.payload.find("MVR_REQUEST_RET") != std::string::npos) {
                error = json_string_value(packet.payload, {"Message"});
            }
        }
        if (payload.empty() && received.size() >= 4 && received[0] == 'P' && received[1] == 'K') {
            payload = received;
        }
        if (!write_completed_mvr_file(target_path, payload, error)) {
            set_last_error(error);
            push_event({"transfer_failed", station.service_name, station.station_name, file_uuid, target_path, error, 0});
        } else {
            push_event({"transfer_finished", station.service_name, station.station_name, file_uuid, target_path, "MVR received", payload.size()});
        }
    }
    busy_.store(false);
#ifdef _WIN32
    WSACleanup();
#endif
}

// Queues a Godot-facing transfer event.
void MvrXchangeTransferClient::push_event(const MvrXchangeEvent &event) {
    std::lock_guard<std::mutex> lock(mutex_);
    events_.push(event);
    ++event_count_;
}

// Stores a transfer error.
void MvrXchangeTransferClient::set_last_error(const std::string &message) {
    std::lock_guard<std::mutex> lock(mutex_);
    last_error_ = message;
}

// Parses commit details from a received control message.
MvrXchangeCommitInfo parse_commit_message(const std::string &message, const StationInfo &station) {
    MvrXchangeCommitInfo commit;
    commit.service_name = station.service_name;
    commit.station_name = station.station_name;
    commit.file_uuid = json_string_value(message, {"FileUUID", "FileUuid", "file_uuid", "uuid"});
    commit.timestamp = json_string_value(message, {"Timestamp", "CommitTime", "timestamp"});
    commit.message = json_string_value(message, {"Message", "Comment", "CommitMessage", "Name", "message"});
    commit.seen_us = now_microseconds();
    return commit;
}

// Writes a completed transfer through a temporary part file and final rename.
bool write_completed_mvr_file(const std::string &target_path, const std::string &payload, std::string &error) {
    if (target_path.empty()) {
        error = "Missing target path";
        return false;
    }
    if (payload.empty()) {
        error = "Received MVR payload is empty";
        return false;
    }
    if (!looks_like_zip(payload)) {
        error = "Received payload does not look like a ZIP/MVR file";
        return false;
    }
    const std::filesystem::path final_path(target_path);
    std::filesystem::create_directories(final_path.parent_path());
    const std::filesystem::path part_path = final_path.string() + ".part";
    {
        std::ofstream file(part_path, std::ios::binary | std::ios::trunc);
        if (!file) {
            error = "Unable to create temporary MVR file";
            return false;
        }
        file.write(payload.data(), static_cast<std::streamsize>(payload.size()));
    }
    std::error_code remove_error;
    std::filesystem::remove(final_path, remove_error);
    std::error_code rename_error;
    std::filesystem::rename(part_path, final_path, rename_error);
    if (rename_error) {
        std::filesystem::remove(part_path, remove_error);
        error = "Unable to finalize received MVR file";
        return false;
    }
    return true;
}

} // namespace peraviz::mvrxchange
