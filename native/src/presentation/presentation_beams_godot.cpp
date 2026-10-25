#include "presentation/presentation_state_godot.h"
#include <chrono>

namespace godot {
// Installs setup-time handles only against the current renderer generation; no worker synchronization is needed.
bool PeravizPresentationState::install_beams(int64_t generation,const PackedInt64Array &objects,const PackedFloat64Array &thresholds) {
    if (uint64_t(generation)!=(async_?async_->binding_generation():state_.generation()) || objects.size()!=script_rows_.size()) return false;
    return beams_.install(objects,thresholds);
}
// Revokes weak handles before cold renderer/resource changes; simulation continues independently.
void PeravizPresentationState::clear_beams() { beams_.clear(); }
// Updates presentation policy without passing physical scalar data back from GDScript.
void PeravizPresentationState::set_beam_policy(bool enabled,double multiplier) { beams_.set_policy(enabled,multiplier); }
// Applies one native batch before any numeric buffer is exported, and nominates only fallback rows for scripts.
void PeravizPresentationState::apply_beams(const std::vector<peraviz::presentation::PreparedRenderRow> &rows,bool trace,Dictionary &result) {
    const auto start=trace?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
    size_t fallback=0; const auto stats=beams_.apply(rows,script_rows_.ptrw(),fallback);
    result["script_rows"]=script_rows_; result["script_count"]=int64_t(fallback);
    if (!trace) return;
    result["native_beam_apply_us"]=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    result["native_beam_applied"]=int64_t(stats.applied); result["native_beam_changed"]=int64_t(stats.changed);
    result["native_beam_unchanged"]=int64_t(stats.unchanged); result["native_beam_visibility_writes"]=int64_t(stats.visibility);
    result["native_beam_parameter_writes"]=int64_t(stats.parameters); result["native_beam_dynamic_writes"]=int64_t(stats.dynamic);
    result["native_beam_stale"]=int64_t(stats.stale); result["native_beam_fallback"]=int64_t(fallback);
}
} // namespace godot
