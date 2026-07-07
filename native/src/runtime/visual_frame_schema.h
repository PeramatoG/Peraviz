#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::runtime {

constexpr int kVisualProtocolVersion = 1;
constexpr int kVisualFrameMetadataCount = 5;
constexpr int kVisualSectionDescriptorStride = 5;

enum class VisualSectionType : int32_t {
    GeometryTransform = 1,
    EmitterIntensity = 2,
    EmitterColor = 3,
    BeamOptics = 4,
    WheelSelection = 5,
    WheelMotion = 6,
    Shaper = 7,
    TemporalOutput = 8,
    MediaDisplay = 9,
    Laser = 10,
    EnvironmentOutput = 11,
    GenericVisualParameter = 12,
    DiagnosticNonVisual = 13,
};

struct VisualSectionSchema {
    int32_t section_type = 0;
    int32_t row_stride_ints = 0;
    int32_t row_stride_floats = 0;
    bool skip_unknown_in_future_minor = false;
};

struct VisualFrameSchema {
    int32_t protocol_version = kVisualProtocolVersion;
    int32_t schema_generation = 1;
    std::vector<VisualSectionSchema> sections;
};

struct SectionedVisualFrame {
    std::vector<int32_t> metadata;
    std::vector<float> values;
};

struct VisualFrameValidationResult {
    bool valid = true;
    std::string message;
};

VisualFrameSchema make_default_visual_frame_schema(int32_t schema_generation);
VisualFrameValidationResult validate_sectioned_visual_frame(const VisualFrameSchema &schema, const SectionedVisualFrame &frame);

} // namespace peraviz::runtime
