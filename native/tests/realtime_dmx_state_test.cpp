#include "dmx/artnet_sequence_tracker.h"
#include "dmx/realtime_subscription.h"
#include "dmx/realtime_universe_mailbox.h"

#include <array>
#include <atomic>
#include <chrono>
#include <iostream>
#include <thread>

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
    if (mailbox.pending_dirty_count() != 1) return fail("dirty universe IDs were not deduplicated");
    const std::vector<DmxFrame> consumed_frames = mailbox.consume_dirty_frames();
    if (consumed_frames.size() != 1 || consumed_frames.front().data[0] != 3) return fail("mailbox did not consume latest state only");
    DmxFrame held;
    if (!mailbox.held(1, held) || held.data[0] != 3) return fail("held state did not survive consume");
    mailbox.set_subscription(RealtimeSubscription::build({{1, {0, 7, 9}}}));
    if (mailbox.held(1, held)) return fail("newly relevant offsets reused an unproven stale snapshot");
    frame[9] = 8;
    if (!mailbox.publish(1, frame.data(), frame.size(), 6, 16)) return fail("fresh payload did not initialize replacement subscription");
    for (uint16_t universe = 100; universe < 31000; ++universe) mailbox.publish(universe, frame.data(), frame.size(), 0, 17);
    if (mailbox.pending_dirty_count() != 1) return fail("unrelated traffic created a scene backlog");
    const auto stats = mailbox.stats();
    if (stats.relevant_packets != 6 || stats.irrelevant_packets < 30000 || stats.unchanged_relevant_packets != 1 || stats.coalesced_states != 3)
        return fail("mailbox counters were unexpected");
    return 0;
}

// Stresses concurrent publish/drain ownership and rejects duplicate delivery of one publication.
int test_mailbox_concurrency() {
    using namespace peraviz::dmx;
    RealtimeUniverseMailbox mailbox;
    mailbox.set_subscription(RealtimeSubscription::build({{1, {0, 1}}}));
    constexpr uint32_t kPublications = 20000;
    std::atomic<bool> producer_done {false};
    std::atomic<bool> failed {false};
    uint32_t last_counter = 0;
    uint16_t last_value = 0;
    std::thread producer([&]() {
        std::array<uint8_t, 512> frame {};
        for (uint32_t value = 0; value < kPublications; ++value) {
            frame[0] = static_cast<uint8_t>(value & 0xffU);
            frame[1] = static_cast<uint8_t>((value >> 8U) & 0xffU);
            mailbox.publish(1, frame.data(), frame.size(), 0, value + 1);
            if ((value & 63U) == 0U) std::this_thread::yield();
        }
        producer_done.store(true, std::memory_order_release);
    });
    while (!producer_done.load(std::memory_order_acquire) || mailbox.pending_dirty_count() > 0) {
        for (const DmxFrame &frame : mailbox.consume_dirty_frames()) {
            const uint16_t value = static_cast<uint16_t>(frame.data[0] | (static_cast<uint16_t>(frame.data[1]) << 8U));
            if (frame.counter <= last_counter || (last_counter > 0 && value < last_value)) failed.store(true, std::memory_order_relaxed);
            last_counter = frame.counter;
            last_value = value;
        }
        std::this_thread::yield();
    }
    producer.join();
    if (failed.load() || last_value != static_cast<uint16_t>(kPublications - 1) || mailbox.pending_dirty_count() != 0)
        return fail("concurrent mailbox delivery duplicated, regressed, or lost the latest publication");

    std::array<uint8_t, 512> frame {};
    frame[0] = 1;
    mailbox.publish(1, frame.data(), frame.size(), 0, 1);
    mailbox.set_subscription(RealtimeSubscription::build({{2, {0}}}));
    mailbox.set_subscription(RealtimeSubscription::build({{1, {0}}}));
    if (mailbox.pending_dirty_count() != 0 || !mailbox.consume_dirty_frames().empty())
        return fail("removed and re-added universe resurrected a stale dirty token");
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
int main() { if (int rc = test_mailbox()) return rc; if (int rc = test_mailbox_concurrency()) return rc; return test_sequence(); }
