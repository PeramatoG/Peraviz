#include "runtime/compiled_runtime_scene_codec.h"
#include "runtime/peraviz_visual_runtime.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

// Verifies seated Gobo(n) selection emits exact indexed wheel, slot, asset, and
// dirty-only revision data.
bool test_native_seated_gobo_selection_section() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({90, CompiledSemantic::Unknown, {{10, 9, 0}}, 0, 255, 0.0, 1.0, "Gobo2", "Gobo2"});
    scene.gobo_assets.push_back({5001, 7002, 1, "gobos/star.png", "/cache/star.png", "scene_lease", 64, 64, false, true});
    scene.gobo_assets.push_back({0, 7002, 2, "", "", "open_slot", 0, 0, true, false});
    scene.gobo_bindings.push_back(
        {9001, 1, 77, 7002, 2, 90, CompiledGoboSelectionMode::SeatedStatic, {{0, 127, 1, "Star"}, {128, 255, 2, "Open"}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame selected = runtime.consume_latest_visual_frame();
    int32_t offset = -1;
    for (size_t index = 0; index < selected.descriptors.size(); index += kVisualSectionDescriptorStride) {
        if (selected.descriptors[index] == static_cast<int32_t>(VisualSectionType::GoboSelection))
            offset = selected.descriptors[index + 2];
    }
    if (offset < 0 || selected.integers[offset + GoboSelectionWheelId] != 7002 ||
        selected.integers[offset + GoboSelectionWheelInstanceIndex] != 2 || selected.integers[offset + GoboSelectionSlotIndex] != 1 ||
        selected.integers[offset + GoboSelectionAssetId] != 5001) {
        std::cerr << "Expected exact seated Gobo2 slot and asset identity" << std::endl;
        return false;
    }
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) {
        std::cerr << "Unchanged seated gobo must not emit another row" << std::endl;
        return false;
    }
    dmx[9] = 200;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame open = runtime.consume_latest_visual_frame();
    offset = open.descriptors.empty() ? -1 : open.descriptors[2];
    if (offset < 0 || open.integers[offset + GoboSelectionSlotIndex] != 2 || open.integers[offset + GoboSelectionAssetId] != 0) {
        std::cerr << "Expected open slot to preserve exact index with asset zero" << std::endl;
        return false;
    }
    if (runtime.stats().gobo_selection_rows != 2 || runtime.stats().gobo_topology_updates != 2) {
        std::cerr << "Expected two dirty-only gobo selection updates" << std::endl;
        return false;
    }
    return true;
}

// Verifies indexed selected-gobo angles emit dirty-only parametric rows in
// physical degrees.
bool test_native_indexed_gobo_rotation_section() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({91, CompiledSemantic::Unknown, {{10, 10, 0}}, 0, 255, -180.0, 180.0, "Gobo1Pos", "Index"});
    CompiledGoboMotionBinding binding;
    binding.binding_id = 9101;
    binding.fixture_id = 1;
    binding.beam_render_target_id = 77;
    binding.wheel_id = 7001;
    binding.wheel_instance_index = 1;
    binding.source_program_id = 91;
    binding.semantic_kind = peraviz::gdtf_runtime::GoboSemanticKind::Pos;
    binding.controlled_scope = peraviz::gdtf_runtime::GoboControlledScope::SelectedGobo;
    binding.physical_from = -180.0;
    binding.physical_to = 180.0;
    binding.physical_unit = "Angle";
    binding.scalar_evaluable = true;
    scene.gobo_motion_bindings.push_back(binding);
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[10] = 128;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame first = runtime.consume_latest_visual_frame();
    int32_t int_offset = -1, float_offset = -1;
    for (size_t index = 0; index < first.descriptors.size(); index += kVisualSectionDescriptorStride) {
        if (first.descriptors[index] == static_cast<int32_t>(VisualSectionType::GoboRotation)) {
            int_offset = first.descriptors[index + 2];
            float_offset = first.descriptors[index + 3];
        }
    }
    if (int_offset < 0 || first.integers[int_offset + GoboRotationWheelInstanceIndex] != 1 ||
        std::abs(first.floats[float_offset] - 0.705882f) > 0.01f)
        return false;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty())
        return false;
    dmx[10] = 255;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame changed = runtime.consume_latest_visual_frame();
    if (changed.descriptors.empty() || runtime.stats().gobo_parametric_updates != 2 || runtime.stats().gobo_topology_updates != 0)
        return false;
    return true;
}

// Verifies v7 packed setup round-trips DPT, gobo selection, Pos, and activation
// identities.
bool test_v7_packed_runtime_scene_round_trip() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-a", "type", "mode", 0, 1});
    scene.fixtures.push_back({2, "fixture-b", "type", "mode", 0, 101});
    scene.source_programs.push_back({10, CompiledSemantic::Pan, {{0, 0, 0}, {0, 1, 1}}, 0, 65535, -270, 270});
    scene.source_programs.push_back({11, CompiledSemantic::Tilt, {{0, 2, 0}, {0, 3, 1}}, 0, 65535, -135, 135});
    scene.source_programs.push_back({12, CompiledSemantic::Dimmer, {{0, 4, 0}}, 0, 255, 0, 1});
    scene.source_programs.push_back({13, CompiledSemantic::Zoom, {{0, 5, 0}}, 0, 255, 10, 50});
    scene.source_programs.push_back({14, CompiledSemantic::Unknown, {{0, 6, 0}}, 0, 255, 0, 1});
    scene.source_programs.push_back({15, CompiledSemantic::Unknown, {{0, 7, 0}}, 0, 255, -180, 180});
    scene.source_programs.back().activation = {peraviz::gdtf_runtime::ModeMasterTargetKind::DmxChannel, 0, 14, 128, 255, 1, {}, true, 0};
    scene.source_programs.push_back({20, CompiledSemantic::Dimmer, {{0, 104, 0}}, 0, 255, 0, 1});
    scene.properties.push_back({100, 1, 1001, 0, CompiledSemantic::Pan, {{10, 1.0}}});
    scene.properties.push_back({101, 1, 1002, 0, CompiledSemantic::Tilt, {{11, 1.0}}});
    scene.properties.push_back({102, 1, 1003, 2001, CompiledSemantic::Dimmer, {{12, 1.0}}});
    scene.properties.push_back({103, 1, 1004, 2001, CompiledSemantic::Zoom, {{13, 1.0}}});
    scene.properties.push_back({200, 2, 2003, 3001, CompiledSemantic::Dimmer, {{20, 1.0}}});
    scene.gobo_bindings.push_back({300, 1, 2001, 7001, 1, 14, CompiledGoboSelectionMode::SeatedStatic, {{0, 255, 1}}});
    CompiledGoboMotionBinding motion;
    motion.binding_id = 301;
    motion.fixture_id = 1;
    motion.beam_render_target_id = 2001;
    motion.wheel_id = 7001;
    motion.wheel_instance_index = 1;
    motion.source_program_id = 15;
    motion.semantic_kind = peraviz::gdtf_runtime::GoboSemanticKind::Pos;
    motion.controlled_scope = peraviz::gdtf_runtime::GoboControlledScope::SelectedGobo;
    motion.physical_from = -180;
    motion.physical_to = 180;
    motion.physical_unit = "Angle";
    motion.scalar_evaluable = true;
    scene.gobo_motion_bindings.push_back(motion);
    const PackedCompiledRuntimeScene packed = encode_compiled_runtime_scene(scene);
    const CompiledRuntimeSceneDecodeResult decoded = decode_compiled_runtime_scene(packed.integers, packed.floats);
    if (!decoded.valid || decoded.consumed_integers != packed.integers.size() || decoded.scene.fixtures.size() != 2 ||
        decoded.scene.source_programs.size() != scene.source_programs.size() ||
        decoded.scene.properties.size() != scene.properties.size() || decoded.scene.gobo_bindings.size() != 1 ||
        decoded.scene.gobo_motion_bindings.size() != 1)
        return false;
    for (size_t index = 0; index < scene.source_programs.size(); ++index) {
        const auto &expected = scene.source_programs[index];
        const auto &actual = decoded.scene.source_programs[index];
        if (actual.program_id != expected.program_id || actual.sources.size() != expected.sources.size())
            return false;
        for (size_t source = 0; source < expected.sources.size(); ++source)
            if (actual.sources[source].universe_id != expected.sources[source].universe_id ||
                actual.sources[source].address != expected.sources[source].address ||
                actual.sources[source].byte_order != expected.sources[source].byte_order)
                return false;
    }
    if (decoded.scene.source_programs[5].activation.master_program_id != 14 || decoded.scene.properties[0].component_id != 1001 ||
        decoded.scene.properties[2].render_target_id != 2001)
        return false;
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(decoded.scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[6] = 200;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    runtime.consume_latest_visual_frame();
    dmx[0] = 255;
    dmx[1] = 255;
    dmx[2] = 128;
    dmx[4] = 255;
    dmx[5] = 255;
    dmx[7] = 255;
    dmx[104] = 255;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    const SectionedVisualFrame frame = runtime.consume_latest_visual_frame();
    bool transform = false, intensity = false, optics = false, rotation = false;
    bool fixture_a_intensity = false, fixture_b_intensity = false;
    for (size_t x = 0; x < frame.descriptors.size(); x += kVisualSectionDescriptorStride) {
        const auto type = static_cast<VisualSectionType>(frame.descriptors[x]);
        transform |= type == VisualSectionType::GeometryTransform;
        intensity |= type == VisualSectionType::EmitterIntensity;
        optics |= type == VisualSectionType::BeamOptics;
        rotation |= type == VisualSectionType::GoboRotation;
        if (type == VisualSectionType::EmitterIntensity) {
            const int32_t rows = frame.descriptors[x + 1], offset = frame.descriptors[x + 2];
            for (int32_t row = 0; row < rows; ++row) {
                const int32_t target = frame.integers[static_cast<size_t>(offset + row * 3 + EmitterIntensityTargetId)];
                fixture_a_intensity |= target == 2001;
                fixture_b_intensity |= target == 3001;
            }
        }
    }
    std::vector<int32_t> truncated = packed.integers;
    truncated.pop_back();
    return transform && intensity && optics && rotation && fixture_a_intensity && fixture_b_intensity &&
           !decode_compiled_runtime_scene(truncated, packed.floats).valid;
}

// Verifies master-only transitions activate, suppress, and reassert indexed Pos
// rows.
bool test_native_gobo_pos_mode_master_transitions() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 0, 1});
    CompiledDmxSourceProgram master{40, CompiledSemantic::Unknown, {{0, 0, 0}}, 0, 255, 0, 1};
    CompiledDmxSourceProgram pos{41, CompiledSemantic::Unknown, {{0, 1, 0}}, 0, 255, -180, 180};
    pos.activation = {peraviz::gdtf_runtime::ModeMasterTargetKind::DmxChannel, 0, 40, 128, 255, 1, {}, true, 0};
    scene.source_programs = {master, pos};
    CompiledGoboMotionBinding binding;
    binding.binding_id = 42;
    binding.fixture_id = 1;
    binding.beam_render_target_id = 77;
    binding.wheel_id = 7;
    binding.wheel_instance_index = 1;
    binding.source_program_id = 41;
    binding.semantic_kind = peraviz::gdtf_runtime::GoboSemanticKind::Pos;
    binding.controlled_scope = peraviz::gdtf_runtime::GoboControlledScope::SelectedGobo;
    binding.physical_from = -180;
    binding.physical_to = 180;
    binding.physical_unit = "Angle";
    binding.scalar_evaluable = true;
    scene.gobo_motion_bindings.push_back(binding);
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[1] = 200;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    if (!runtime.consume_latest_visual_frame().descriptors.empty())
        return false;
    dmx[0] = 200;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    if (runtime.consume_latest_visual_frame().descriptors.empty())
        return false;
    dmx[0] = 0;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    if (!runtime.consume_latest_visual_frame().descriptors.empty())
        return false;
    dmx[0] = 200;
    runtime.submit_universe_frame(0, dmx.data(), 512);
    return !runtime.consume_latest_visual_frame().descriptors.empty() && runtime.stats().gobo_parametric_updates == 2;
}
