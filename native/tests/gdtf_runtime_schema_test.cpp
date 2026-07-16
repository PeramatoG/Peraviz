#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_frame_schema.h"
#include "runtime/wheel_runtime_core.h"

#include <cmath>
#include <iostream>

namespace {

// Reports a schema test failure.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}

// Verifies numbered wildcard families keep separate component identities.
int test_two_gobo_wheels_remain_independent() {
    const auto fixture = peraviz::gdtf_runtime::make_two_gobo_wheel_regression_fixture();
    if (fixture.components.size() != 3 || fixture.components[1].wheel_id == fixture.components[2].wheel_id) {
        return fail("Expected two gobo wheels to compile as separate wheel/component IDs.");
    }
    if (fixture.attributes[1].canonical_family != "Gobo" || fixture.attributes[1].primary_index != 1) {
        return fail("Gobo1 was not normalized as wildcard family Gobo index 1.");
    }
    if (fixture.attributes[2].canonical_family != "Gobo" || fixture.attributes[2].primary_index != 2) {
        return fail("Gobo2 was not normalized as wildcard family Gobo index 2.");
    }
    return 0;
}

// Verifies the sectioned live frame validator rejects stale schema generations.
int test_stale_schema_generation_is_rejected() {
    const auto schema = peraviz::runtime::make_default_visual_frame_schema(7);
    peraviz::runtime::SectionedVisualFrame frame;
    frame.schema_generation = 6;
    const auto result = peraviz::runtime::validate_sectioned_visual_frame(schema, frame);
    if (result.valid) {
        return fail("Expected stale schema generation to be rejected.");
    }
    return 0;
}

// Verifies section bounds are checked before Godot can consume packed buffers.
int test_section_bounds_are_validated() {
    const auto schema = peraviz::runtime::make_default_visual_frame_schema(1);
    peraviz::runtime::SectionedVisualFrame frame;
    frame.descriptors = {static_cast<int>(peraviz::runtime::VisualSectionType::EmitterIntensity), 2, 10, 0, 0};
    frame.floats = {1.0f, 2.0f, 3.0f, 4.0f};
    const auto result = peraviz::runtime::validate_sectioned_visual_frame(schema, frame);
    if (result.valid) {
        return fail("Expected section metadata overrun to be rejected.");
    }
    return 0;
}

// Verifies protocol v2.1 carries renderer-ready wheel optical and motion rows.
int test_wheel_protocol_schema_is_versioned() {
    const auto schema = peraviz::runtime::make_default_visual_frame_schema(1);
    if (schema.protocol_major != 2 || schema.protocol_minor != 1) {
        return fail("Expected color-wheel protocol migration to v2.1.");
    }
    bool saw_selection = false;
    bool saw_motion = false;
    for (const auto &section : schema.sections) {
        if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelSelection)) {
            saw_selection = section.row_stride_ints == 8 && section.row_stride_floats == 8;
        }
        if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelMotion)) {
            saw_motion = section.row_stride_ints == 6 && section.row_stride_floats == 4;
        }
    }
    if (!saw_selection || !saw_motion) {
        return fail("Expected migrated wheel row strides in default schema.");
    }
    return 0;
}

// Verifies PlacementOffset and indexed angle mapping across cyclic wheel boundaries.
int test_indexed_wheel_angle_mapping() {
    peraviz::runtime::CompiledWheel wheel;
    wheel.stable_id = 42;
    wheel.placement_offset_degrees = 270.0F;
    for (int i = 1; i <= 4; ++i) {
        peraviz::runtime::CompiledWheelSlot slot;
        slot.stable_id = i;
        slot.slot_index = i;
        slot.srgb_r = static_cast<float>(i);
        slot.srgb_g = 0.0F;
        slot.srgb_b = 0.0F;
        slot.linear_gain = 1.0F;
        wheel.slots.push_back(slot);
    }
    const auto full_a = peraviz::runtime::evaluate_indexed_wheel_state(wheel, -270.0F);
    if (full_a.slot_a != 1 || full_a.slot_b != 2 || std::fabs(full_a.split_fraction) > 0.0001F) {
        return fail("Expected PlacementOffset-adjusted -270 degrees to seat slot 1.");
    }
    const auto half = peraviz::runtime::evaluate_indexed_wheel_state(wheel, -225.0F);
    if (half.slot_a != 1 || half.slot_b != 2 || std::fabs(half.split_fraction - 0.5F) > 0.0001F) {
        return fail("Expected half-sector angle to split slots 1 and 2 equally.");
    }
    const auto wrapped = peraviz::runtime::evaluate_indexed_wheel_state(wheel, 0.0F);
    if (wrapped.slot_a != 4 || wrapped.slot_b != 1 || std::fabs(wrapped.split_fraction) > 0.0001F) {
        return fail("Expected cyclic last-to-first mapping at 0 degrees with default PlacementOffset.");
    }
    return 0;
}

// Verifies deterministic random seeding and slot selection remain native-authoritative.
int test_deterministic_wheel_random() {
    peraviz::runtime::WheelMotionState a;
    peraviz::runtime::WheelMotionState b;
    a.random_state = peraviz::runtime::seed_wheel_random(10, 20, 30);
    b.random_state = peraviz::runtime::seed_wheel_random(10, 20, 30);
    for (int i = 0; i < 8; ++i) {
        const int32_t slot_a = peraviz::runtime::advance_wheel_random_slot(a, 6);
        const int32_t slot_b = peraviz::runtime::advance_wheel_random_slot(b, 6);
        if (slot_a != slot_b || slot_a < 1 || slot_a > 6) {
            return fail("Expected deterministic in-range random wheel slot sequence.");
        }
    }
    return 0;
}

} // namespace

// Runs the native GDTF runtime schema foundation tests.
int main() {
    if (int result = test_two_gobo_wheels_remain_independent()) return result;
    if (int result = test_stale_schema_generation_is_rejected()) return result;
    if (int result = test_section_bounds_are_validated()) return result;
    if (int result = test_wheel_protocol_schema_is_versioned()) return result;
    if (int result = test_indexed_wheel_angle_mapping()) return result;
    if (int result = test_deterministic_wheel_random()) return result;
    return 0;
}
