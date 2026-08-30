#include "artnet_sequence_tracker.h"

namespace peraviz::dmx {

// Applies ArtDmx's disabled-zero and ordered 1-through-255 sequence cycle with bounded restart rejection.
ArtNetSequenceDecision ArtNetSequenceTracker::accept(uint16_t universe, uint8_t sequence, ArtNetEndpoint endpoint) {
    State &state = states_[universe];
    const bool source_changed = state.initialized && state.endpoint != endpoint;
    if (!state.initialized || source_changed) {
        state = {endpoint, sequence, sequence != 0, true};
        return {true, source_changed};
    }
    if (sequence == 0) {
        state.ordered = false;
        state.sequence = 0;
        return {true, false};
    }
    if (!state.ordered) {
        state.sequence = sequence;
        state.ordered = true;
        return {true, false};
    }
    const int previous = static_cast<int>(state.sequence) - 1;
    const int incoming = static_cast<int>(sequence) - 1;
    const int forward = (incoming - previous + 255) % 255;
    if (forward == 0 || forward > 127) {
        return {false, false};
    }
    state.sequence = sequence;
    return {true, false};
}

// Clears all ordered stream state at the beginning of a receiver session.
void ArtNetSequenceTracker::reset() {
    states_.clear();
}

} // namespace peraviz::dmx
