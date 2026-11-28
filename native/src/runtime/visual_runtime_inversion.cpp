#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <array>
namespace peraviz::runtime {
// Invert the assembled value for this consumer; the shared source cache remains unmodified.
PeravizVisualRuntimeCore::EvaluationResult
PeravizVisualRuntimeCore::mechanical_value(UniverseState &universe, uint32_t source, bool inverted) {
    auto value = evaluate_cached_source(universe, source);
    if (!inverted || !value.valid)
        return value;
    const auto &installed = *universe.source_bindings[source];
    const auto &program = installed.program;
    value.raw_value = uint32_t(installed.mapping->maximum) - value.raw_value;
    const double local =
        installed.mapping->span > 0
            ? std::clamp((double(value.raw_value) - program.dmx_from) / installed.mapping->span, 0.0, 1.0)
            : double(value.raw_value) * installed.mapping->inverse_maximum;
    value.normalized_value = float(local);
    value.physical_value =
        float(program.physical_from + (program.physical_to - program.physical_from) * local);
    return value;
}
// Gate inverted own ranges using unchanged master bytes and the existing bounded activation semantics.
bool PeravizVisualRuntimeCore::mechanical_active(UniverseState &universe, uint32_t source, uint32_t own_raw,
                                                 size_t depth) {
    if (source >= universe.source_bindings.size() || depth > universe.source_bindings.size())
        return false;
    const auto &program = universe.source_bindings[source]->program;
    if (own_raw < program.dmx_from || own_raw > program.dmx_to)
        return false;
    const auto &condition = program.activation;
    using Kind = gdtf_runtime::ModeMasterTargetKind;
    if (!condition.valid || condition.target_kind == Kind::Invalid)
        return false;
    if (condition.target_kind == Kind::None)
        return true;
    const int32_t master = universe.plan.source(source).master;
    if (master < 0 || size_t(master) >= universe.source_bindings.size())
        return false;
    const auto value = evaluate_cached_source(universe, master);
    const auto raw = value.raw_value;
    return value.valid && raw >= condition.from && raw <= condition.to &&
           (condition.target_kind != Kind::ChannelFunction ||
            mechanical_active(universe, master, raw, depth + 1));
}
// Change flags under exclusive ownership, invalidating held inputs without rebuilding the scene.
bool PeravizVisualRuntimeCore::set_fixture_inversions(const std::vector<int32_t> &triples) {
    if (triples.size() % 3)
        return false;
    for (size_t i = 0; i < triples.size(); i += 3)
        if (!render_params_by_fixture_.count(triples[i]) || triples[i + 1] < 0 || triples[i + 1] > 1 ||
            triples[i + 2] < 0 || triples[i + 2] > 1)
            return false;
    std::unordered_map<int32_t, std::array<bool, 2>> changes;
    for (size_t i = 0; i < triples.size(); i += 3)
        changes[triples[i]] = {triples[i + 1] != 0, triples[i + 2] != 0};
    for (auto &[id, universe] : universes_) {
        bool changed = false;
        for (auto &property : universe.properties) {
            const auto change = changes.find(property.property.fixture_id);
            if (change == changes.end() || (property.parameter != SemanticParameter::Pan &&
                                            property.parameter != SemanticParameter::Tilt))
                continue;
            const bool next = change->second[property.parameter == SemanticParameter::Pan ? 0 : 1];
            changed |= property.inverted != next;
            property.inverted = next;
        }
        if (changed && universe.has_last_relevant_values) {
            universe.has_last_relevant_values = false;
            universe.has_pending_frame = true;
        }
    }
    return true;
}
} // namespace peraviz::runtime
