#include "dmx/gdtf_wheel_catalog.h"

#include "dmx/gdtf_xml_reader.h"

#include <algorithm>
#include <sstream>

namespace peraviz::dmx {
namespace {

// Builds a stable catalog ID from source order and exact name.
std::string make_stable_id(const std::string &prefix, int source_order, const std::string &name) {
    return prefix + ":" + std::to_string(source_order) + ":" + name;
}

// Returns true when text identifies a graphic wheel definition.
bool contains_graphic_wheel_marker(const std::string &text) {
    const std::string lower = lower_ascii(text);
    return lower.find("graphic") != std::string::npos && lower.find("wheel") != std::string::npos;
}

// Reads a direct child text-like value by element name.
std::string read_child_text(tinyxml2::XMLElement *node, const char *name) {
    for (tinyxml2::XMLElement *child = node ? node->FirstChildElement() : nullptr; child;
         child = child->NextSiblingElement()) {
        if (lower_ascii(child->Name()) == lower_ascii(name) && child->GetText()) {
            return child->GetText();
        }
    }
    return {};
}

// Parses prism facet metadata without interpreting renderer semantics.
std::string collect_prism_facet_data(tinyxml2::XMLElement *slot) {
    std::ostringstream data;
    for (tinyxml2::XMLElement *child = slot ? slot->FirstChildElement() : nullptr; child;
         child = child->NextSiblingElement()) {
        if (lower_ascii(child->Name()) == "prismfacet") {
            if (data.tellp() > 0) {
                data << ";";
            }
            data << "PrismFacet";
        }
    }
    return data.str();
}

// Parses animation metadata without implementing playback.
std::string collect_animation_system_data(tinyxml2::XMLElement *slot) {
    std::ostringstream data;
    for (tinyxml2::XMLElement *child = slot ? slot->FirstChildElement() : nullptr; child;
         child = child->NextSiblingElement()) {
        const std::string name = lower_ascii(child->Name());
        if (name == "animationsystem" || name == "animationsystemattribute") {
            if (data.tellp() > 0) {
                data << ";";
            }
            data << child->Name();
        }
    }
    return data.str();
}

// Parses one WheelSlot and preserves exact resource references.
GdtfWheelSlotDefinition parse_wheel_slot(tinyxml2::XMLElement *slot, int slot_index, bool parent_is_graphic) {
    GdtfWheelSlotDefinition definition;
    definition.slot_index = slot_index;
    definition.name = read_attr_ci(slot, "Name", "name");
    definition.raw_color = read_attr_ci(slot, "Color", "color");
    if (!definition.raw_color.empty()) {
        definition.color = parse_gdtf_color_cie(definition.raw_color, "WheelSlot.Color");
    }
    definition.filter_reference = read_attr_ci(slot, "Filter", "filter");
    definition.media_file_name = read_attr_ci(slot, "MediaFileName", "mediafilename");
    definition.graphic_wheel_reference = read_attr_ci(slot, "GraphicWheel", "graphicwheel");
    definition.graphic_wheel_resource = read_attr_ci(slot, "GraphicFile", "graphicfile");
    if (definition.graphic_wheel_resource.empty()) {
        definition.graphic_wheel_resource = read_child_text(slot, "GraphicFile");
    }
    if (parent_is_graphic && definition.graphic_wheel_resource.empty()) {
        definition.graphic_wheel_resource = definition.media_file_name;
    }
    definition.prism_facet_data = collect_prism_facet_data(slot);
    definition.animation_system_data = collect_animation_system_data(slot);
    return definition;
}

} // namespace

// Builds a read-only Wheel, WheelSlot, Filter, and graphic-wheel catalog from GDTF XML.
GdtfWheelCatalog build_gdtf_wheel_catalog(tinyxml2::XMLElement *root) {
    GdtfWheelCatalog catalog;
    int filter_order = 0;
    for (tinyxml2::XMLElement *filter : collect_elements_by_name(root, "filter")) {
        GdtfFilterDefinition definition;
        definition.source_order = filter_order++;
        definition.name = read_attr_ci(filter, "Name", "name");
        definition.stable_id = make_stable_id("filter", definition.source_order, definition.name);
        definition.raw_color = read_attr_ci(filter, "Color", "color");
        if (!definition.raw_color.empty()) {
            definition.color = parse_gdtf_color_cie(definition.raw_color, "Filter.Color");
        }
        catalog.filters.push_back(definition);
    }

    int wheel_order = 0;
    for (tinyxml2::XMLElement *wheel : collect_elements_by_name(root, "wheel")) {
        GdtfWheelDefinition definition;
        definition.source_order = wheel_order++;
        definition.name = read_attr_ci(wheel, "Name", "name");
        definition.stable_id = make_stable_id("wheel", definition.source_order, definition.name);
        definition.wheel_type = read_attr_ci(wheel, "Type", "type");
        definition.is_graphic_wheel = contains_graphic_wheel_marker(definition.wheel_type) ||
                                      contains_graphic_wheel_marker(definition.name);
        int slot_index = 1;
        for (tinyxml2::XMLElement *slot : collect_direct_children_by_name(wheel, "wheelslot")) {
            definition.slots.push_back(parse_wheel_slot(slot, slot_index++, definition.is_graphic_wheel));
        }
        catalog.wheels.push_back(definition);
    }
    return catalog;
}

// Finds a wheel by exact name before accepting an unambiguous case-insensitive match.
const GdtfWheelDefinition *find_gdtf_wheel_by_name(const GdtfWheelCatalog &catalog, const std::string &name) {
    for (const GdtfWheelDefinition &wheel : catalog.wheels) {
        if (wheel.name == name) {
            return &wheel;
        }
    }
    const GdtfWheelDefinition *match = nullptr;
    for (const GdtfWheelDefinition &wheel : catalog.wheels) {
        if (lower_ascii(wheel.name) == lower_ascii(name)) {
            if (match) {
                return nullptr;
            }
            match = &wheel;
        }
    }
    return match;
}

// Finds a filter by exact name before accepting an unambiguous case-insensitive match.
const GdtfFilterDefinition *find_gdtf_filter_by_name(const GdtfWheelCatalog &catalog, const std::string &name) {
    for (const GdtfFilterDefinition &filter : catalog.filters) {
        if (filter.name == name) {
            return &filter;
        }
    }
    const GdtfFilterDefinition *match = nullptr;
    for (const GdtfFilterDefinition &filter : catalog.filters) {
        if (lower_ascii(filter.name) == lower_ascii(name)) {
            if (match) {
                return nullptr;
            }
            match = &filter;
        }
    }
    return match;
}

} // namespace peraviz::dmx
