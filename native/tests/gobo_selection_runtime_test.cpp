#include "runtime/peraviz_visual_runtime.h"

#include <cstdint>
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
