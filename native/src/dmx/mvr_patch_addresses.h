#pragma once
#include "scene_model.h"
#include "dmx/addressing_fields.h"
#include <set>

namespace peraviz::dmx {
// Retains ordered standard MVR entries; scalar fields are only a primary-break projection.
inline void read_mvr_patch_addresses(tinyxml2::XMLElement *fixture, SceneModel::FixturePatch &patch) {
    auto *container = fixture->FirstChildElement("Addresses");
    if (!container) return; // Existing nonstandard scalar compatibility decoding remains separate.
    patch.mvr_universe = patch.mvr_address = -1;
    const auto fail = [&]() { patch.dmx_import_error="Invalid, duplicate or contradictory MVR Address declaration; fixture bindings withheld."; };
    if (container->NextSiblingElement("Addresses")) { fail(); return; }
    std::set<int> seen;
    for (auto *node=container->FirstChildElement("Address"); node; node=node->NextSiblingElement("Address")) {
        SceneModel::FixturePatchAddress entry;
        if (node->Attribute("break") && node->Attribute("Break")) { fail(); return; }
        const char *id=patch_attribute(node,"break","Break");
        entry.explicit_break = id != nullptr;
        entry.order = static_cast<int>(patch.addresses.size());
        if (id && !patch_number(id,entry.mvr_break)) { fail(); return; }
        if (!seen.insert(entry.mvr_break).second) { fail(); return; }
        const std::string text=trim_ascii(node->GetText() ? node->GetText() : "");
        const auto dot=text.find('.');
        if (dot==std::string::npos) {
            int absolute=0;
            if (!patch_number(text,absolute,1)) { fail(); return; }
            entry.universe=1+(absolute-1)/512;
            entry.address=1+(absolute-1)%512;
        } else if (!patch_number(text.substr(0,dot),entry.universe,1) ||
                   !patch_number(text.substr(dot+1),entry.address,1) || entry.address>512) { fail(); return; }
        // Attribute-based addresses on a standard text entry are contradictory authorities.
        for (const auto *attribute=node->FirstAttribute(); attribute; attribute=attribute->Next()) {
            const auto name=lower_ascii(attribute->Name());
            if (name=="universe" || name=="address" || name=="absoluteaddress" || name=="dmxaddress") { fail(); return; }
        }
        patch.addresses.push_back(entry);
        if (entry.mvr_break==0) { patch.mvr_universe=entry.universe; patch.mvr_address=entry.address; }
    }
    if (patch.addresses.empty()) fail();
}
}
