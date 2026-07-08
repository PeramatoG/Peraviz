#include "runtime/peraviz_visual_runtime.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

// Reports a visual runtime test failure.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}

// Creates a compiled Dimmer/Pan/Tilt scene with stable fixture-owned IDs.
peraviz::runtime::CompiledRuntimeScene make_scene() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-1", "RegressionFixture", "Mode 1", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    scene.source_programs.push_back({2, CompiledSemantic::Pan, {{10, 1, 0}, {10, 3, 1}}, 0, 65535, -270.0, 270.0, "Pan", "Pan"});
    scene.source_programs.push_back({3, CompiledSemantic::Tilt, {{10, 2, 0}, {10, 4, 1}}, 0, 65535, -135.0, 135.0, "Tilt", "Tilt"});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Dimmer, {{1, 1.0}}});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Pan, {{2, 1.0}}});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Tilt, {{3, 1.0}}});
    return scene;
}

// Verifies the production path emits transform and intensity sections from compiled programs.
int test_compiled_scene_e2e() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_scene());
    std::vector<uint8_t> frame(8, 0);
    frame[0] = 255;
    frame[1] = 0x80;
    frame[3] = 0x00;
    frame[2] = 0x40;
    frame[4] = 0x00;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.descriptors.size() < peraviz::runtime::kVisualSectionDescriptorStride * 2) return fail("Expected transform and intensity sections");
    if (visual.integers.size() < 6 || visual.integers[1] != 101 || visual.integers[4] != 1001) return fail("Expected stable IDs from compiled scene rows");
    if (visual.floats.empty()) return fail("Expected cooked float payloads");
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Unchanged relevant DMX values should not dirty output");
    return 0;
}

// Verifies non-adjacent coarse/fine bytes are assembled as one 16-bit value.
int test_non_adjacent_16_bit_value() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_scene());
    std::vector<uint8_t> frame(8, 0);
    frame[1] = 0xff;
    frame[3] = 0xff;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.floats.empty() || std::fabs(visual.floats[0] - 270.0f) > 0.01f) return fail("Expected non-adjacent 16-bit Pan maximum physical value");
    return 0;
}

// Verifies the source reader accepts more than two ordered bytes through the compiled model.
int test_more_than_two_source_bytes() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-1", "RegressionFixture", "Mode 1", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}, {10, 2, 1}, {10, 4, 2}}, 0, 16777215, 0.0, 1.0, "Dimmer", "Dimmer24"});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Dimmer, {{1, 1.0}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(8, 0xff);
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.descriptors.empty()) return fail("Expected 24-bit source program to emit output");
    return 0;
}

// Verifies one property can name multiple compiled contributors deterministically.
int test_multiple_contributors() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene = make_scene();
    scene.source_programs.push_back({4, CompiledSemantic::Dimmer, {{10, 5, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerVirtual"});
    scene.properties[0].contributors.push_back({4, 0.0});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(8, 0);
    frame[0] = 128;
    frame[5] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected multi-contributor property to emit output");
    return 0;
}

} // namespace

// Runs compiled scene runtime behavior tests.
int main() {
    if (test_compiled_scene_e2e() != 0) return 1;
    if (test_non_adjacent_16_bit_value() != 0) return 1;
    if (test_more_than_two_source_bytes() != 0) return 1;
    if (test_multiple_contributors() != 0) return 1;
    return 0;
}
