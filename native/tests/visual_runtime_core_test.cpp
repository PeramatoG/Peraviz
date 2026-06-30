#include "runtime/peraviz_visual_runtime.h"

#include <cstdint>
#include <iostream>
#include <vector>

namespace {

// Reports a visual runtime test failure.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}

// Creates a zero-filled DMX frame with the requested channel values.
std::vector<uint8_t> make_frame(uint8_t dimmer, uint8_t pan, uint8_t irrelevant) {
    std::vector<uint8_t> frame(16, 0);
    frame[0] = dimmer;
    frame[1] = pan;
    frame[12] = irrelevant;
    return frame;
}

// Verifies latest-wins coalescing and cooked frame output.
int test_latest_wins_coalescing() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({
        {1, 10, 3, 0, -1, -1, 8, 0.0, 1.0},
        {1, 10, 1, 1, -1, -1, 8, 0.0, 1.0},
    });
    auto first = make_frame(10, 20, 0);
    auto second = make_frame(255, 64, 0);
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty() || static_cast<int>(frame.values[0]) != 1) {
        return fail("Expected one dirty fixture from coalesced latest frame");
    }
    if (frame.stats.packets_coalesced != 1) {
        return fail("Expected one coalesced packet");
    }
    if (frame.values.size() != 1 + peraviz::runtime::kVisualFrameStride) {
        return fail("Unexpected visual frame stride");
    }
    if (frame.values[4] < 0.99f) {
        return fail("Latest dimmer value was not used");
    }
    return 0;
}

// Verifies unused universes are ignored before fixture work.
int test_unused_universe_ignored() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({{1, 10, 3, 0, -1, -1, 8, 0.0, 1.0}});
    auto frame = make_frame(255, 0, 0);
    runtime.submit_universe_frame(99, frame.data(), static_cast<int>(frame.size()));
    if (!runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Unused universe produced visual output");
    }
    if (runtime.stats().universes_ignored != 1) {
        return fail("Unused universe was not counted as ignored");
    }
    return 0;
}

// Verifies irrelevant channel changes do not dirty fixture state.
int test_interest_hash_filters_irrelevant_changes() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({{1, 10, 3, 0, -1, -1, 8, 0.0, 1.0}});
    auto first = make_frame(128, 0, 1);
    auto second = make_frame(128, 0, 200);
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial relevant frame did not dirty fixture");
    }
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    if (!runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Irrelevant channel change dirtied fixture");
    }
    return 0;
}

// Verifies binding rebuilds clear old universe interest state.
int test_rebuild_clears_old_state() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({{1, 10, 3, 0, -1, -1, 8, 0.0, 1.0}});
    auto frame = make_frame(255, 0, 0);
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial binding did not produce output");
    }
    runtime.set_fixture_bindings({{2, 11, 3, 0, -1, -1, 8, 0.0, 1.0}});
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (!runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Old universe remained active after binding rebuild");
    }
    runtime.submit_universe_frame(11, frame.data(), static_cast<int>(frame.size()));
    peraviz::runtime::VisualFrame rebuilt_frame = runtime.consume_latest_visual_frame();
    if (rebuilt_frame.values.empty() || static_cast<int>(rebuilt_frame.values[1]) != 2) {
        return fail("New binding did not produce fixture 2 output");
    }
    return 0;
}

// Verifies a mass fixture update emits exactly the dirty fixture count once.
int test_mass_dirty_fixture_count_and_empty_second_consume() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    std::vector<peraviz::runtime::FixtureChannelBinding> bindings;
    bindings.reserve(80);
    for (int fixture_id = 1; fixture_id <= 80; ++fixture_id) {
        bindings.push_back({fixture_id, 10, 3, fixture_id - 1, -1, -1, 8, 0.0, 1.0});
    }
    runtime.set_fixture_bindings(bindings);
    std::vector<uint8_t> off_frame(128, 0);
    std::vector<uint8_t> on_frame(128, 255);

    runtime.submit_universe_frame(10, off_frame.data(), static_cast<int>(off_frame.size()));
    peraviz::runtime::VisualFrame first_frame = runtime.consume_latest_visual_frame();
    if (first_frame.values.empty() || static_cast<int>(first_frame.values[0]) != 80) {
        return fail("Expected the initial 80-fixture frame to emit exactly 80 dirty fixtures");
    }
    if (!runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Second consume without a submitted frame should be empty");
    }

    runtime.submit_universe_frame(10, on_frame.data(), static_cast<int>(on_frame.size()));
    peraviz::runtime::VisualFrame second_frame = runtime.consume_latest_visual_frame();
    if (second_frame.values.empty() || static_cast<int>(second_frame.values[0]) != 80) {
        return fail("Expected the 80-fixture mass toggle to emit exactly 80 dirty fixtures");
    }
    if (second_frame.values.size() != 1 + (80 * peraviz::runtime::kVisualFrameStride)) {
        return fail("Mass toggle output buffer size did not match the dirty fixture count");
    }
    if (!runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Repeated consume after mass toggle should be empty");
    }
    return 0;
}

// Verifies pan changes with dimmer already on only request transform application.
int test_pan_tilt_only_mask_with_dimmer_on() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({
        {1, 10, 3, 0, -1, -1, 8, 0.0, 1.0},
        {1, 10, 1, 1, -1, -1, 8, 0.0, 1.0},
        {1, 10, 2, 2, -1, -1, 8, 0.0, 1.0},
    });
    std::vector<uint8_t> first(16, 0);
    first[0] = 255;
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial pan fixture state did not emit");
    }
    std::vector<uint8_t> second = first;
    second[1] = 128;
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty()) {
        return fail("Pan-only change did not emit");
    }
    const uint32_t channel_mask = static_cast<uint32_t>(frame.values[2]);
    const uint32_t visual_mask = static_cast<uint32_t>(frame.values[3]);
    if (channel_mask != (1U << static_cast<uint32_t>(peraviz::runtime::VisualChannel::Pan))) {
        return fail("Pan-only change emitted the wrong channel mask");
    }
    if (visual_mask != peraviz::runtime::VisualChangeTransform) {
        return fail("Pan-only change emitted lighting work in the visual mask");
    }
    return 0;
}

// Verifies dimmer-only changes do not request transform work.
int test_dimmer_only_mask() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({
        {1, 10, 3, 0, -1, -1, 8, 0.0, 1.0},
        {1, 10, 1, 1, -1, -1, 8, 0.0, 1.0},
    });
    auto first = make_frame(0, 64, 0);
    auto second = make_frame(255, 64, 0);
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial dimmer fixture state did not emit");
    }
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty()) {
        return fail("Dimmer-only change did not emit");
    }
    const uint32_t channel_mask = static_cast<uint32_t>(frame.values[2]);
    const uint32_t visual_mask = static_cast<uint32_t>(frame.values[3]);
    if (channel_mask != (1U << static_cast<uint32_t>(peraviz::runtime::VisualChannel::Dimmer))) {
        return fail("Dimmer-only change emitted the wrong channel mask");
    }
    if ((visual_mask & peraviz::runtime::VisualChangeDimmer) == 0U || (visual_mask & peraviz::runtime::VisualChangeTransform) != 0U) {
        return fail("Dimmer-only change emitted the wrong visual mask");
    }
    return 0;
}

// Verifies color-only changes request color/material work only.
int test_color_only_mask() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({
        {1, 10, 5, 4, -1, -1, 8, 0.0, 1.0},
        {1, 10, 6, 5, -1, -1, 8, 0.0, 1.0},
        {1, 10, 7, 6, -1, -1, 8, 0.0, 1.0},
    });
    std::vector<uint8_t> first(16, 0);
    std::vector<uint8_t> second = first;
    second[4] = 128;
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial color fixture state did not emit");
    }
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty()) {
        return fail("Color-only change did not emit");
    }
    const uint32_t visual_mask = static_cast<uint32_t>(frame.values[3]);
    if ((visual_mask & peraviz::runtime::VisualChangeColor) == 0U || (visual_mask & peraviz::runtime::VisualChangeTransform) != 0U || (visual_mask & peraviz::runtime::VisualChangeDimmer) != 0U) {
        return fail("Color-only change emitted the wrong visual mask");
    }
    return 0;
}

// Verifies zoom-only changes request zoom work only.
int test_zoom_only_mask() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({{1, 10, 4, 3, -1, -1, 8, 0.0, 1.0}});
    runtime.set_fixture_render_params(1, {10000.0, 25.0, 4.0, 40.0, 5600.0, 1.0, 20.0, true, false});
    std::vector<uint8_t> first(16, 0);
    std::vector<uint8_t> second = first;
    second[3] = 255;
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial zoom fixture state did not emit");
    }
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty()) {
        return fail("Zoom-only change did not emit");
    }
    const uint32_t visual_mask = static_cast<uint32_t>(frame.values[3]);
    if ((visual_mask & peraviz::runtime::VisualChangeZoom) == 0U || (visual_mask & peraviz::runtime::VisualChangeTransform) != 0U || (visual_mask & peraviz::runtime::VisualChangeDimmer) != 0U) {
        return fail("Zoom-only change emitted the wrong visual mask");
    }
    return 0;
}

// Verifies one DMX step of pan still emits a transform update.
int test_single_step_pan_change_is_not_filtered() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.set_fixture_bindings({{1, 10, 1, 1, -1, -1, 8, 0.0, 1.0}});
    std::vector<uint8_t> first(16, 0);
    std::vector<uint8_t> second = first;
    second[1] = 1;
    runtime.submit_universe_frame(10, first.data(), static_cast<int>(first.size()));
    if (runtime.consume_latest_visual_frame().values.empty()) {
        return fail("Initial single-step pan fixture state did not emit");
    }
    runtime.submit_universe_frame(10, second.data(), static_cast<int>(second.size()));
    peraviz::runtime::VisualFrame frame = runtime.consume_latest_visual_frame();
    if (frame.values.empty()) {
        return fail("One-step pan change was incorrectly filtered");
    }
    const uint32_t visual_mask = static_cast<uint32_t>(frame.values[3]);
    if (visual_mask != peraviz::runtime::VisualChangeTransform) {
        return fail("One-step pan change emitted the wrong visual mask");
    }
    return 0;
}

} // namespace

// Runs visual runtime core regression tests.
int main() {
    if (int result = test_latest_wins_coalescing(); result != 0) {
        return result;
    }
    if (int result = test_unused_universe_ignored(); result != 0) {
        return result;
    }
    if (int result = test_interest_hash_filters_irrelevant_changes(); result != 0) {
        return result;
    }
    if (int result = test_rebuild_clears_old_state(); result != 0) {
        return result;
    }
    if (int result = test_mass_dirty_fixture_count_and_empty_second_consume(); result != 0) {
        return result;
    }
    if (int result = test_pan_tilt_only_mask_with_dimmer_on(); result != 0) {
        return result;
    }
    if (int result = test_single_step_pan_change_is_not_filtered(); result != 0) {
        return result;
    }
    if (int result = test_dimmer_only_mask(); result != 0) {
        return result;
    }
    if (int result = test_color_only_mask(); result != 0) {
        return result;
    }
    if (int result = test_zoom_only_mask(); result != 0) {
        return result;
    }
    return 0;
}
