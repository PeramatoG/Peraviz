#include "peraviz_mvr_xchange_client.h"

#include <chrono>

namespace godot {

// Registers class methods so they are callable from Godot scripts.
void PeravizMvrXchangeClient::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "group", "bind_ip"), &PeravizMvrXchangeClient::start, DEFVAL(String("Default")), DEFVAL(String("")));
    ClassDB::bind_method(D_METHOD("stop"), &PeravizMvrXchangeClient::stop);
    ClassDB::bind_method(D_METHOD("is_running"), &PeravizMvrXchangeClient::is_running);
    ClassDB::bind_method(D_METHOD("get_last_error"), &PeravizMvrXchangeClient::get_last_error);
    ClassDB::bind_method(D_METHOD("get_stations"), &PeravizMvrXchangeClient::get_stations);
    ClassDB::bind_method(D_METHOD("get_commits"), &PeravizMvrXchangeClient::get_commits);
    ClassDB::bind_method(D_METHOD("join_station", "service_name"), &PeravizMvrXchangeClient::join_station);
    ClassDB::bind_method(D_METHOD("request_latest_mvr", "service_name", "target_path"), &PeravizMvrXchangeClient::request_latest_mvr);
    ClassDB::bind_method(D_METHOD("request_mvr", "service_name", "file_uuid", "target_path"), &PeravizMvrXchangeClient::request_mvr);
    ClassDB::bind_method(D_METHOD("poll_events"), &PeravizMvrXchangeClient::poll_events);
    ClassDB::bind_method(D_METHOD("get_stats"), &PeravizMvrXchangeClient::get_stats);
}

// Initializes the Godot-facing discovery client.
PeravizMvrXchangeClient::PeravizMvrXchangeClient()
    : discovery_(std::make_unique<peraviz::mvrxchange::MvrXchangeDiscovery>()),
      transfer_(std::make_unique<peraviz::mvrxchange::MvrXchangeTransferClient>()) {
}

// Stops discovery before destroying the client.
PeravizMvrXchangeClient::~PeravizMvrXchangeClient() {
    stop();
}

// Starts discovery for the requested group and optional interface address.
bool PeravizMvrXchangeClient::start(const String &group, const String &bind_ip) {
    const std::string group_name(group.utf8().get_data());
    const std::string bind_address(bind_ip.utf8().get_data());
    const bool local_started = transfer_->start_local_station(group_name, bind_address);
    const bool discovery_started = discovery_->start(group_name, bind_address);
    return local_started && discovery_started;
}

// Stops discovery.
void PeravizMvrXchangeClient::stop() {
    discovery_->stop();
    transfer_->stop();
}

// Returns whether discovery is currently active.
bool PeravizMvrXchangeClient::is_running() const {
    return discovery_->is_running();
}

// Returns the last native discovery error.
String PeravizMvrXchangeClient::get_last_error() const {
    const std::string transfer_error = transfer_->get_last_error();
    if (!transfer_error.empty()) {
        return String(transfer_error.c_str());
    }
    return String(discovery_->get_last_error().c_str());
}

// Returns discovered stations as stable dictionaries for GDScript.
Array PeravizMvrXchangeClient::get_stations() const {
    const uint64_t now_us = now_microseconds();
    Array out;
    for (const peraviz::mvrxchange::StationInfo &station : discovery_->get_stations()) {
        Dictionary item;
        item["station_name"] = String(station.station_name.c_str());
        item["group"] = String(station.group.c_str());
        item["service_name"] = String(station.service_name.c_str());
        item["host"] = String(station.host.c_str());
        item["address"] = String(station.address.c_str());
        item["port"] = static_cast<int64_t>(station.port);
        item["last_seen_ms_ago"] = station.last_seen_us > 0 && now_us >= station.last_seen_us ? static_cast<int64_t>((now_us - station.last_seen_us) / 1000ULL) : -1;
        Dictionary txt;
        for (const auto &entry : station.txt) {
            txt[String(entry.first.c_str())] = String(entry.second.c_str());
        }
        item["txt"] = txt;
        out.push_back(item);
    }
    transfer_->set_stations(discovery_->get_stations());
    return out;
}

// Returns available MVR commits as stable dictionaries for GDScript.
Array PeravizMvrXchangeClient::get_commits() const {
    Array out;
    for (const peraviz::mvrxchange::MvrXchangeCommitInfo &commit : transfer_->get_commits()) {
        Dictionary item;
        item["service_name"] = String(commit.service_name.c_str());
        item["station_name"] = String(commit.station_name.c_str());
        item["file_uuid"] = String(commit.file_uuid.c_str());
        item["timestamp"] = String(commit.timestamp.c_str());
        item["message"] = String(commit.message.c_str());
        item["seen_us"] = static_cast<int64_t>(commit.seen_us);
        out.push_back(item);
    }
    return out;
}

// Starts joining a discovered station over TCP.
bool PeravizMvrXchangeClient::join_station(const String &service_name) {
    transfer_->set_stations(discovery_->get_stations());
    return transfer_->join_station(std::string(service_name.utf8().get_data()));
}

// Requests the latest available MVR for a station.
bool PeravizMvrXchangeClient::request_latest_mvr(const String &service_name, const String &target_path) {
    transfer_->set_stations(discovery_->get_stations());
    return transfer_->request_latest_mvr(std::string(service_name.utf8().get_data()), std::string(target_path.utf8().get_data()));
}

// Requests a specific MVR file UUID for a station.
bool PeravizMvrXchangeClient::request_mvr(const String &service_name, const String &file_uuid, const String &target_path) {
    transfer_->set_stations(discovery_->get_stations());
    return transfer_->request_mvr(std::string(service_name.utf8().get_data()), std::string(file_uuid.utf8().get_data()), std::string(target_path.utf8().get_data()));
}

// Returns and clears queued MVR-xchange events.
Array PeravizMvrXchangeClient::poll_events() {
    Array out;
    for (const peraviz::mvrxchange::MvrXchangeEvent &event : transfer_->poll_events()) {
        Dictionary item;
        item["type"] = String(event.type.c_str());
        item["service_name"] = String(event.service_name.c_str());
        item["station_name"] = String(event.station_name.c_str());
        item["file_uuid"] = String(event.file_uuid.c_str());
        item["path"] = String(event.path.c_str());
        item["message"] = String(event.message.c_str());
        item["size_bytes"] = static_cast<int64_t>(event.size_bytes);
        out.push_back(item);
    }
    return out;
}

// Returns discovery runtime counters.
Dictionary PeravizMvrXchangeClient::get_stats() const {
    const peraviz::mvrxchange::DiscoveryStats stats = discovery_->get_stats();
    Dictionary out;
    out["running"] = stats.running;
    out["query_count"] = static_cast<int64_t>(stats.query_count);
    out["response_count"] = static_cast<int64_t>(stats.response_count);
    out["malformed_record_count"] = static_cast<int64_t>(stats.malformed_record_count);
    out["station_count"] = static_cast<int64_t>(stats.station_count);
    const peraviz::mvrxchange::TransferStats transfer_stats = transfer_->get_stats();
    out["transfer_busy"] = transfer_stats.busy;
    out["commit_count"] = static_cast<int64_t>(transfer_stats.commit_count);
    out["event_count"] = static_cast<int64_t>(transfer_stats.event_count);
    out["station_uuid"] = String(transfer_stats.station_uuid.c_str());
    out["current_station_uuid"] = String(transfer_stats.current_station_uuid.c_str());
    out["current_file_uuid"] = String(transfer_stats.current_file_uuid.c_str());
    out["last_received_file_path"] = String(transfer_stats.last_received_file_path.c_str());
    out["received_byte_count"] = static_cast<int64_t>(transfer_stats.received_byte_count);
    return out;
}

// Returns a monotonic timestamp in microseconds.
uint64_t PeravizMvrXchangeClient::now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace godot
