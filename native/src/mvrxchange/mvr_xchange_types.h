#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace peraviz::mvrxchange {

constexpr const char *kMvrXchangeServiceType = "_mvrxchange._tcp.local.";
constexpr const char *kDefaultGroupName = "Default";

struct StationInfo {
    std::string station_name;
    std::string group;
    std::string service_name;
    std::string host;
    std::string address;
    uint16_t port = 0;
    uint64_t last_seen_us = 0;
    std::map<std::string, std::string> txt;
};

struct DiscoveryStats {
    bool running = false;
    uint64_t query_count = 0;
    uint64_t response_count = 0;
    uint64_t malformed_record_count = 0;
    uint64_t station_count = 0;
};

} // namespace peraviz::mvrxchange
