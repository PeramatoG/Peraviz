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
    ClassDB::bind_method(D_METHOD("get_stats"), &PeravizMvrXchangeClient::get_stats);
}

// Initializes the Godot-facing discovery client.
PeravizMvrXchangeClient::PeravizMvrXchangeClient()
    : discovery_(std::make_unique<peraviz::mvrxchange::MvrXchangeDiscovery>()) {
}

// Stops discovery before destroying the client.
PeravizMvrXchangeClient::~PeravizMvrXchangeClient() {
    stop();
}

// Starts discovery for the requested group and optional interface address.
bool PeravizMvrXchangeClient::start(const String &group, const String &bind_ip) {
    return discovery_->start(std::string(group.utf8().get_data()), std::string(bind_ip.utf8().get_data()));
}

// Stops discovery.
void PeravizMvrXchangeClient::stop() {
    discovery_->stop();
}

// Returns whether discovery is currently active.
bool PeravizMvrXchangeClient::is_running() const {
    return discovery_->is_running();
}

// Returns the last native discovery error.
String PeravizMvrXchangeClient::get_last_error() const {
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
    return out;
}

// Returns a monotonic timestamp in microseconds.
uint64_t PeravizMvrXchangeClient::now_microseconds() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

} // namespace godot
