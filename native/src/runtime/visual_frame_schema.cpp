#include "runtime/visual_frame_schema.h"

#include <limits>
#include <unordered_map>
#include <unordered_set>

namespace peraviz::runtime {
namespace {

// Adds a section schema when the scene has at least one matching visual capability.
void add_section(std::vector<VisualSectionSchema> &sections, VisualSectionType type, int32_t int_stride, int32_t float_stride) {
    sections.push_back({static_cast<int32_t>(type), int_stride, float_stride, 0});
}

// Checks whether row_count * stride can be represented and fits in the target buffer.
bool range_fits(int32_t offset, int32_t row_count, int32_t stride, size_t size, int64_t &end) {
    if (offset < 0 || row_count < 0 || stride <= 0) {
        return false;
    }
    const int64_t product = static_cast<int64_t>(row_count) * static_cast<int64_t>(stride);
    if (product > static_cast<int64_t>(std::numeric_limits<int32_t>::max())) {
        return false;
    }
    end = static_cast<int64_t>(offset) + product;
    return end >= 0 && end <= static_cast<int64_t>(size);
}

} // namespace

// Compiles the immutable section schema for the capabilities present in a loaded scene.
VisualFrameSchema make_visual_frame_schema(int32_t schema_generation, const VisualFrameSchemaCapabilities &capabilities) {
    VisualFrameSchema schema;
    schema.schema_generation = schema_generation;
    if (capabilities.has_transform) add_section(schema.sections, VisualSectionType::GeometryTransform, 4, 2);
    if (capabilities.has_intensity) add_section(schema.sections, VisualSectionType::EmitterIntensity, 3, 5);
    if (capabilities.has_color) add_section(schema.sections, VisualSectionType::EmitterColor, 3, 4);
    if (capabilities.has_optics) add_section(schema.sections, VisualSectionType::BeamOptics, 3, 3);
    if (capabilities.has_wheel_selection) add_section(schema.sections, VisualSectionType::WheelSelection, 5, 1);
    if (capabilities.has_wheel_motion) add_section(schema.sections, VisualSectionType::WheelMotion, 4, 3);
    if (capabilities.has_temporal) add_section(schema.sections, VisualSectionType::TemporalOutput, 4, 2);
    return schema;
}

// Builds a compatibility schema containing the currently implemented visual sections.
VisualFrameSchema make_default_visual_frame_schema(int32_t schema_generation) {
    VisualFrameSchemaCapabilities capabilities;
    capabilities.has_transform = true;
    capabilities.has_intensity = true;
    capabilities.has_color = true;
    capabilities.has_optics = true;
    capabilities.has_wheel_selection = true;
    capabilities.has_wheel_motion = true;
    capabilities.has_temporal = true;
    return make_visual_frame_schema(schema_generation, capabilities);
}

// Validates the typed descriptor, integer, and float buffers against the installed schema.
VisualFrameValidationResult validate_sectioned_visual_frame(const VisualFrameSchema &schema, const SectionedVisualFrame &frame) {
    if (frame.protocol_major != schema.protocol_major || frame.protocol_minor != schema.protocol_minor) {
        return {false, "Visual frame protocol version does not match the installed schema."};
    }
    if (frame.schema_generation != schema.schema_generation) {
        return {false, "Visual frame schema generation is stale."};
    }
    if ((frame.descriptors.size() % static_cast<size_t>(kVisualSectionDescriptorStride)) != 0U) {
        return {false, "Visual frame descriptor buffer has a malformed stride."};
    }

    std::unordered_map<int32_t, VisualSectionSchema> sections_by_type;
    for (const VisualSectionSchema &section : schema.sections) {
        if (section.row_stride_ints <= 0 || section.row_stride_floats <= 0) {
            return {false, "Installed schema contains an invalid row stride."};
        }
        sections_by_type[section.section_type] = section;
    }

    std::unordered_set<int32_t> seen_types;
    std::vector<std::pair<int64_t, int64_t>> int_ranges;
    std::vector<std::pair<int64_t, int64_t>> float_ranges;
    const size_t section_count = frame.descriptors.size() / static_cast<size_t>(kVisualSectionDescriptorStride);
    for (size_t index = 0; index < section_count; ++index) {
        const size_t base = index * static_cast<size_t>(kVisualSectionDescriptorStride);
        const int32_t section_type = frame.descriptors[base];
        const int32_t row_count = frame.descriptors[base + 1];
        const int32_t int_offset = frame.descriptors[base + 2];
        const int32_t float_offset = frame.descriptors[base + 3];
        const int32_t flags = frame.descriptors[base + 4];
        if (!seen_types.insert(section_type).second) {
            return {false, "Visual frame contains a duplicate section type."};
        }
        const auto schema_it = sections_by_type.find(section_type);
        if (schema_it == sections_by_type.end()) {
            return {false, "Visual frame contains a section type that is not installed in this schema."};
        }
        if ((flags & VisualSectionFlagMandatory) != 0 && schema_it->second.section_type != section_type) {
            return {false, "Visual frame contains an unsupported mandatory section."};
        }
        int64_t int_end = 0;
        int64_t float_end = 0;
        if (!range_fits(int_offset, row_count, schema_it->second.row_stride_ints, frame.integers.size(), int_end) ||
            !range_fits(float_offset, row_count, schema_it->second.row_stride_floats, frame.floats.size(), float_end)) {
            return {false, "Visual frame section rows overrun a packed payload buffer."};
        }
        const std::pair<int64_t, int64_t> int_range = {int_offset, int_end};
        const std::pair<int64_t, int64_t> float_range = {float_offset, float_end};
        for (const auto &range : int_ranges) {
            if (int_range.first < range.second && range.first < int_range.second) return {false, "Visual frame integer payload regions overlap."};
        }
        for (const auto &range : float_ranges) {
            if (float_range.first < range.second && range.first < float_range.second) return {false, "Visual frame float payload regions overlap."};
        }
        int_ranges.push_back(int_range);
        float_ranges.push_back(float_range);
    }
    return {true, {}};
}

} // namespace peraviz::runtime
