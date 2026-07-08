#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include "runtime/visual_runtime_types.h"

namespace peraviz::runtime {

constexpr int kVisualProtocolMajor = 2;
constexpr int kVisualProtocolMinor = 0;
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

enum VisualSectionFlags : int32_t {
    VisualSectionFlagMandatory = 1 << 0,
};

enum GeometryTransformIntField : int32_t { GeometryTransformFixtureId = 0, GeometryTransformPanComponentId = 1, GeometryTransformTiltComponentId = 2, GeometryTransformChangedMask = 3 };
enum GeometryTransformFloatField : int32_t { GeometryTransformPanDegrees = 0, GeometryTransformTiltDegrees = 1 };
enum EmitterIntensityIntField : int32_t { EmitterIntensityFixtureId = 0, EmitterIntensityTargetId = 1, EmitterIntensityChangedMask = 2 };
enum EmitterIntensityFloatField : int32_t { EmitterIntensityDimmerNorm = 0, EmitterIntensityEnergy = 1, EmitterIntensitySpotEnergy = 2, EmitterIntensityBeamIntensity = 3, EmitterIntensityMaterialEnergy = 4 };
enum EmitterColorIntField : int32_t { EmitterColorFixtureId = 0, EmitterColorTargetId = 1, EmitterColorChangedMask = 2 };
enum EmitterColorFloatField : int32_t { EmitterColorRed = 0, EmitterColorGreen = 1, EmitterColorBlue = 2 };
enum BeamOpticsIntField : int32_t { BeamOpticsFixtureId = 0, BeamOpticsTargetId = 1, BeamOpticsChangedMask = 2 };
enum BeamOpticsFloatField : int32_t { BeamOpticsHalfAngle = 0, BeamOpticsAngle = 1, BeamOpticsZoomNorm = 2 };
enum WheelSelectionIntField : int32_t { WheelSelectionFixtureId = 0, WheelSelectionWheelId = 1, WheelSelectionTargetId = 2, WheelSelectionSlotIndex = 3, WheelSelectionChangedMask = 4 };
enum WheelSelectionFloatField : int32_t { WheelSelectionNormalized = 0 };
enum WheelMotionIntField : int32_t { WheelMotionFixtureId = 0, WheelMotionWheelId = 1, WheelMotionChangedMask = 2, WheelMotionMode = 3 };
enum WheelMotionFloatField : int32_t { WheelMotionIndexNorm = 0, WheelMotionRotationNorm = 1, WheelMotionShakeNorm = 2 };
enum TemporalOutputIntField : int32_t { TemporalOutputFixtureId = 0, TemporalOutputTargetId = 1, TemporalOutputMode = 2, TemporalOutputChangedMask = 3 };
enum TemporalOutputFloatField : int32_t { TemporalOutputStrobeNorm = 0, TemporalOutputOutputNorm = 1 };

struct VisualSectionSchema {
    int32_t section_type = 0;
    int32_t row_stride_ints = 0;
    int32_t row_stride_floats = 0;
    int32_t flags = 0;
};

struct VisualFrameSchema {
    int32_t protocol_major = kVisualProtocolMajor;
    int32_t protocol_minor = kVisualProtocolMinor;
    int32_t schema_generation = 1;
    std::vector<VisualSectionSchema> sections;
};

struct VisualFrameSchemaCapabilities {
    bool has_transform = false;
    bool has_intensity = false;
    bool has_color = false;
    bool has_optics = false;
    bool has_wheel_selection = false;
    bool has_wheel_motion = false;
    bool has_temporal = false;
};

struct SectionedVisualFrame {
    int32_t protocol_major = kVisualProtocolMajor;
    int32_t protocol_minor = kVisualProtocolMinor;
    int32_t schema_generation = 1;
    std::vector<int32_t> descriptors;
    std::vector<int32_t> integers;
    std::vector<float> floats;
    VisualFrameStats stats;
};

struct VisualFrameValidationResult {
    bool valid = true;
    std::string message;
};

VisualFrameSchema make_visual_frame_schema(int32_t schema_generation, const VisualFrameSchemaCapabilities &capabilities);
VisualFrameSchema make_default_visual_frame_schema(int32_t schema_generation);
VisualFrameValidationResult validate_sectioned_visual_frame(const VisualFrameSchema &schema, const SectionedVisualFrame &frame);

} // namespace peraviz::runtime
