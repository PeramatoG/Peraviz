#pragma once
#include "dmx/gdtf_xml_reader.h"
#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/addressing_fields.h"
#include <tinyxml2.h>
#include <functional>
#include <unordered_map>
#include <unordered_set>

namespace peraviz::dmx {
// Gates the legacy single-universe metadata API only; native compiled routing is authoritative.
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
