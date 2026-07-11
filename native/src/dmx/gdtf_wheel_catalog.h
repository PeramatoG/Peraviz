#pragma once

#include "dmx/gdtf_color_cie.h"

#include <string>
#include <vector>

#include <tinyxml2.h>

namespace peraviz::dmx {

struct GdtfFilterDefinition {
    std::string stable_id;
    std::string name;
    std::string raw_color;
    GdtfColorCie color;
    int source_order = 0;
};

struct GdtfWheelSlotDefinition {
    int slot_index = 0;
    std::string name;
    std::string raw_color;
    GdtfColorCie color;
    std::string filter_reference;
    std::string media_file_name;
    std::string resolved_archive_resource_path;
    std::string prism_facet_data;
    std::string animation_system_data;
    std::string graphic_wheel_reference;
    std::string graphic_wheel_resource;
    std::vector<GdtfDiagnostic> diagnostics;
};

struct GdtfWheelDefinition {
    std::string stable_id;
    std::string name;
    int source_order = 0;
    std::string wheel_type;
    bool is_graphic_wheel = false;
    std::vector<GdtfWheelSlotDefinition> slots;
    std::vector<GdtfDiagnostic> diagnostics;
};

struct GdtfWheelCatalog {
    std::vector<GdtfWheelDefinition> wheels;
    std::vector<GdtfFilterDefinition> filters;
    std::vector<GdtfDiagnostic> diagnostics;
};

GdtfWheelCatalog build_gdtf_wheel_catalog(tinyxml2::XMLElement *root);
const GdtfWheelDefinition *find_gdtf_wheel_by_name(const GdtfWheelCatalog &catalog, const std::string &name);
const GdtfFilterDefinition *find_gdtf_filter_by_name(const GdtfWheelCatalog &catalog, const std::string &name);

} // namespace peraviz::dmx
