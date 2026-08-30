#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>

namespace peraviz::dmx {

struct ArtNetSequenceDecision {
    bool accepted = false;
    bool source_changed = false;
};

class ArtNetSequenceTracker {
public:
    ArtNetSequenceDecision accept(uint16_t universe, uint8_t sequence, const std::string &endpoint);

private:
    struct State { std::string endpoint; uint8_t sequence = 0; bool ordered = false; };
    std::unordered_map<uint16_t, State> states_;
};

} // namespace peraviz::dmx
