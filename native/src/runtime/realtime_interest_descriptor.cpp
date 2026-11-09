#include "runtime/peraviz_visual_runtime.h"
#include <map>
#include <set>

namespace peraviz::runtime {

// Compiles effective and transport-only replay interests at setup without granting byte ownership.
std::vector<std::pair<uint16_t, std::vector<uint16_t>>> PeravizVisualRuntimeCore::realtime_interest_offsets() const {
    std::map<uint16_t,std::set<uint16_t>> physical;
    for (const auto &[id,state]:universes_) for (int slot:state.interest_offsets) if (slot>=0 && slot<512) physical[id].insert(slot);
    for (const auto &byte:replay_sources_) if (byte.universe_id>=0 && byte.universe_id<=32767 && byte.address>=0 && byte.address<512)
        physical[byte.universe_id].insert(byte.address);
    std::vector<std::pair<uint16_t,std::vector<uint16_t>>> result;
    for (const auto &[id,slots]:physical) result.push_back({id,{slots.begin(),slots.end()}});
    return result;
}

} // namespace peraviz::runtime
