#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_frame_schema.h"

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
    frame.metadata = {peraviz::runtime::kVisualProtocolVersion, 6, 0, 0, 0};
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
    frame.metadata = {peraviz::runtime::kVisualProtocolVersion, 1, 1, 0, 0,
                      static_cast<int>(peraviz::runtime::VisualSectionType::EmitterIntensity), 2, 10, 0, 0};
    frame.values = {1.0f, 2.0f, 3.0f, 4.0f};
    const auto result = peraviz::runtime::validate_sectioned_visual_frame(schema, frame);
    if (result.valid) {
        return fail("Expected section metadata overrun to be rejected.");
    }
    return 0;
}

} // namespace

// Runs the native GDTF runtime schema foundation tests.
int main() {
    if (int result = test_two_gobo_wheels_remain_independent()) return result;
    if (int result = test_stale_schema_generation_is_rejected()) return result;
    if (int result = test_section_bounds_are_validated()) return result;
    return 0;
}
