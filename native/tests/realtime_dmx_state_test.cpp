#include "dmx/artnet_sequence_tracker.h"
#include "dmx/realtime_subscription.h"
#include "dmx/realtime_universe_mailbox.h"

#include <array>
#include <iostream>

namespace {

// Reports one deterministic native test failure.
int fail(const char *message) { std::cerr << message << '\n'; return 1; }

// Verifies relevant-slot filtering, first-zero initialization, coalescing, and held-state rehydration.
int test_mailbox() {
    using namespace peraviz::dmx;
    RealtimeUniverseMailbox mailbox;
    mailbox.set_subscription(RealtimeSubscription::build({{1, {0, 7}}, {2, {511}}}));
    std::array<uint8_t, 512> frame {};
    if (!mailbox.publish(1, frame.data(), frame.size(), 1, 10)) return fail("first zero state was not published");
    if (mailbox.publish(9, frame.data(), frame.size(), 1, 11)) return fail("irrelevant universe was published");
    frame[3] = 42;
    if (mailbox.publish(1, frame.data(), frame.size(), 2, 12)) return fail("irrelevant slot dirtied mailbox");
    frame[0] = 1;
    mailbox.publish(1, frame.data(), frame.size(), 3, 13);
    frame[0] = 2; mailbox.publish(1, frame.data(), frame.size(), 4, 14);
    frame[0] = 3; mailbox.publish(1, frame.data(), frame.size(), 5, 15);
    if (mailbox.dirty_universes() != std::vector<uint16_t> {1}) return fail("dirty universe IDs were not deduplicated");
    DmxFrame consumed;
    if (!mailbox.consume(1, consumed) || consumed.data[0] != 3) return fail("mailbox did not consume latest state only");
    DmxFrame held;
    if (!mailbox.held(1, held) || held.data[0] != 3) return fail("held state did not survive consume");
    mailbox.set_subscription(RealtimeSubscription::build({{1, {0, 7, 9}}}));
    if (mailbox.held(1, held)) return fail("newly relevant offsets reused an unproven stale snapshot");
    frame[9] = 8;
    if (!mailbox.publish(1, frame.data(), frame.size(), 6, 16)) return fail("fresh payload did not initialize replacement subscription");
    for (uint16_t universe = 100; universe < 31000; ++universe) mailbox.publish(universe, frame.data(), frame.size(), 0, 17);
    if (mailbox.dirty_universes() != std::vector<uint16_t> {1}) return fail("unrelated traffic created a scene backlog");
    const auto stats = mailbox.stats();
    if (stats.relevant_packets != 6 || stats.irrelevant_packets < 30000 || stats.unchanged_relevant_packets != 1 || stats.coalesced_states != 3)
        return fail("mailbox counters were unexpected");
    return 0;
}

// Verifies ordered ArtDmx acceptance, duplicate/stale rejection, wrap, zero, and source reseeding.
int test_sequence() {
    using peraviz::dmx::ArtNetSequenceTracker;
    using peraviz::dmx::ArtNetEndpoint;
    ArtNetSequenceTracker tracker;
    const ArtNetEndpoint source_a {1, 6454};
    const ArtNetEndpoint source_b {2, 6454};
    if (!tracker.accept(1, 0, source_a).accepted || !tracker.accept(1, 0, source_a).accepted) return fail("sequence zero was rejected");
    if (!tracker.accept(1, 254, source_a).accepted || !tracker.accept(1, 255, source_a).accepted || !tracker.accept(1, 1, source_a).accepted || !tracker.accept(1, 2, source_a).accepted) return fail("ordered sequence or wrap was rejected");
    if (tracker.accept(1, 2, source_a).accepted || tracker.accept(1, 1, source_a).accepted) return fail("duplicate or stale sequence was accepted");
    if (!tracker.accept(1, 0, source_a).accepted || !tracker.accept(1, 200, source_a).accepted) return fail("sequence zero did not reseed ordered state");
    const auto changed = tracker.accept(1, 100, source_b);
    if (!changed.accepted || !changed.source_changed) return fail("source change did not reseed sequence");
    tracker.reset();
    if (!tracker.accept(1, 1, source_b).accepted) return fail("receiver-session reset did not clear sequence state");
    return 0;
}
} // namespace

// Runs deterministic realtime state and ArtDmx sequence tests.
int main() { if (int rc = test_mailbox()) return rc; return test_sequence(); }
