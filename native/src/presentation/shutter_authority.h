#pragma once
#include "runtime/visual_runtime_types.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <unordered_map>

namespace peraviz::presentation {
using ShutterAuthority = std::array<int64_t,11>;
// Compares exact declared timing without floating-point ordering ambiguities or hash collisions.
inline int64_t shutter_bits(double value) { int64_t bits; std::memcpy(&bits,&value,sizeof(bits)); return bits; }
// Proves shared source, activation identity, waveform and all declared timing at scene setup only.
inline std::unordered_map<int32_t,std::vector<ShutterAuthority>> shutter_authorities(const runtime::CompiledRuntimeScene &scene) {
    std::unordered_map<int32_t,std::vector<ShutterAuthority>> result;
    for (const auto &b:scene.shutter_bindings)
        result[b.beam_target_id].push_back({b.source_program_id,b.shutter_index,int64_t(b.wave),b.status,int64_t(b.dmx_from),int64_t(b.dmx_to),
            shutter_bits(b.duration),shutter_bits(b.duty),shutter_bits(b.offset),shutter_bits(b.physical_from),shutter_bits(b.physical_to)});
    for (auto &[target,entries]:result) std::sort(entries.begin(),entries.end());
    return result;
}
}
