#include "dmx/latency_histogram.h"
#include "runtime/realtime_dmx_coordinator.h"

#include <array>
#include <cmath>
#include <iostream>
#include <string>

namespace {

// Emits a useful failure when the sustained-state regression fails.
bool check(bool condition, const char *message) {
    if (!condition) std::cerr << "realtime stability: " << message << '\n';
    return condition;
}

// Verifies resetting fixed histograms separates a slow interval from a fast lifetime.
bool test_latency_intervals() {
    peraviz::dmx::LatencyWindows latency;
    for (int index = 0; index < 100000; ++index) latency.observe(10, true);
    const auto first = latency.consume_interval();
    if (!check(first.samples == 100000 && first.maximum_us == 10 && first.percentile(95) == 10, "first interval incorrect")) return false;
    if (!check(latency.consume_interval().samples == 0, "empty interval retained old samples")) return false;
    latency.observe(100000, true);
    const auto slow = latency.consume_interval();
    if (!check(slow.samples == 1 && slow.percentile(50) == 100000 && slow.maximum_us == 100000, "slow interval hidden by history")) return false;
    if (!check(latency.lifetime.samples == 100001 && latency.lifetime.percentile(95) == 16, "lifetime was reset with interval")) return false;
    latency.observe(20, false);
    return check(latency.consume_interval().samples == 0 && latency.lifetime.samples == 100002, "trace OFF collected interval samples");
}

// Repeatedly coalesces three universes, drains latest values, and replaces generations.
bool test_mailbox_soak() {
    using namespace peraviz::dmx;
    RealtimeUniverseMailbox mailbox;
    auto subscription = RealtimeSubscription::build({{1, {0, 1}}, {2, {0, 1}}, {3, {0, 1}}});
    mailbox.set_subscription(subscription);
    std::array<uint8_t, 512> data {};
    for (uint32_t iteration = 0; iteration < 10000; ++iteration) {
        for (uint16_t burst = 0; burst < 4; ++burst) {
            const uint16_t value = static_cast<uint16_t>(iteration * 4 + burst);
            data[0] = static_cast<uint8_t>(value);
            data[1] = static_cast<uint8_t>(value >> 8);
            for (uint16_t universe = 1; universe <= 3; ++universe) mailbox.publish(universe, data.data(), data.size(), 0, iteration + 1);
            if (!check(mailbox.pending_dirty_count() == 3, "mailbox appended duplicate tokens")) return false;
        }
        const auto frames = mailbox.consume_dirty_frames();
        if (!check(frames.size() == 3 && mailbox.pending_dirty_count() == 0, "drain lost a universe")) return false;
        for (const auto &frame : frames) {
            DmxFrame held;
            if (!check(frame.data[0] == data[0] && frame.data[1] == data[1] && mailbox.held(frame.universe_id, held) && held.data == frame.data, "latest or held semantics lost")) return false;
        }
        if (iteration % 100 == 0) {
            data[0] ^= 1;
            mailbox.publish(1, data.data(), data.size(), 0, iteration + 1);
            mailbox.set_subscription(subscription);
            if (!check(mailbox.consume_dirty_frames().empty(), "generation retained dirty token")) return false;
        }
    }
    const auto stats = mailbox.stats();
    if (!check(stats.allocated_slots == 3 && stats.pending_high_water == 3 && stats.coalesced_states >= 90000, "mailbox storage/counters not bounded")) return false;
    data[0] ^= 1;
    mailbox.publish(1, data.data(), data.size(), 0, 1);
    mailbox.reset_session();
    DmxFrame held;
    return check(mailbox.consume_dirty_frames().empty() && !mailbox.held(1, held) && mailbox.publish(1, data.data(), data.size(), 0, 2), "stop/start retained stale input or lost subscription");
}

// Builds fifty physical color outputs sharing source authority, without fixture-name logic.
peraviz::runtime::CompiledRuntimeScene make_fanout_scene() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "synthetic", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    scene.source_programs.push_back({2, CompiledSemantic::ColorAddRed, {{10, 1, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_R", "Red"});
    scene.properties.push_back({101, 1, 11, 21, CompiledSemantic::Dimmer, {{1, 1.0}}});
    for (int index = 0; index < 50; ++index) {
        CompiledColorTargetProgram target;
        target.fixture_id = 1;
        target.color_target_id = 2000 + index;
        target.additive_source = true;
        target.beam_render_target_id = 1000 + index;
        target.inputs.push_back({2, CompiledSemantic::ColorAddRed, 0.0, false});
        scene.color_targets.push_back(target);
    }
    return scene;
}

// Checks scene-size state and frame payload bounds across sustained native fan-out/rebuilds.
bool test_native_fanout_soak() {
    using namespace peraviz::runtime;
    PeravizVisualRuntimeCore runtime;
    const auto scene = make_fanout_scene();
    runtime.install_compiled_scene(scene);
    std::array<uint8_t, 512> data {};
    RuntimeStateSizes warm {};
    size_t frame_bound = 0;
    for (int iteration = 0; iteration < 2000; ++iteration) {
        data[0] = static_cast<uint8_t>(iteration);
        data[1] = static_cast<uint8_t>(iteration * 3);
        runtime.submit_universe_frame(10, data.data(), data.size());
        const auto frame = runtime.consume_latest_visual_frame();
        size_t color_rows = 0;
        for (size_t offset = 0; offset < frame.descriptors.size(); offset += kVisualSectionDescriptorStride) {
            if (frame.descriptors[offset] == static_cast<int32_t>(VisualSectionType::EmitterColor)) color_rows += frame.descriptors[offset + 1];
        }
        if (!check(color_rows == 50, "fan-out lost physical outputs")) return false;
        const size_t frame_size = frame.descriptors.size() + frame.integers.size() + frame.floats.size();
        if (iteration == 0) { warm = runtime.state_sizes(); frame_bound = frame_size; }
        if (!check(frame_size <= frame_bound && runtime.state_sizes() == warm, "native state grew after warmup")) return false;
        if (!check(runtime.consume_latest_visual_frame().descriptors.empty(), "consumed frame retained dirty work")) return false;
        if (iteration % 100 == 99) runtime.install_compiled_scene(scene);
    }
    runtime.clear();
    for (const auto &[key, count] : runtime.state_sizes()) {
        if (std::string(key) == "diagnostic_capacity") continue; // vector capacity may be reused after clear.
        if (!check(count == 0, "runtime clear retained scene state")) return false;
    }
    return true;
}

// Reproduces warning growth from a changing coarse byte with a missing fine byte.
bool test_short_payload_warning_bound() {
    using namespace peraviz::runtime;
    auto scene = make_fanout_scene();
    scene.color_targets.clear();
    scene.source_programs[0].sources.push_back({10, 7, 1});
    scene.source_programs[0].dmx_to = 65535;
    PeravizVisualRuntimeCore runtime;
    for (int generation = 0; generation < 3; ++generation) {
        runtime.install_compiled_scene(scene);
        RuntimeStateSizes warm {};
        for (int iteration = 0; iteration < 3000; ++iteration) {
            const uint8_t value = static_cast<uint8_t>(iteration);
            runtime.submit_universe_frame(10, &value, 1);
            runtime.consume_latest_visual_frame();
            if (iteration == 0) warm = runtime.state_sizes();
            if (!check(runtime.state_sizes() == warm, "short payload appended warnings per evaluation")) return false;
        }
        if (!check(warm[11].second == 1, "missing byte warning was lost or duplicated")) return false;
    }
    return true;
}

} // namespace

// Runs bounded soak regressions within the existing native runtime test executable.
bool test_realtime_stability() {
    return test_latency_intervals() && test_mailbox_soak() && test_native_fanout_soak() && test_short_payload_warning_bound();
}
