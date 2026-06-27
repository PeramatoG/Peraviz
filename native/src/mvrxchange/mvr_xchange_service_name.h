#pragma once

#include <string>

namespace peraviz::mvrxchange {

struct ParsedServiceName {
    std::string station_name;
    std::string group;
    bool valid = false;
};

ParsedServiceName parse_mvr_xchange_service_name(const std::string &service_name);
bool mvr_xchange_service_matches_group(const std::string &service_name, const std::string &group);
std::string normalize_group_name(const std::string &group);

} // namespace peraviz::mvrxchange
