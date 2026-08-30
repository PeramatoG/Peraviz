#pragma once

#include "dmx/realtime_universe_mailbox.h"
#include "runtime/peraviz_visual_runtime.h"

#include <cstdint>

namespace peraviz::runtime {

struct RealtimePumpResult {
    int states_submitted = 0;
    uint64_t oldest_receive_us = 0;
};

class RealtimeDmxCoordinator {
public:
    RealtimePumpResult install_subscription(PeravizVisualRuntimeCore &runtime, dmx::RealtimeUniverseMailbox &mailbox) const;
    RealtimePumpResult pump(PeravizVisualRuntimeCore &runtime, dmx::RealtimeUniverseMailbox &mailbox) const;

private:
    static RealtimePumpResult submit_frames(PeravizVisualRuntimeCore &runtime, const std::vector<dmx::DmxFrame> &frames);
};

} // namespace peraviz::runtime
