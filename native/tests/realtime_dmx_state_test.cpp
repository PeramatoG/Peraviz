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
    const auto stats = mailbox.stats();
    if (stats.relevant_packets != 5 || stats.irrelevant_packets != 1 || stats.unchanged_relevant_packets != 1 || stats.coalesced_states != 3)
        return fail("mailbox counters were unexpected");
    return 0;
}

// Verifies ordered ArtDmx acceptance, duplicate/stale rejection, wrap, zero, and source reseeding.
int test_sequence() {
    using peraviz::dmx::ArtNetSequenceTracker;
    ArtNetSequenceTracker tracker;
    if (!tracker.accept(1, 0, "a").accepted || !tracker.accept(1, 0, "a").accepted) return fail("sequence zero was rejected");
    if (!tracker.accept(1, 254, "a").accepted || !tracker.accept(1, 255, "a").accepted || !tracker.accept(1, 1, "a").accepted || !tracker.accept(1, 2, "a").accepted) return fail("ordered sequence or wrap was rejected");
    if (tracker.accept(1, 2, "a").accepted || tracker.accept(1, 1, "a").accepted) return fail("duplicate or stale sequence was accepted");
    const auto changed = tracker.accept(1, 200, "b");
    if (!changed.accepted || !changed.source_changed) return fail("source change did not reseed sequence");
    return 0;
}
} // namespace

// Runs deterministic realtime state and ArtDmx sequence tests.
int main() { if (int rc = test_mailbox()) return rc; return test_sequence(); }
