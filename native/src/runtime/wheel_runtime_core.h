#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::runtime {

enum class WheelRuntimeMode : int32_t {
    Select = 0,
    Index = 1,
    Spin = 2,
    Random = 3,
    AudioUnsupported = 4,
};

struct CompiledWheelSlot {
    int32_t stable_id = 0;
    int32_t slot_index = 0;
    float srgb_r = 1.0F;
    float srgb_g = 1.0F;
    float srgb_b = 1.0F;
    float linear_gain = 1.0F;
    bool identity = true;
    std::string media_file_name;
    std::string optical_provenance = "default_white";
};

struct CompiledWheel {
    int32_t stable_id = 0;
    std::string name;
    std::vector<CompiledWheelSlot> slots;
    float placement_offset_degrees = 270.0F;
};

struct WheelOpticalState {
    int32_t wheel_id = 0;
    WheelRuntimeMode mode = WheelRuntimeMode::Select;
    int32_t slot_a = 0;
    int32_t slot_b = 0;
    float normalized_phase = 0.0F;
    float split_fraction = 0.0F;
    float boundary_angle_degrees = 0.0F;
    float aggregate_srgb_r = 1.0F;
    float aggregate_srgb_g = 1.0F;
    float aggregate_srgb_b = 1.0F;
    float aggregate_gain = 1.0F;
};

struct WheelMotionState {
    int32_t wheel_id = 0;
    WheelRuntimeMode mode = WheelRuntimeMode::Spin;
    float authoritative_phase = 0.0F;
    float angular_velocity_degrees_per_second = 0.0F;
    float reference_seconds = 0.0F;
    float random_frequency_hz = 0.0F;
    uint32_t random_state = 0U;
};

float normalize_wheel_degrees(float degrees);
float wheel_phase_from_physical_angle(float physical_degrees, float placement_offset_degrees);
WheelOpticalState evaluate_indexed_wheel_state(const CompiledWheel &wheel, float physical_degrees);
WheelMotionState start_wheel_spin(const CompiledWheel &wheel, float current_phase, float angular_velocity_degrees_per_second, float reference_seconds);
uint32_t seed_wheel_random(uint32_t fixture_id, uint32_t wheel_id, uint32_t activation_revision);
int32_t advance_wheel_random_slot(WheelMotionState &state, int32_t slot_count);

} // namespace peraviz::runtime
