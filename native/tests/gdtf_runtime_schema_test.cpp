#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "gdtf_runtime/gobo_motion_contract.h"
#include "gdtf_runtime/mode_master.h"
#include "runtime/visual_frame_schema.h"
#include "runtime/wheel_runtime_core.h"

#include <cmath>
#include <iostream>
#include <set>

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

// Verifies every official gobo motion identity remains exact and wheel-indexed.
int test_exact_gobo_motion_identities() {
    using namespace peraviz::gdtf_runtime;
    const char *names[] = {"Gobo1", "Gobo1SelectSpin", "Gobo1SelectShake", "Gobo1SelectEffects", "Gobo1WheelIndex", "Gobo1WheelSpin", "Gobo1WheelShake", "Gobo1WheelRandom", "Gobo1WheelAudio", "Gobo1Pos", "Gobo1PosRotate", "Gobo1PosShake"};
    std::set<GoboSemanticKind> kinds;
    for (const char *name : names) {
        const auto parsed = parse_gobo_semantic(name);
        if (!parsed.recognized || parsed.wheel_number != 1 || !kinds.insert(parsed.kind).second) return fail("Expected a distinct exact Gobo1 semantic identity.");
    }
    const auto second = parse_gobo_semantic("gObO2pOsRoTaTe");
    if (!second.recognized || second.wheel_number != 2 || second.normalized_name != "Gobo2PosRotate") return fail("Expected case-insensitive normalized Gobo2 identity.");
    if (parse_gobo_semantic("GoboPosRotate").recognized || parse_gobo_semantic("Gobo1Rotate").recognized) return fail("Expected shorthand and legacy aliases to remain outside the exact contract.");
    const auto rotate_alias = normalize_attribute_identity(100, "Gobo1Rotate");
    const auto index_alias = normalize_attribute_identity(101, "Gobo1Index");
    if (rotate_alias.known_official || index_alias.known_official || rotate_alias.gobo_kind != GoboSemanticKind::None || index_alias.gobo_kind != GoboSemanticKind::None) return fail("Expected legacy gobo aliases to remain non-official and non-authoritative.");
    return 0;
}

// Verifies normative GDTF DMXValue mirroring, shifting, and validation.
int test_dmx_value_conversion() {
    using namespace peraviz::gdtf_runtime;
    ParsedDmxValue value;
    uint32_t converted = 0;
    if (!parse_gdtf_dmx_value("255/1", value) || !convert_gdtf_dmx_value(value, 2, converted) || converted != 65535) return fail("Expected byte-mirrored 8-to-16-bit conversion.");
    if (!parse_gdtf_dmx_value("255/1s", value) || !convert_gdtf_dmx_value(value, 2, converted) || converted != 65280) return fail("Expected byte-shifted 8-to-16-bit conversion.");
    if (!parse_gdtf_dmx_value("128/1", value) || !convert_gdtf_dmx_value(value, 1, converted) || converted != 128) return fail("Expected native 8-bit conversion.");
    if (parse_gdtf_dmx_value("256/1", value) || parse_gdtf_dmx_value("12/0", value) || parse_gdtf_dmx_value("broken", value)) return fail("Expected malformed DMXValue forms to be rejected.");
    return 0;
}

// Verifies structured ModeMaster paths, defaults, malformed values, and reversed ranges.
int test_mode_master_node_resolution() {
    using namespace peraviz::gdtf_runtime;
    const std::vector<ModeMasterNodeRecord> nodes = {
        {ModeMasterTargetKind::DmxChannel, 7, 7, 11, 2, "Beam_Gobo1"},
        {ModeMasterTargetKind::ChannelFunction, 9, 8, 12, 1, "Beam_Gobo1Pos.Gobo1Pos.IndexFn"},
    };
    ModeMasterCondition condition;
    std::string diagnostic;
    if (!resolve_mode_master_condition("Beam_Gobo1", "", "", nodes, condition, diagnostic) || condition.from != 0 || condition.to != 0 || condition.master_channel_id != 7) return fail("Expected exact DMXChannel Node resolution with official defaults.");
    if (!resolve_mode_master_condition("Beam_Gobo1", "", "255/1s", nodes, condition, diagnostic) || condition.to != 65280) return fail("Expected omitted ModeFrom and shifted ModeTo conversion.");
    if (!resolve_mode_master_condition("Beam_Gobo1", "255/1", "", nodes, condition, diagnostic) || condition.from != 65535 || condition.to != 0) {
        if (diagnostic != "PVZ-GDTF-MODEMASTER-RANGE-INVALID") return fail("Expected omitted ModeTo to apply before reversed-range validation.");
    }
    if (resolve_mode_master_condition("IndexFn", "0/1", "1/1", nodes, condition, diagnostic) || diagnostic != "PVZ-GDTF-MODEMASTER-UNRESOLVED") return fail("Expected suffix-only Node links to remain unresolved.");
    if (resolve_mode_master_condition("Beam_Gobo1..IndexFn", "0/1", "1/1", nodes, condition, diagnostic) || diagnostic != "PVZ-GDTF-MODEMASTER-NODE-MALFORMED") return fail("Expected malformed Node paths to be diagnosed.");
    if (resolve_mode_master_condition("Beam_Gobo1", "bad", "1/1", nodes, condition, diagnostic) || diagnostic != "PVZ-GDTF-MODEMASTER-RANGE-INVALID") return fail("Expected explicit malformed ModeFrom to be diagnosed.");
    return 0;
}

// Verifies overlapping functions are gated inclusively by a DMXChannel ModeMaster.
int test_mode_master_channel_gating() {
    using namespace peraviz::gdtf_runtime;
    std::vector<ChannelFunctionActivation> functions = {
        {1, 0, 0, 255, {}},
        {2, 1, 0, 255, {ModeMasterTargetKind::DmxChannel, 0, 1, 0, 79, 1, "Master", true}},
        {3, 1, 0, 255, {ModeMasterTargetKind::DmxChannel, 0, 1, 80, 159, 1, "Master", true}},
        {4, 1, 0, 255, {ModeMasterTargetKind::DmxChannel, 0, 1, 160, 255, 1, "Master", true}},
    };
    std::vector<uint32_t> values = {79, 127};
    if (!is_channel_function_active(2, functions, values) || is_channel_function_active(3, functions, values)) return fail("Expected inclusive index ModeMaster range.");
    values[0] = 80;
    if (is_channel_function_active(2, functions, values) || !is_channel_function_active(3, functions, values)) return fail("Expected changing only the master to select rotation.");
    values[0] = 255;
    if (!is_channel_function_active(4, functions, values)) return fail("Expected inclusive shake upper boundary.");
    return 0;
}

// Verifies ChannelFunction cascades activate safely and cycles are diagnosed.
int test_mode_master_cascade_and_invalid_graphs() {
    using namespace peraviz::gdtf_runtime;
    std::vector<ChannelFunctionActivation> cascade = {
        {1, 0, 0, 255, {}},
        {2, 1, 0, 255, {ModeMasterTargetKind::DmxChannel, 0, 1, 10, 20, 1, "Master", true}},
        {3, 2, 0, 255, {ModeMasterTargetKind::ChannelFunction, 2, 2, 100, 200, 1, "Function2", true}},
    };
    std::string diagnostic;
    if (!validate_mode_master_graph(cascade, diagnostic) || !is_channel_function_active(3, cascade, {15, 150, 120})) return fail("Expected a valid ChannelFunction dependency cascade.");
    if (is_channel_function_active(3, cascade, {21, 150, 120})) return fail("Expected cascade to require the referenced function to be active.");
    cascade[1].mode_master = {ModeMasterTargetKind::ChannelFunction, 3, 3, 0, 255, 1, "Function3", true};
    if (validate_mode_master_graph(cascade, diagnostic) || diagnostic.find("PVZ-GDTF-MODEMASTER-CYCLE") == std::string::npos) return fail("Expected deterministic cycle diagnosis.");
    cascade[1].mode_master = {ModeMasterTargetKind::Invalid, 0, 0, 0, 0, 1, "Missing", false};
    if (validate_mode_master_graph(cascade, diagnostic) || diagnostic.find("PVZ-GDTF-MODEMASTER-UNRESOLVED") == std::string::npos) return fail("Expected deterministic unresolved dependency diagnosis.");
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

// Verifies protocol v2.2 carries renderer-ready wheel and indexed-gobo rows.
int test_wheel_protocol_schema_is_versioned() {
    const auto schema = peraviz::runtime::make_default_visual_frame_schema(1);
    if (schema.protocol_major != 2 || schema.protocol_minor != 2) {
        return fail("Expected indexed-gobo protocol migration to v2.2.");
    }
    bool saw_selection = false;
    bool saw_motion = false;
    bool saw_gobo_rotation = false;
    for (const auto &section : schema.sections) {
        if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelSelection)) {
            saw_selection = section.row_stride_ints == 8 && section.row_stride_floats == 8;
        }
        if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelMotion)) {
            saw_motion = section.row_stride_ints == 6 && section.row_stride_floats == 4;
        }
        if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::GoboRotation)) {
            saw_gobo_rotation = section.row_stride_ints == 6 && section.row_stride_floats == 1;
        }
    }
    if (!saw_selection || !saw_motion || !saw_gobo_rotation) {
        return fail("Expected migrated wheel row strides in default schema.");
    }
    const auto empty_schema = peraviz::runtime::make_visual_frame_schema(2, {});
    for (const auto &section : empty_schema.sections) if (section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::GoboRotation)) return fail("Scene without Pos must not advertise GoboRotation.");
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
    if (int result = test_exact_gobo_motion_identities()) return result;
    if (int result = test_dmx_value_conversion()) return result;
    if (int result = test_mode_master_node_resolution()) return result;
    if (int result = test_mode_master_channel_gating()) return result;
    if (int result = test_mode_master_cascade_and_invalid_graphs()) return result;
    if (int result = test_stale_schema_generation_is_rejected()) return result;
    if (int result = test_section_bounds_are_validated()) return result;
    if (int result = test_wheel_protocol_schema_is_versioned()) return result;
    if (int result = test_indexed_wheel_angle_mapping()) return result;
    if (int result = test_deterministic_wheel_random()) return result;
    return 0;
}
