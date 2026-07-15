#include "runtime/wheel_runtime_core.h"

#include <algorithm>
#include <cmath>

namespace peraviz::runtime {
namespace {

// Wraps a normalized phase into the [0, 1) interval.
float wrap_phase(float phase) {
    float wrapped = std::fmod(phase, 1.0F);
    if (wrapped < 0.0F) {
        wrapped += 1.0F;
    }
    return wrapped;
}

// Finds a compiled slot by its one-based GDTF slot index.
const CompiledWheelSlot *find_slot(const CompiledWheel &wheel, int32_t slot_index) {
    for (const CompiledWheelSlot &slot : wheel.slots) {
        if (slot.slot_index == slot_index) {
            return &slot;
        }
    }
    return nullptr;
}

// Returns a stable non-zero xorshift state.
uint32_t sanitize_random_state(uint32_t state) {
    return state == 0U ? 0x9E3779B9U : state;
}

} // namespace

// Normalizes any physical wheel angle into the [0, 360) degree interval.
float normalize_wheel_degrees(float degrees) {
    float normalized = std::fmod(degrees, 360.0F);
    if (normalized < 0.0F) {
        normalized += 360.0F;
    }
    return normalized;
}

// Converts GDTF physical angle plus PlacementOffset into Peraviz clockwise slot phase.
float wheel_phase_from_physical_angle(float physical_degrees, float placement_offset_degrees) {
    return normalize_wheel_degrees(physical_degrees + placement_offset_degrees) / 360.0F;
}

// Evaluates an indexed wheel into adjacent slots and a renderer-ready split state.
WheelOpticalState evaluate_indexed_wheel_state(const CompiledWheel &wheel, float physical_degrees) {
    WheelOpticalState state;
    state.wheel_id = wheel.stable_id;
    state.mode = WheelRuntimeMode::Index;
    const int32_t slot_count = static_cast<int32_t>(wheel.slots.size());
    if (slot_count <= 0) {
        return state;
    }

    state.normalized_phase = wheel_phase_from_physical_angle(physical_degrees, wheel.placement_offset_degrees);
    const float slot_coordinate = state.normalized_phase * static_cast<float>(slot_count);
    const int32_t base_zero = static_cast<int32_t>(std::floor(slot_coordinate)) % slot_count;
    state.split_fraction = slot_coordinate - std::floor(slot_coordinate);
    state.slot_a = wheel.slots[base_zero].slot_index;
    state.slot_b = wheel.slots[(base_zero + 1) % slot_count].slot_index;
    state.boundary_angle_degrees = normalize_wheel_degrees(state.normalized_phase * 360.0F);

    const CompiledWheelSlot *slot_a = find_slot(wheel, state.slot_a);
    const CompiledWheelSlot *slot_b = find_slot(wheel, state.slot_b);
    if (slot_a && slot_b) {
        const float a_weight = 1.0F - state.split_fraction;
        const float b_weight = state.split_fraction;
        state.aggregate_srgb_r = slot_a->srgb_r * a_weight + slot_b->srgb_r * b_weight;
        state.aggregate_srgb_g = slot_a->srgb_g * a_weight + slot_b->srgb_g * b_weight;
        state.aggregate_srgb_b = slot_a->srgb_b * a_weight + slot_b->srgb_b * b_weight;
        state.aggregate_gain = slot_a->linear_gain * a_weight + slot_b->linear_gain * b_weight;
    }
    return state;
}

// Starts or updates spin while preserving the authoritative phase supplied by native runtime state.
WheelMotionState start_wheel_spin(const CompiledWheel &wheel, float current_phase, float angular_velocity_degrees_per_second, float reference_seconds) {
    WheelMotionState state;
    state.wheel_id = wheel.stable_id;
    state.mode = WheelRuntimeMode::Spin;
    state.authoritative_phase = wrap_phase(current_phase);
    state.angular_velocity_degrees_per_second = angular_velocity_degrees_per_second;
    state.reference_seconds = reference_seconds;
    return state;
}

// Builds a deterministic random seed from stable fixture, wheel, and activation identities.
uint32_t seed_wheel_random(uint32_t fixture_id, uint32_t wheel_id, uint32_t activation_revision) {
    uint32_t state = 2166136261U;
    state = (state ^ fixture_id) * 16777619U;
    state = (state ^ wheel_id) * 16777619U;
    state = (state ^ activation_revision) * 16777619U;
    return sanitize_random_state(state);
}

// Advances the deterministic wheel PRNG and returns a one-based slot index.
int32_t advance_wheel_random_slot(WheelMotionState &state, int32_t slot_count) {
    if (slot_count <= 0) {
        return 0;
    }
    uint32_t x = sanitize_random_state(state.random_state);
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state.random_state = sanitize_random_state(x);
    return static_cast<int32_t>((state.random_state % static_cast<uint32_t>(slot_count)) + 1U);
}

} // namespace peraviz::runtime
