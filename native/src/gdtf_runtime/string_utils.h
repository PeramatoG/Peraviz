#pragma once

#include <algorithm>
#include <cctype>
#include <string>

namespace peraviz::gdtf_runtime {

// Trims ASCII whitespace for parser-owned semantic tokens.
inline std::string trim_ascii_token(const std::string &value) {
    const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char ch) { return std::isspace(ch) != 0; });
    const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char ch) { return std::isspace(ch) != 0; }).base();
    return first < last ? std::string(first, last) : std::string();
}

// Lowercases ASCII semantic tokens for normalized attribute matching.
inline std::string lower_ascii_token(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
}

} // namespace peraviz::gdtf_runtime
