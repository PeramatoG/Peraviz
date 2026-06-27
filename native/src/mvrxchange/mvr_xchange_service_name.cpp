#include "mvrxchange/mvr_xchange_service_name.h"

#include "mvrxchange/mvr_xchange_types.h"

#include <algorithm>
#include <cctype>

namespace peraviz::mvrxchange {
namespace {

// Trims ASCII whitespace from both ends of a string.
std::string trim_copy(const std::string &value) {
    size_t first = 0;
    while (first < value.size() && std::isspace(static_cast<unsigned char>(value[first]))) {
        ++first;
    }
    size_t last = value.size();
    while (last > first && std::isspace(static_cast<unsigned char>(value[last - 1]))) {
        --last;
    }
    return value.substr(first, last - first);
}

// Removes a known DNS-SD suffix from a full service instance name.
std::string remove_service_suffix(std::string value) {
    const std::string suffix = kMvrXchangeServiceType;
    if (value.size() >= suffix.size() && value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0) {
        value.erase(value.size() - suffix.size());
    }
    if (!value.empty() && value.back() == '.') {
        value.pop_back();
    }
    return value;
}

} // namespace

// Returns a usable MVR-xchange group name, falling back to the standard default.
std::string normalize_group_name(const std::string &group) {
    const std::string trimmed = trim_copy(group);
    return trimmed.empty() ? std::string(kDefaultGroupName) : trimmed;
}

// Parses a DNS-SD service instance name into station and group fields.
ParsedServiceName parse_mvr_xchange_service_name(const std::string &service_name) {
    ParsedServiceName parsed;
    std::string instance = trim_copy(remove_service_suffix(service_name));
    if (instance.empty()) {
        return parsed;
    }

    const size_t separator = instance.rfind('@');
    if (separator == std::string::npos) {
        parsed.station_name = instance;
        parsed.group = kDefaultGroupName;
        parsed.valid = true;
        return parsed;
    }

    parsed.station_name = trim_copy(instance.substr(0, separator));
    parsed.group = normalize_group_name(instance.substr(separator + 1));
    parsed.valid = !parsed.station_name.empty();
    return parsed;
}

// Returns true when a service instance belongs to the requested group.
bool mvr_xchange_service_matches_group(const std::string &service_name, const std::string &group) {
    const ParsedServiceName parsed = parse_mvr_xchange_service_name(service_name);
    return parsed.valid && parsed.group == normalize_group_name(group);
}

} // namespace peraviz::mvrxchange
