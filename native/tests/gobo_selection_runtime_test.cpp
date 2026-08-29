#include "runtime/peraviz_visual_runtime.h"

#include <cstdint>
#include <cmath>
#include <iostream>
#include <vector>

// Verifies seated Gobo(n) selection emits exact indexed wheel, slot, asset, and dirty-only revision data.
bool test_native_seated_gobo_selection_section() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({90, CompiledSemantic::Unknown, {{10, 9, 0}}, 0, 255, 0.0, 1.0, "Gobo2", "Gobo2"});
    scene.gobo_assets.push_back({5001, 7002, 1, "gobos/star.png", "/cache/star.png", "scene_lease", 64, 64, false, true});
    scene.gobo_assets.push_back({0, 7002, 2, "", "", "open_slot", 0, 0, true, false});
    scene.gobo_bindings.push_back({9001, 1, 77, 7002, 2, 90, CompiledGoboSelectionMode::SeatedStatic, {{0, 127, 1, "Star"}, {128, 255, 2, "Open"}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame selected = runtime.consume_latest_visual_frame();
    int32_t offset = -1;
    for (size_t index = 0; index < selected.descriptors.size(); index += kVisualSectionDescriptorStride) {
        if (selected.descriptors[index] == static_cast<int32_t>(VisualSectionType::GoboSelection)) offset = selected.descriptors[index + 2];
    }
    if (offset < 0 || selected.integers[offset + GoboSelectionWheelId] != 7002 || selected.integers[offset + GoboSelectionWheelInstanceIndex] != 2 || selected.integers[offset + GoboSelectionSlotIndex] != 1 || selected.integers[offset + GoboSelectionAssetId] != 5001) {
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

// Verifies indexed selected-gobo angles emit dirty-only parametric rows in physical degrees.
bool test_native_indexed_gobo_rotation_section() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({91, CompiledSemantic::Unknown, {{10, 10, 0}}, 0, 255, -180.0, 180.0, "Gobo1Pos", "Index"});
    CompiledGoboMotionBinding binding;
    binding.binding_id = 9101; binding.fixture_id = 1; binding.beam_render_target_id = 77;
    binding.wheel_id = 7001; binding.wheel_instance_index = 1; binding.source_program_id = 91;
    binding.semantic_kind = peraviz::gdtf_runtime::GoboSemanticKind::Pos;
    binding.controlled_scope = peraviz::gdtf_runtime::GoboControlledScope::SelectedGobo;
    binding.physical_from = -180.0; binding.physical_to = 180.0; binding.physical_unit = "Angle";
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
        if (first.descriptors[index] == static_cast<int32_t>(VisualSectionType::GoboRotation)) { int_offset = first.descriptors[index + 2]; float_offset = first.descriptors[index + 3]; }
    }
    if (int_offset < 0 || first.integers[int_offset + GoboRotationWheelInstanceIndex] != 1 || std::abs(first.floats[float_offset] - 0.705882f) > 0.01f) return false;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return false;
    dmx[10] = 255;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const SectionedVisualFrame changed = runtime.consume_latest_visual_frame();
    if (changed.descriptors.empty() || runtime.stats().gobo_parametric_updates != 2 || runtime.stats().gobo_topology_updates != 0) return false;
    return true;
}
