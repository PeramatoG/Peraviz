#include "presentation/presentation_state_godot.h"
#include <godot_cpp/classes/light3d.hpp>
#include <godot_cpp/core/object.hpp>
#include <chrono>

namespace godot {
using namespace peraviz::presentation;
// Retains weak renderer handles only; all canonical resources remain owned by Godot.
bool PeravizPresentationState::install_shutter_resources(int64_t generation,const PackedInt64Array &beams,
        const PackedFloat64Array &thresholds,const Array &group_materials,const PackedInt64Array &lights,const PackedInt32Array &owners) {
    if (uint64_t(generation)!=(async_?async_->binding_generation():state_.generation()) || beams.size()!=int64_t(projection_.row_count()) || lights.size()!=owners.size()) return false;
    std::vector<std::vector<uint64_t>> routes(async_?displayed_physical_.size():state_.bindings().size());
    for (int64_t i=0;i<lights.size();++i) {
        if (owners[i]<0 || size_t(owners[i])>=routes.size() || !Object::cast_to<Light3D>(ObjectDB::get_instance(uint64_t(lights[i])))) return false;
        routes[owners[i]].push_back(uint64_t(lights[i]));
    }
    if (!shutter_beams_.install(beams,thresholds) || !shutter_beams_.install_group_materials(group_materials)) return false;
    shutter_lights_=std::move(routes);
    shutter_rows_.reserve(projection_.row_count()); shutter_fallback_.resize(projection_.row_count());
    shutter_row_slots_.assign(projection_.row_count(),-1);
    shutters_.invalidate(); return true;
}
// Changes presentation/suppression policy without touching source state or temporal phase.
void PeravizPresentationState::set_shutter_policy(bool enabled,double beam_gain,double surface_gain) {
    if (shutter_enabled_!=enabled || shutter_surface_gain_!=surface_gain || shutter_beam_gain_!=beam_gain) shutters_.invalidate();
    shutter_beam_gain_=beam_gain; shutter_enabled_=enabled; shutter_surface_gain_=surface_gain;
    shutter_beams_.set_policy(enabled,1);
}
// Adopts only persistent parameter changes from the native source graph, never light scalars.
void PeravizPresentationState::ingest_shutters(const peraviz::runtime::SectionedVisualFrame &frame) {
    shutters_.ingest(frame.descriptors.data(),frame.descriptors.size(),frame.integers.data(),frame.integers.size(),frame.floats.data(),frame.floats.size());
}
// Advances a compact active set on the presentation thread; no DMX evaluation, topology or resources are created.
int64_t PeravizPresentationState::advance_shutters(int64_t generation,double test_now) {
    if (uint64_t(generation)!=(async_?async_->binding_generation():state_.generation())) return -1;
    if (!shutters_.pending()) return 0;
    const auto start=std::chrono::steady_clock::now();
    const auto &changed=shutters_.tick(test_now);
    if (changed.empty()) {
        ++shutter_ticks_;
        shutter_us_+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
        return 0;
    }
    const auto &envelopes=shutters_.envelopes();
    shutter_rows_.clear();
    for (uint32_t owner:changed) {
        if (owner>=projection_.membership().size()) continue;
        const auto row=projection_.membership()[owner];
        if (row<held_renderer_.size() && held_renderer_valid_[row] && row<shutter_row_slots_.size() && shutter_row_slots_[row]<0) {
            auto value=held_renderer_[row]; value.mask=peraviz::runtime::VisualChangeDimmer;
            const double base=value.values[BeamIntensity]*shutter_beam_gain_;
            value.values[BeamIntensity]=float((shutter_beams_.uses_group_material(row)?std::max(base,0.0):std::clamp(base,0.0,50.0))*envelopes[owner]);
            shutter_row_slots_[row]=int32_t(shutter_rows_.size()); shutter_rows_.push_back(value);
        }
        if (owner<shutter_lights_.size()) {
            const auto physical=async_?displayed_physical_[owner]:state_.render_values(owner);
            const double base=physical[SpotEnergy]>0?physical[SpotEnergy]:physical[BeamEnergy];
            const double energy=shutter_enabled_?base*shutter_surface_gain_*envelopes[owner]:0;
            for (uint64_t object:shutter_lights_[owner]) if (auto *light=Object::cast_to<Light3D>(ObjectDB::get_instance(object)))
                if (light->get_param(Light3D::PARAM_ENERGY)!=energy) light->set_param(Light3D::PARAM_ENERGY,float(energy));
        }
    }
    size_t fallback=0;
    const auto beam_stats=shutter_beams_.apply(shutter_rows_,shutter_fallback_.data(),fallback);
    shutter_beam_writes_+=beam_stats.parameters+beam_stats.visibility;
    for (const auto &row:shutter_rows_) shutter_row_slots_[row.index]=-1;
    if (!lens_writes_suppressed_) { materials_.apply_shutters(changed); shutter_lens_submissions_+=lenses_.apply_shutters(changed); }
    footprints_.apply_shutters(changed);
    shutter_material_writes_+=materials_.writes()+footprints_.writes(); ++shutter_ticks_;
    shutter_us_+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    return int64_t(changed.size());
}
// Exposes the independent presentation envelope for deterministic output/retirement probes.
PackedFloat32Array PeravizPresentationState::shutter_values() const {
    PackedFloat32Array out; out.resize(shutters_.envelopes().size());
    std::copy(shutters_.envelopes().begin(),shutters_.envelopes().end(),out.ptrw()); return out;
}
}
