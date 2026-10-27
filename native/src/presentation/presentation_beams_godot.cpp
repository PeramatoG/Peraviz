#include "presentation/presentation_state_godot.h"
#include <chrono>
#include <algorithm>

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
    for (const auto &row:rows) if (row.index<held_renderer_.size()) {
        held_renderer_[row.index]=row; held_renderer_[row.index].mask=0; held_renderer_valid_[row.index]=true;
    }
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
// Presentation-only gain replays displayed lens caches; it never retires or polls native work.
int64_t PeravizPresentationState::set_lens_emission_gain(double gain) {
    lenses_.set_gain(gain);
    return int64_t(materials_.set_lens_gain(gain));
}
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
// Replays displayed values only; never retires, polls, waits for, or modifies a native worker.
Dictionary PeravizPresentationState::replay_presentation_gains(bool shafts,bool surfaces,double surface_gain,bool trace) {
    const auto start=trace?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
    Dictionary result;
    if (surfaces) result["surface_gain_writes"]=int64_t(footprints_.set_surface_gain(surface_gain));
    if (shafts) {
        gain_rows_.clear();
        for (size_t i=0;i<held_renderer_.size();++i) if (held_renderer_valid_[i]) gain_rows_.push_back(held_renderer_[i]);
        apply_beams(gain_rows_,trace,result);
        auto *indices=indices_masks_.ptrw(); auto *values=values_.ptrw();
        for (size_t i=0;i<gain_rows_.size();++i) {
            indices[2*i]=int32_t(gain_rows_[i].index); indices[2*i+1]=0;
            std::copy(gain_rows_[i].values.begin(),gain_rows_[i].values.end(),values+i*peraviz::presentation::ValueCount);
        }
        result["indices_masks"]=indices_masks_; result["values"]=values_; result["count"]=int64_t(gain_rows_.size());
        result["generation"]=int64_t(async_?async_->binding_generation():state_.generation());
        result["gain_replay"]=true;
    }
    if (trace) result["gain_replay_us"]=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    return result;
}
} // namespace godot
