#include "runtime/realtime_dmx_coordinator.h"

#include "dmx/realtime_subscription.h"

#include <algorithm>

namespace peraviz::runtime {

// Installs authoritative compiled interests and rehydrates proven held receiver state.
RealtimePumpResult RealtimeDmxCoordinator::install_subscription(PeravizVisualRuntimeCore &runtime, dmx::RealtimeUniverseMailbox &mailbox) const {
    mailbox.set_subscription(dmx::RealtimeSubscription::build(runtime.realtime_interest_offsets()));
    return submit_frames(runtime, mailbox.held_states());
}

// Drains and submits only bounded dirty mailbox states to the native visual runtime.
RealtimePumpResult RealtimeDmxCoordinator::pump(PeravizVisualRuntimeCore &runtime, dmx::RealtimeUniverseMailbox &mailbox) const {
    return submit_frames(runtime, mailbox.consume_dirty_frames());
}

// Submits a bounded frame batch and retains its oldest receive timestamp for latency measurement.
RealtimePumpResult RealtimeDmxCoordinator::submit_frames(PeravizVisualRuntimeCore &runtime, const std::vector<dmx::DmxFrame> &frames) {
    RealtimePumpResult result;
    result.states_submitted = static_cast<int>(frames.size());
    for (const dmx::DmxFrame &frame : frames) {
        runtime.submit_universe_frame(frame.universe_id, frame.data.data(), frame.length);
        if (frame.last_rx_us > 0 && (result.oldest_receive_us == 0 || frame.last_rx_us < result.oldest_receive_us)) result.oldest_receive_us = frame.last_rx_us;
    }
    return result;
}

} // namespace peraviz::runtime
