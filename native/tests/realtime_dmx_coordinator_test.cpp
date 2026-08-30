#include "runtime/realtime_dmx_coordinator.h"

#include <array>
#include <iostream>

namespace {

// Builds one native Dimmer scene whose compiled source owns the requested offsets.
peraviz::runtime::CompiledRuntimeScene make_realtime_scene(bool include_second_offset) {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    scene.properties.push_back({101, 1, 11, 21, CompiledSemantic::Dimmer, {{1, 1.0}}});
    if (include_second_offset) {
        scene.source_programs.push_back({2, CompiledSemantic::Pan, {{10, 1, 0}}, 0, 255, -270.0, 270.0, "Pan", "Pan"});
        scene.properties.push_back({102, 1, 12, 22, CompiledSemantic::Pan, {{2, 1.0}}});
    }
    return scene;
}

} // namespace

// Verifies compiled interests, latest-state pumping, filtering, and native generation rehydration end to end.
bool test_realtime_dmx_coordinator_path() {
    using namespace peraviz::dmx;
    using namespace peraviz::runtime;
    RealtimeUniverseMailbox mailbox;
    RealtimeDmxCoordinator coordinator;
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_realtime_scene(false));
    if (coordinator.install_subscription(runtime, mailbox).states_submitted != 0) return false;

    std::array<uint8_t, 512> frame {};
    if (!mailbox.publish(10, frame.data(), frame.size(), 0, 1)) return false;
    if (coordinator.pump(runtime, mailbox).states_submitted != 1 || runtime.consume_latest_visual_frame().descriptors.empty()) return false;
    const uint64_t submitted_after_zero = runtime.stats().packets_submitted;
    if (mailbox.publish(10, frame.data(), frame.size(), 0, 2) || coordinator.pump(runtime, mailbox).states_submitted != 0 || runtime.stats().packets_submitted != submitted_after_zero) return false;
    frame[7] = 90;
    if (mailbox.publish(10, frame.data(), frame.size(), 0, 3) || coordinator.pump(runtime, mailbox).states_submitted != 0) return false;
    if (mailbox.publish(99, frame.data(), frame.size(), 0, 4) || coordinator.pump(runtime, mailbox).states_submitted != 0) return false;

    frame[0] = 1; mailbox.publish(10, frame.data(), frame.size(), 0, 5);
    frame[0] = 2; mailbox.publish(10, frame.data(), frame.size(), 0, 6);
    frame[0] = 3; mailbox.publish(10, frame.data(), frame.size(), 0, 7);
    frame[0] = 4; mailbox.publish(10, frame.data(), frame.size(), 0, 8);
    if (coordinator.pump(runtime, mailbox).states_submitted != 1) return false;
    const SectionedVisualFrame latest = runtime.consume_latest_visual_frame();
    if (latest.descriptors.empty()) return false;

    PeravizVisualRuntimeCore rebuilt;
    rebuilt.install_compiled_scene(make_realtime_scene(false));
    if (coordinator.install_subscription(rebuilt, mailbox).states_submitted != 1 || rebuilt.consume_latest_visual_frame().descriptors.empty()) return false;

    PeravizVisualRuntimeCore expanded;
    expanded.install_compiled_scene(make_realtime_scene(true));
    if (coordinator.install_subscription(expanded, mailbox).states_submitted != 0) return false;
    frame[1] = 128;
    if (!mailbox.publish(10, frame.data(), frame.size(), 0, 9) || coordinator.pump(expanded, mailbox).states_submitted != 1) return false;
    expanded.consume_latest_visual_frame();

    PeravizVisualRuntimeCore narrowed;
    narrowed.install_compiled_scene(make_realtime_scene(false));
    if (coordinator.install_subscription(narrowed, mailbox).states_submitted != 1 || narrowed.consume_latest_visual_frame().descriptors.empty()) return false;
    return true;
}
