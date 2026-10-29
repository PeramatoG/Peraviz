#pragma once
#include "dmx/gdtf_xml_reader.h"
#include "dmx/gdtf_attribute_classifier.h"
#include <tinyxml2.h>
#include <cstdlib>
#include <functional>
#include <unordered_map>
#include <unordered_set>

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

// Retains raw evidence and refuses ambiguous/multiple MVR breaks, not new break semantics.
inline std::string unsupported_mvr_patch(tinyxml2::XMLElement *fixture) {
    auto *container = fixture->FirstChildElement("Addresses");
    if (!container) return {};
    int count = 0;
    bool unsupported = container->NextSiblingElement("Addresses") != nullptr;
    for (auto *entry = container->FirstChildElement("Address"); entry; entry = entry->NextSiblingElement("Address")) {
        ++count;
        unsupported |= !patch_integer_is(patch_attribute(entry,"break","Break"),0);
    }
    if (count <= 1 && !unsupported) return {};
    tinyxml2::XMLPrinter evidence(nullptr,true);
    container->Accept(&evidence);
    return std::string("Only one primary MVR break (0) is supported; DMX bindings withheld. Source: ")+evidence.CStr();
}

// Validates only the selected mode/tree. No flattening of multi-break or referenced sources.
inline std::string unsupported_gdtf_patch(tinyxml2::XMLElement *root, tinyxml2::XMLElement *mode) {
    for (auto *channel : collect_elements_by_name(mode,"dmxchannel")) {
        if (!parse_offsets(patch_attribute(channel,"Offset","offset") ? patch_attribute(channel,"Offset","offset") : "").empty() &&
            !patch_integer_is(patch_attribute(channel,"DMXBreak","dmxbreak"),1))
            return std::string("DMXChannel DMXBreak=")+patch_attribute(channel,"DMXBreak","dmxbreak")+" requires break-aware sources; bindings withheld.";
    }
    std::unordered_map<std::string,tinyxml2::XMLElement *> roots;
    for (auto *geometries : collect_elements_by_name(root,"geometries"))
        for (auto *node=geometries->FirstChildElement(); node; node=node->NextSiblingElement())
            if (patch_attribute(node,"Name","name")) roots[patch_attribute(node,"Name","name")]=node;
    const std::string selected = patch_attribute(mode,"Geometry","geometry") ? patch_attribute(mode,"Geometry","geometry") : "";
    auto found = roots.find(selected);
    if (found==roots.end()) return {}; // Existing missing-root diagnostics own this case.
    std::unordered_set<tinyxml2::XMLElement *> stack;
    std::unordered_map<std::string,int> names;
    std::string issue;
    std::function<void(tinyxml2::XMLElement *)> visit = [&](tinyxml2::XMLElement *node) {
        if (!issue.empty() || !stack.insert(node).second) return;
        if (lower_ascii(node->Name())=="geometryreference") {
            for (auto *entry=node->FirstChildElement(); entry; entry=entry->NextSiblingElement()) {
                if (lower_ascii(entry->Name())!="break") continue;
                if (!patch_integer_is(patch_attribute(entry,"DMXBreak","dmxbreak"),1) || !patch_integer_is(patch_attribute(entry,"DMXOffset","dmxoffset"),1)) {
                    issue="GeometryReference break/offset remapping requires instance-aware sources; bindings withheld.";
                    break;
                }
            }
            const auto target=roots.find(patch_attribute(node,"Geometry","geometry") ? patch_attribute(node,"Geometry","geometry") : "");
            if (target!=roots.end()) visit(target->second);
        } else {
            if (patch_attribute(node,"Name","name")) ++names[patch_attribute(node,"Name","name")];
            for (auto *child=node->FirstChildElement(); child; child=child->NextSiblingElement()) visit(child);
        }
        stack.erase(node);
    };
    visit(found->second);
    if (!issue.empty()) return issue;
    for (auto *channel : collect_elements_by_name(mode,"dmxchannel")) {
        const std::string geometry=patch_attribute(channel,"Geometry","geometry") ? patch_attribute(channel,"Geometry","geometry") : "";
        if (names[geometry]>1) return "DMXChannel geometry="+geometry+" has multiple reference instances; bindings withheld instead of choosing the last instance.";
    }
    return {};
}
}
