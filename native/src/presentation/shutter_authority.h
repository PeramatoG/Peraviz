#pragma once
#include "gdtf_runtime/shutter_control_authority.h"

namespace peraviz::presentation {
using ShutterAuthority=gdtf_runtime::ShutterControlSignature;
// Proves full static control compatibility for grouping; random and periodic modes share the same ownership rules.
inline std::unordered_map<int32_t,std::vector<ShutterAuthority>> shutter_authorities(const runtime::CompiledRuntimeScene &scene) {
    std::unordered_map<int32_t,std::vector<ShutterAuthority>> result;
    for (const auto &b:scene.shutter_bindings) result[b.beam_target_id].push_back(gdtf_runtime::shutter_control_signature(b));
    for (auto &[target,entries]:result) std::sort(entries.begin(),entries.end());
    return result;
}
}
