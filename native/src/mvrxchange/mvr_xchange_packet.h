#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::mvrxchange {

constexpr uint32_t kMvrPackageHeader = 778682;
constexpr uint32_t kMvrPackageVersion = 1;
constexpr uint32_t kMvrPackageTypeJson = 0;
constexpr uint32_t kMvrPackageTypeMvr = 1;

struct MvrXchangePacket {
    uint32_t package_number = 0;
    uint32_t package_count = 1;
    uint32_t package_type = kMvrPackageTypeJson;
    std::string payload;
};

std::string build_mvr_package(uint32_t package_type, const std::string &payload);
std::vector<MvrXchangePacket> parse_mvr_packages(const std::string &data);
std::string build_join_message(const std::string &station_name, const std::string &station_uuid);
std::string build_join_ret_message(const std::string &station_name, const std::string &station_uuid, bool ok, const std::string &message);
std::string build_request_message(const std::string &station_uuid, const std::string &file_uuid);
std::string json_string_value(const std::string &text, const std::vector<std::string> &names);

} // namespace peraviz::mvrxchange
