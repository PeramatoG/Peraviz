#include "dmx/gdtf_dmx_inspector.h"

#include <algorithm>
#include <cmath>

namespace peraviz::dmx {
namespace {

// Returns whether a normalized DMX value is inside an inclusive range.
bool contains_value(std::uint32_t value, std::uint32_t from, std::uint32_t to) {
    return value >= std::min(from, to) && value <= std::max(from, to);
}

// Interpolates a physical value across increasing or decreasing physical ranges.
double interpolate_physical(std::uint32_t value, const GdtfInspectorChannelFunction &function) {
    if (function.dmx_from == function.dmx_to) {
        return function.physical_from;
    }
    const double t = (static_cast<double>(value) - function.dmx_from) /
                     (static_cast<double>(function.dmx_to) - function.dmx_from);
    return function.physical_from + t * (function.physical_to - function.physical_from);
}

// Decomposes a normalized value into coarse-to-fine DMX bytes.
std::vector<std::uint8_t> decompose_bytes(std::uint32_t value, int byte_count) {
    std::vector<std::uint8_t> bytes;
    const int clamped_count = std::clamp(byte_count, 1, 4);
    bytes.reserve(static_cast<std::size_t>(clamped_count));
    for (int index = clamped_count - 1; index >= 0; --index) {
        bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8)) & 0xFFU));
    }
    return bytes;
}

} // namespace

// Returns the maximum normalized DMX value for an 8-, 16-, 24-, or 32-bit channel.
std::uint32_t max_dmx_value_for_bytes(int byte_count) {
    const int clamped_count = std::clamp(byte_count, 1, 4);
    if (clamped_count == 4) {
        return 0xFFFFFFFFU;
    }
    return (1U << (clamped_count * 8)) - 1U;
}

// Resolves active functions, sets, wheel slots, resources, and diagnostics for a DMX value.
GdtfDmxInspectionResult inspect_gdtf_dmx_value(const GdtfInspectorDmxChannel &channel,
                                               std::uint32_t normalized_value,
                                               const GdtfWheelCatalog &catalog) {
    GdtfDmxInspectionResult result;
    result.channel_id = channel.stable_id;
    result.is_virtual = channel.is_virtual;
    const std::uint32_t max_value = max_dmx_value_for_bytes(channel.byte_count);
    result.normalized_value = std::min(normalized_value, max_value);
    result.bytes = decompose_bytes(result.normalized_value, channel.byte_count);
    result.percentage = max_value == 0U ? 0.0 : static_cast<double>(result.normalized_value) / max_value * 100.0;

    for (const GdtfInspectorLogicalChannel &logical : channel.logical_channels) {
        GdtfInspectorMapping mapping;
        mapping.logical_channel_id = logical.stable_id;
        mapping.attribute = logical.attribute;
        for (const GdtfInspectorChannelFunction &function : logical.functions) {
            if (!contains_value(result.normalized_value, function.dmx_from, function.dmx_to)) {
                continue;
            }
            mapping.active_function = &function;
            mapping.mode_master_conditional = function.has_mode_master;
            if (function.has_dmx_profile) {
                mapping.diagnostics.push_back({"dmx_profile_limit", "Physical value is approximate because a DMXProfile is present."});
            } else if (function.has_physical_range) {
                mapping.physical_value = interpolate_physical(result.normalized_value, function);
                mapping.physical_reliable = std::isfinite(mapping.physical_value);
            }
            for (const GdtfInspectorChannelSet &set : function.channel_sets) {
                if (contains_value(result.normalized_value, set.dmx_from, set.dmx_to)) {
                    mapping.active_set = &set;
                    break;
                }
            }
            if (!function.wheel_name.empty()) {
                mapping.wheel = find_gdtf_wheel_by_name(catalog, function.wheel_name);
                if (!mapping.wheel) {
                    mapping.diagnostics.push_back({"missing_wheel", "ChannelFunction Wheel reference could not be resolved."});
                } else if (mapping.active_set && mapping.active_set->wheel_slot_index > 0) {
                    const int slot_index = mapping.active_set->wheel_slot_index;
                    if (slot_index <= static_cast<int>(mapping.wheel->slots.size())) {
                        mapping.wheel_slot = &mapping.wheel->slots[static_cast<std::size_t>(slot_index - 1)];
                        if (!mapping.wheel_slot->filter_reference.empty()) {
                            mapping.filter = find_gdtf_filter_by_name(catalog, mapping.wheel_slot->filter_reference);
                            if (!mapping.filter) {
                                mapping.diagnostics.push_back({"missing_filter", "WheelSlot Filter reference could not be resolved."});
                            }
                        }
                    } else {
                        mapping.diagnostics.push_back({"invalid_wheel_slot", "ChannelSet WheelSlotIndex is outside the wheel slot range."});
                    }
                } else {
                    mapping.diagnostics.push_back({"missing_wheel_slot", "Active ChannelSet has no valid one-based WheelSlotIndex."});
                }
            }
            break;
        }
        if (!mapping.active_function) {
            mapping.diagnostics.push_back({"no_function", "No ChannelFunction contains the inspected DMX value."});
        } else if (!mapping.active_set) {
            mapping.diagnostics.push_back({"no_channel_set", "No ChannelSet contains the inspected DMX value."});
        }
        result.mappings.push_back(mapping);
    }
    return result;
}

} // namespace peraviz::dmx
