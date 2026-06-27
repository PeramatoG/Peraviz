#include "mvrxchange/mvr_xchange_packet.h"

#include <regex>
#include <sstream>
#include <algorithm>
#include <cctype>

namespace peraviz::mvrxchange {
namespace {

// Appends a big-endian 32-bit integer to a byte buffer.
void append_u32(std::string &out, uint32_t value) {
    out.push_back(static_cast<char>((value >> 24U) & 0xffU));
    out.push_back(static_cast<char>((value >> 16U) & 0xffU));
    out.push_back(static_cast<char>((value >> 8U) & 0xffU));
    out.push_back(static_cast<char>(value & 0xffU));
}

// Appends a big-endian 64-bit integer to a byte buffer.
void append_u64(std::string &out, uint64_t value) {
    for (int shift = 56; shift >= 0; shift -= 8) {
        out.push_back(static_cast<char>((value >> static_cast<unsigned>(shift)) & 0xffU));
    }
}

// Reads a big-endian 32-bit integer from a byte buffer.
uint32_t read_u32(const std::string &data, size_t offset) {
    return (static_cast<uint32_t>(static_cast<unsigned char>(data[offset])) << 24U) |
           (static_cast<uint32_t>(static_cast<unsigned char>(data[offset + 1])) << 16U) |
           (static_cast<uint32_t>(static_cast<unsigned char>(data[offset + 2])) << 8U) |
           static_cast<uint32_t>(static_cast<unsigned char>(data[offset + 3]));
}

// Reads a big-endian 64-bit integer from a byte buffer.
uint64_t read_u64(const std::string &data, size_t offset) {
    uint64_t value = 0;
    for (size_t i = 0; i < 8; ++i) {
        value = (value << 8U) | static_cast<uint64_t>(static_cast<unsigned char>(data[offset + i]));
    }
    return value;
}

// Escapes a string for a small JSON message.
std::string json_escape(const std::string &value) {
    std::string out;
    for (char ch : value) {
        if (ch == '\\' || ch == '"') {
            out.push_back('\\');
        }
        out.push_back(ch);
    }
    return out;
}

}

// Builds an MVR-xchange TCP package with the official big-endian header.
std::string build_mvr_package(uint32_t package_type, const std::string &payload) {
    std::string out;
    out.reserve(28 + payload.size());
    append_u32(out, kMvrPackageHeader);
    append_u32(out, kMvrPackageVersion);
    append_u32(out, 0);
    append_u32(out, 1);
    append_u32(out, package_type);
    append_u64(out, static_cast<uint64_t>(payload.size()));
    out.append(payload);
    return out;
}

// Parses one or more MVR-xchange TCP packages from a byte buffer.
std::vector<MvrXchangePacket> parse_mvr_packages(const std::string &data) {
    std::vector<MvrXchangePacket> packets;
    size_t offset = 0;
    while (offset + 28 <= data.size()) {
        if (read_u32(data, offset) != kMvrPackageHeader || read_u32(data, offset + 4) != kMvrPackageVersion) {
            break;
        }
        MvrXchangePacket packet;
        packet.package_number = read_u32(data, offset + 8);
        packet.package_count = read_u32(data, offset + 12);
        packet.package_type = read_u32(data, offset + 16);
        const uint64_t length = read_u64(data, offset + 20);
        offset += 28;
        if (length > data.size() - offset) {
            break;
        }
        packet.payload.assign(data.data() + offset, static_cast<size_t>(length));
        offset += static_cast<size_t>(length);
        packets.push_back(packet);
    }
    return packets;
}

// Builds an MVR_JOIN JSON message.
std::string build_join_message(const std::string &station_name, const std::string &station_uuid) {
    std::ostringstream stream;
    stream << "{\"Type\":\"MVR_JOIN\",\"Provider\":\"Peraviz\",\"verMajor\":1,\"verMinor\":6,\"StationUUID\":\""
           << json_escape(station_uuid) << "\",\"StationName\":\"" << json_escape(station_name) << "\",\"Commits\":[]}";
    return stream.str();
}

// Builds an MVR_JOIN_RET JSON message.
std::string build_join_ret_message(const std::string &station_name, const std::string &station_uuid, bool ok, const std::string &message) {
    std::ostringstream stream;
    stream << "{\"Type\":\"MVR_JOIN_RET\",\"OK\":" << (ok ? "true" : "false")
           << ",\"Message\":\"" << json_escape(message) << "\",\"Provider\":\"Peraviz\",\"verMajor\":1,\"verMinor\":6,\"StationUUID\":\""
           << json_escape(station_uuid) << "\",\"StationName\":\"" << json_escape(station_name) << "\",\"Commits\":[]}";
    return stream.str();
}

// Builds an MVR_REQUEST JSON message.
std::string build_request_message(const std::string &station_uuid, const std::string &file_uuid) {
    const std::string from_station_uuid = canonicalize_uuid(station_uuid);
    const std::string requested_file_uuid = canonicalize_uuid(file_uuid);
    std::ostringstream stream;
    stream << "{\"Type\":\"MVR_REQUEST\",\"FromStationUUID\":\"" << json_escape(from_station_uuid.empty() ? station_uuid : from_station_uuid) << "\"";
    if (!requested_file_uuid.empty()) {
        stream << ",\"FileUUID\":\"" << json_escape(requested_file_uuid) << "\"";
    }
    stream << "}";
    return stream.str();
}

// Extracts a common JSON field value from protocol text.
std::string json_string_value(const std::string &text, const std::vector<std::string> &names) {
    for (const std::string &name : names) {
        std::regex string_regex("[\"']" + name + "[\"']\\s*:\\s*[\"']([^\"']*)[\"']", std::regex::icase);
        std::smatch match;
        if (std::regex_search(text, match, string_regex) && match.size() > 1) {
            return match[1].str();
        }
        std::regex number_regex("[\"']" + name + "[\"']\\s*:\\s*([0-9]+)", std::regex::icase);
        if (std::regex_search(text, match, number_regex) && match.size() > 1) {
            return match[1].str();
        }
    }
    return std::string();
}

// Canonicalizes UUID text to lower-case 8-4-4-4-12 form.
std::string canonicalize_uuid(const std::string &value) {
    std::string hex;
    hex.reserve(32);
    for (char ch : value) {
        if (ch == '{' || ch == '}' || ch == '-') {
            continue;
        }
        if (!std::isxdigit(static_cast<unsigned char>(ch))) {
            return std::string();
        }
        hex.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
    }
    if (hex.size() != 32) {
        return std::string();
    }
    return hex.substr(0, 8) + "-" + hex.substr(8, 4) + "-" + hex.substr(12, 4) + "-" + hex.substr(16, 4) + "-" + hex.substr(20, 12);
}

// Returns true when text contains a valid UUID value.
bool is_valid_uuid(const std::string &value) {
    return !canonicalize_uuid(value).empty();
}

} // namespace peraviz::mvrxchange
