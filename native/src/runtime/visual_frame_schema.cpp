#include "runtime/visual_frame_schema.h"

#include <unordered_map>

namespace peraviz::runtime {

// Builds the immutable live protocol schema installed after structural fixture changes.
VisualFrameSchema make_default_visual_frame_schema(int32_t schema_generation) {
    VisualFrameSchema schema;
    schema.schema_generation = schema_generation;
    schema.sections = {
        {static_cast<int32_t>(VisualSectionType::GeometryTransform), 3, 2, false},
        {static_cast<int32_t>(VisualSectionType::EmitterIntensity), 3, 2, false},
        {static_cast<int32_t>(VisualSectionType::EmitterColor), 3, 3, false},
        {static_cast<int32_t>(VisualSectionType::BeamOptics), 3, 2, false},
        {static_cast<int32_t>(VisualSectionType::WheelSelection), 5, 0, false},
        {static_cast<int32_t>(VisualSectionType::WheelMotion), 4, 2, false},
        {static_cast<int32_t>(VisualSectionType::Shaper), 5, 4, false},
        {static_cast<int32_t>(VisualSectionType::TemporalOutput), 4, 2, false},
        {static_cast<int32_t>(VisualSectionType::MediaDisplay), 6, 4, true},
        {static_cast<int32_t>(VisualSectionType::Laser), 5, 6, true},
        {static_cast<int32_t>(VisualSectionType::EnvironmentOutput), 4, 2, true},
        {static_cast<int32_t>(VisualSectionType::GenericVisualParameter), 5, 1, true},
        {static_cast<int32_t>(VisualSectionType::DiagnosticNonVisual), 5, 0, true},
    };
    return schema;
}

// Validates protocol version, schema generation, section strides, and packed buffer bounds.
VisualFrameValidationResult validate_sectioned_visual_frame(const VisualFrameSchema &schema, const SectionedVisualFrame &frame) {
    if (frame.metadata.size() < static_cast<size_t>(kVisualFrameMetadataCount)) {
        return {false, "Visual frame metadata is shorter than the protocol header."};
    }
    if (frame.metadata[0] != schema.protocol_version) {
        return {false, "Visual frame protocol version does not match the installed schema."};
    }
    if (frame.metadata[1] != schema.schema_generation) {
        return {false, "Visual frame schema generation is stale."};
    }
    const int32_t section_count = frame.metadata[2];
    if (section_count < 0) {
        return {false, "Visual frame section count is negative."};
    }
    const size_t descriptor_start = static_cast<size_t>(kVisualFrameMetadataCount);
    const size_t descriptor_count = static_cast<size_t>(section_count) * static_cast<size_t>(kVisualSectionDescriptorStride);
    if (frame.metadata.size() < descriptor_start + descriptor_count) {
        return {false, "Visual frame section descriptors overrun the metadata buffer."};
    }

    std::unordered_map<int32_t, VisualSectionSchema> sections_by_type;
    for (const VisualSectionSchema &section : schema.sections) {
        sections_by_type[section.section_type] = section;
    }

    for (int32_t index = 0; index < section_count; ++index) {
        const size_t base = descriptor_start + (static_cast<size_t>(index) * static_cast<size_t>(kVisualSectionDescriptorStride));
        const int32_t section_type = frame.metadata[base];
        const int32_t row_count = frame.metadata[base + 1];
        const int32_t int_offset = frame.metadata[base + 2];
        const int32_t float_offset = frame.metadata[base + 3];
        const int32_t flags = frame.metadata[base + 4];
        (void)flags;
        if (row_count < 0 || int_offset < 0 || float_offset < 0) {
            return {false, "Visual frame section contains a negative count or offset."};
        }
        const auto schema_it = sections_by_type.find(section_type);
        if (schema_it == sections_by_type.end()) {
            return {false, "Visual frame contains an unknown section type for this schema."};
        }
        const VisualSectionSchema &section_schema = schema_it->second;
        const int64_t int_end = static_cast<int64_t>(int_offset) + (static_cast<int64_t>(row_count) * section_schema.row_stride_ints);
        const int64_t float_end = static_cast<int64_t>(float_offset) + (static_cast<int64_t>(row_count) * section_schema.row_stride_floats);
        if (int_end > static_cast<int64_t>(frame.metadata.size()) || float_end > static_cast<int64_t>(frame.values.size())) {
            return {false, "Visual frame section rows overrun a packed buffer."};
        }
    }
    return {true, {}};
}

} // namespace peraviz::runtime
