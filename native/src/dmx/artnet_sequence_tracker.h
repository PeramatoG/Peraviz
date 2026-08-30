#pragma once

#include <cstdint>
#include <unordered_map>

namespace peraviz::dmx {

struct ArtNetSequenceDecision {
    bool accepted = false;
    bool source_changed = false;
};

struct ArtNetEndpoint {
    uint32_t ipv4 = 0;
    uint16_t port = 0;
    // Compares compact endpoint identities without formatting text.
    bool operator==(const ArtNetEndpoint &other) const { return ipv4 == other.ipv4 && port == other.port; }
    // Reports whether compact endpoint identities differ.
    bool operator!=(const ArtNetEndpoint &other) const { return !(*this == other); }
};

class ArtNetSequenceTracker {
public:
    ArtNetSequenceDecision accept(uint16_t universe, uint8_t sequence, ArtNetEndpoint endpoint);
    void reset();

private:
    struct State { ArtNetEndpoint endpoint; uint8_t sequence = 0; bool ordered = false; bool initialized = false; };
    std::unordered_map<uint16_t, State> states_;
};

} // namespace peraviz::dmx
