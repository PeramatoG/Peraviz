#pragma once

#include "mvrxchange/mvr_xchange_types.h"

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace peraviz::mvrxchange {

class MvrXchangeDiscovery {
public:
    MvrXchangeDiscovery();
    ~MvrXchangeDiscovery();

    bool start(const std::string &group = kDefaultGroupName, const std::string &bind_ip = std::string());
    void stop();
    bool is_running() const;
    std::string get_last_error() const;
    std::vector<StationInfo> get_stations() const;
    DiscoveryStats get_stats() const;

private:
    void discovery_loop();
public:
    void upsert_placeholder_station(const std::string &service_name);
    void upsert_service_endpoint(const std::string &service_name, const std::string &host, uint16_t port);
    void upsert_service_txt(const std::string &service_name, const std::map<std::string, std::string> &txt);
    void upsert_host_address(const std::string &host, const std::string &address);

private:
    uint64_t now_microseconds() const;

    mutable std::mutex mutex_;
    std::thread worker_;
    std::atomic<bool> running_{false};
    std::string group_ = kDefaultGroupName;
    std::string bind_ip_;
    std::string last_error_;
    std::unordered_map<std::string, StationInfo> stations_;
    DiscoveryStats stats_;
};

} // namespace peraviz::mvrxchange
