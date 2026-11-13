#pragma once
#include "scene_model.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_runtime_types.h"
#include <map>
#include <unordered_map>
#include <unordered_set>

namespace peraviz::gdtf_runtime {
enum class AutoSpanPolicy { Off, AutoSafe, AutoOverlap };
AutoSpanPolicy parse_auto_span_policy(const std::string &value, bool *valid = nullptr);
const char *auto_span_policy_id(AutoSpanPolicy policy);
struct RuntimeRoutingOptions {
    AutoSpanPolicy policy = AutoSpanPolicy::AutoSafe;
    std::unordered_set<std::string> auto_span_fixture_uuids;
};
using FixtureTypeCache = std::unordered_map<std::string,CompiledGdtfFixtureType>;
const CompiledGdtfFixtureType &cached_fixture_type(const SceneModel::FixturePatch &patch, FixtureTypeCache &cache);
struct FixtureRoutingDecision { bool span=false, strict_partial=false; std::string error; };
struct AutoSpanPlan {
    std::map<std::string,FixtureRoutingDecision> fixtures;
    std::vector<runtime::CompiledDmxByteSource> replay_sources;
    std::vector<runtime::CompiledRuntimeDiagnostic> diagnostics;
};
using AutoSpanEligibility = bool (*)(const CompiledGdtfFixtureType &);
AutoSpanPlan plan_auto_span(const SceneModel &scene,int universe_offset,const RuntimeRoutingOptions &options,
                           FixtureTypeCache &cache,AutoSpanEligibility eligible);
// Removes whole unavailable controls/dependency groups after intensity authority has been classified.
void retain_strict_controls(runtime::CompiledRuntimeScene &scene,const std::unordered_set<int32_t> &unavailable);
}
