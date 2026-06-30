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
    if (frame.values[3] < 0.99f) {
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
    return 0;
}
