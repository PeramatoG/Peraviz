#pragma once
#include "dmx/gdtf_xml_reader.h"
#include <tinyxml2.h>
#include <charconv>
#include <cstdlib>

namespace peraviz::dmx {
// Uses the standard spelling and the same lowercase compatibility alias as the importer.
inline const char *patch_attribute(tinyxml2::XMLElement *node, const char *name, const char *alias) {
    const auto *value = node->Attribute(name);
    return value ? value : node->Attribute(alias);
}

// Matches a complete integer spelling, without interpreting break IDs as universes.
inline bool patch_integer_is(const char *text, long expected) {
    if (!text) return true;
    const std::string raw(text);
    const auto first = raw.find_first_not_of(" \t\r\n");
    const auto last = raw.find_last_not_of(" \t\r\n");
    const auto value = first==std::string::npos ? std::string() : raw.substr(first,last-first+1);
    char *end = nullptr;
    return !value.empty() && std::strtol(value.c_str(), &end, 10)==expected && end==value.c_str()+value.size();
}

// Parses complete unsigned decimal fields without accepting suffixes or overflow.
inline bool patch_number(const std::string &raw, int &value, int minimum = 0) {
    const auto text = trim_ascii(raw);
    if (text.empty()) return false;
    const auto result = std::from_chars(text.data(), text.data()+text.size(), value);
    return result.ec==std::errc() && result.ptr==text.data()+text.size() && value>=minimum;
}

}
