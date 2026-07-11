#pragma once

#include "dmx/gdtf_wheel_catalog.h"

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::dmx {

struct GdtfInspectorChannelSet {
    std::string stable_id;
    std::string name;
    std::uint32_t dmx_from = 0;
    std::uint32_t dmx_to = 0;
    int wheel_slot_index = 0;
};

struct GdtfInspectorChannelFunction {
    std::string stable_id;
    std::string name;
    std::string attribute;
    std::string wheel_name;
    std::uint32_t dmx_from = 0;
    std::uint32_t dmx_to = 0;
    double physical_from = 0.0;
    double physical_to = 0.0;
    std::string physical_unit;
    bool has_physical_range = false;
    bool has_dmx_profile = false;
    bool has_mode_master = false;
    std::vector<GdtfInspectorChannelSet> channel_sets;
};

struct GdtfInspectorLogicalChannel {
    std::string stable_id;
    std::string attribute;
    std::vector<GdtfInspectorChannelFunction> functions;
};

struct GdtfInspectorDmxChannel {
    std::string stable_id;
    int byte_count = 1;
    bool is_virtual = false;
    std::vector<GdtfInspectorLogicalChannel> logical_channels;
};

struct GdtfInspectorMapping {
    std::string logical_channel_id;
    std::string attribute;
    const GdtfInspectorChannelFunction *active_function = nullptr;
    const GdtfInspectorChannelSet *active_set = nullptr;
    const GdtfWheelDefinition *wheel = nullptr;
    const GdtfWheelSlotDefinition *wheel_slot = nullptr;
    const GdtfFilterDefinition *filter = nullptr;
    double physical_value = 0.0;
    bool physical_reliable = false;
    bool mode_master_conditional = false;
    std::vector<GdtfDiagnostic> diagnostics;
};

struct GdtfDmxInspectionResult {
    std::string channel_id;
    std::uint32_t normalized_value = 0;
    std::vector<std::uint8_t> bytes;
    double percentage = 0.0;
    bool is_virtual = false;
    std::vector<GdtfInspectorMapping> mappings;
    std::vector<GdtfDiagnostic> diagnostics;
};

GdtfDmxInspectionResult inspect_gdtf_dmx_value(const GdtfInspectorDmxChannel &channel,
                                               std::uint32_t normalized_value,
                                               const GdtfWheelCatalog &catalog);
std::uint32_t max_dmx_value_for_bytes(int byte_count);

} // namespace peraviz::dmx
