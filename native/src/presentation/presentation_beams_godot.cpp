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
// Installs borrowed MultiMesh RIDs only for this physical binding generation.
bool PeravizPresentationState::install_lenses(int64_t generation,const Array &rids,const Array &owners,const Array &buffers,const Array &scales) {
    if (uint64_t(generation)!=(async_?async_->binding_generation():state_.generation())) return false;
    return lenses_.install(async_?displayed_physical_.size():state_.bindings().size(),rids,owners,buffers,scales);
}
// Revokes native batch routes before their Godot resource owner tears down.
void PeravizPresentationState::clear_lenses() { lenses_.clear(); }
// Visibility signals carry resource policy only, never lighting calculations.
void PeravizPresentationState::set_lens_visible(int32_t batch,int32_t instance,bool visible) { lenses_.set_visible(batch,instance,visible); }
// Coalesced cold visibility changes submit without waiting for another DMX packet.
void PeravizPresentationState::flush_lenses() { lenses_.flush(); }
// Exposes the actual retained instance buffer to focused renderer regression checks.
PackedFloat32Array PeravizPresentationState::lens_buffer(int32_t batch) const { return lenses_.buffer(batch); }
// Binds independently owned surface materials to canonical physical outputs, never aggregate shaft rows.
bool PeravizPresentationState::install_footprints(int64_t generation,const Array &rids,const Array &instances,const PackedInt32Array &owners,
        const PackedFloat32Array &scales,const PackedInt32Array &routes) {
    if (uint64_t(generation)!=(async_?async_->binding_generation():state_.generation())) return false;
    return footprints_.install(async_?displayed_physical_.size():state_.bindings().size(),rids,owners,scales,routes,true) && footprints_.install_surface_instances(instances);
}
// Revokes borrowed surface RIDs before their presentation owner frees them.
void PeravizPresentationState::clear_footprints() { footprints_.clear(); }
// Diagnostic policy suppresses only surface presentation; physical held state remains native.
void PeravizPresentationState::set_footprints_enabled(bool enabled) { footprints_.set_enabled(enabled); }
// Accepts renderer visibility policy only; DMX and physical values remain untouched.
void PeravizPresentationState::set_footprint_visible(int32_t index,bool visible) { footprints_.set_surface_visible(index,visible); }
// Exposes committed presentation cache values for deterministic lifecycle checks.
PackedFloat32Array PeravizPresentationState::footprint_values(const RID &rid) const { return footprints_.values(rid); }
} // namespace godot
