#include "presentation/presentation_material_bindings.h"
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/color.hpp>
#include <cmath>
#include <algorithm>
#include "runtime/visual_runtime_types.h"

namespace godot {
// Installs renderer-owned material resources and exact physical inverse routes once per generation.
bool PresentationMaterialBindings::install(size_t count, const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes, bool surface) {
    if (rids.size()!=owners.size() || owners.size()!=scales.size() || routes.size()%2!=0) return false;
    for (int64_t i=0;i<owners.size();++i) if (owners[i]<0 || size_t(owners[i])>=count ||
        rids[i].get_type()!=Variant::RID || !std::isfinite(scales[i]) || scales[i]<0) return false;
    for (int64_t i=0;i<routes.size();i+=2) if (routes[i]<0 || size_t(routes[i])>=count || routes[i+1]<0 || routes[i+1]>=owners.size()) return false;
    clear(); surface_=surface; routes_.resize(count); bindings_.reserve(owners.size()); dirty_.reserve(owners.size());
    for (int64_t i=0;i<owners.size();++i) { Binding b; b.rid=rids[i]; b.owner=uint32_t(owners[i]); b.scale=scales[i]; bindings_.push_back(b); }
    for (int64_t i=0;i<routes.size();i+=2) { routes_[routes[i]].push_back(uint32_t(routes[i+1])); ++bindings_[routes[i+1]].users; }
    return true;
}
// Borrows presentation volume instance RIDs; initial visibility awaits held physical replay.
bool PresentationMaterialBindings::install_surface_instances(const Array &instances) {
    if (!surface_ || size_t(instances.size())!=bindings_.size()) return false;
    for (int64_t i=0;i<instances.size();++i) if (instances[i].get_type()!=Variant::RID) return false;
    surface_instances_.resize(instances.size());
    for (int64_t i=0;i<instances.size();++i) { surface_instances_[i].rid=instances[i]; update_surface_visible(i,true); }
    return true;
}
// Repairs Godot's visibility notification without scene lookup or a worker wait.
void PresentationMaterialBindings::set_surface_visible(int32_t index,bool allowed) {
    if (index<0 || size_t(index)>=surface_instances_.size()) return;
    surface_instances_[index].allowed=allowed;
    update_surface_visible(size_t(index),true);
}
// Suppresses actual draw submission during blackout and conservative receiver culling.
void PresentationMaterialBindings::update_surface_visible(size_t index,bool force) {
    if (index>=surface_instances_.size()) return;
    auto &instance=surface_instances_[index];
    const bool visible=enabled_ && instance.allowed && bindings_[index].energy>0;
    if (force || !instance.known || visible!=instance.visible) {
        RenderingServer::get_singleton()->instance_set_visible(instance.rid,visible);
        instance.visible=visible; instance.known=true;
    }
}
// Releases RIDs and scene-sized routes before their owning Godot resources are retired.
void PresentationMaterialBindings::clear() { decltype(surface_instances_)().swap(surface_instances_); decltype(bindings_)().swap(bindings_); decltype(routes_)().swap(routes_); decltype(dirty_)().swap(dirty_); writes_=avoided_=color_outputs_=unchanged_=0; }
// Suppression preserves physical held values; enabling forces current material values to replay.
size_t PresentationMaterialBindings::set_enabled(bool enabled) {
    size_t writes=0;
    if (enabled && !enabled_) invalidate();
    if (!enabled) for (auto &b:bindings_) if (b.energy!=0) {
        RenderingServer::get_singleton()->material_set_param(b.rid,energy_,0.0f); b.energy=0; ++writes;
    }
    enabled_=enabled;
    for (size_t i=0;i<surface_instances_.size();++i) update_surface_visible(i);
    return writes;
}
// Changes visual gain on borrowed surface RIDs using the last displayed physical energy, including zero recovery.
size_t PresentationMaterialBindings::set_surface_gain(double gain) {
    if (!surface_ || !std::isfinite(gain)) return 0;
    size_t writes=0;
    for (size_t i=0;i<bindings_.size();++i) {
        auto &b=bindings_[i]; b.scale=float(std::max(gain,0.0));
        const float energy=enabled_?b.surface_base*b.scale*shutter(b.owner):0.0f;
        if (b.energy!=energy) {
            RenderingServer::get_singleton()->material_set_param(b.rid,energy_,energy); b.energy=energy; ++writes;
        }
        update_surface_visible(i);
    }
    writes_=writes;
    return writes;
}
// Replays only cached displayed lens energy, preserving optical scales and zero-gain recovery.
size_t PresentationMaterialBindings::set_lens_gain(double gain) {
    if (surface_ || !std::isfinite(gain)) return 0;
    lens_gain_=float(std::max(gain,0.0));
    size_t writes=0;
    for (auto &b:bindings_) {
        const float energy=enabled_?b.lens_base*lens_gain_*shutter(b.owner):0.0f;
        if (b.energy!=energy) {
            RenderingServer::get_singleton()->material_set_param(b.rid,energy_,energy);
            b.energy=energy; ++writes;
        }
    }
    return writes;
}
// Invalidates cached renderer mutations without changing native semantic or material ownership.
void PresentationMaterialBindings::invalidate() { for (auto &b:bindings_) b.red=b.green=b.blue=b.energy=-1; }
// Coalesces shared lens RIDs in native main-thread glue; independent pixel lenses remain exact.
void PresentationMaterialBindings::apply(const peraviz::presentation::DensePresentationState &physical, bool suppress_writes) {
    using namespace peraviz::presentation;
    writes_=avoided_=color_outputs_=unchanged_=0; dirty_.clear();
    if (!enabled_) return;
    for (uint32_t index:physical.dirty_indices()) nominate(index,physical.pending_mask(index));
    auto *server=RenderingServer::get_singleton();
    for (uint32_t index:dirty_) {
        auto &b=bindings_[index]; b.dirty=false;
        if (suppress_writes) continue;
        write(b,physical.render_values(b.owner),server);
    }
}
// Nominates actual resource routes from already completed physical presentation values.
void PresentationMaterialBindings::nominate(uint32_t index,uint32_t mask) {
    if (mask & peraviz::runtime::VisualChangeColor) ++color_outputs_;
    if (!(mask & (peraviz::runtime::VisualChangeColor | peraviz::runtime::VisualChangeDimmer |
            peraviz::runtime::VisualChangeMaterial | peraviz::runtime::VisualChangeBeamTopology))) return;
    if (index<routes_.size()) for (uint32_t material:routes_[index]) {
        auto &b=bindings_[material]; if (!b.dirty) { b.dirty=true; dirty_.push_back(material); }
    }
}
// Applies the same guarded RID mutations for synchronous and immutable completed snapshots.
void PresentationMaterialBindings::write(Binding &b,const peraviz::presentation::RenderValues &v,RenderingServer *server) {
    using namespace peraviz::presentation;
    if (surface_) b.surface_base=v[Visible]>0 ? (v[SpotEnergy]>0 ? v[SpotEnergy] : v[BeamEnergy]) : 0.0f;
    if (!surface_) b.lens_base=v[MaterialEnergy]*b.scale;
    const float energy=(surface_ ? b.surface_base*b.scale : b.lens_base*lens_gain_)*shutter(b.owner);
    const size_t before=writes_;
    if (b.red!=v[Red] || b.green!=v[Green] || b.blue!=v[Blue]) {
        server->material_set_param(b.rid,emission_,Color(v[Red],v[Green],v[Blue],1));
        b.red=v[Red]; b.green=v[Green]; b.blue=v[Blue]; ++writes_; avoided_+=b.users>0?b.users-1:0;
    }
    if (std::abs(b.energy-energy)>std::max(0.00001f,0.00001f*std::abs(b.energy))) {
        server->material_set_param(b.rid,energy_,energy); b.energy=energy;
        ++writes_; avoided_+=b.users>0?b.users-1:0;
    }
    if (surface_) update_surface_visible(size_t(&b-bindings_.data()));
    if (writes_==before) ++unchanged_;
}
// Mutates only cached main-thread RIDs; no worker or authoritative state is consulted here.
void PresentationMaterialBindings::apply_completed(const std::vector<peraviz::presentation::PreparedOutput> &changes,
        const std::vector<peraviz::presentation::RenderValues> &held,bool suppress_writes) {
    writes_=avoided_=color_outputs_=unchanged_=0; dirty_.clear();
    if (!enabled_) return;
    for (const auto &row:changes) nominate(row.index,row.mask);
    auto *server=RenderingServer::get_singleton();
    for (uint32_t index:dirty_) {
        auto &b=bindings_[index]; b.dirty=false;
        if (!suppress_writes) write(b,held[b.owner],server);
    }
}
// Counts cached native surface contributions only at diagnostic report boundaries.
size_t PresentationMaterialBindings::active() const {
    size_t count=0;
    for (size_t i=0;i<bindings_.size();++i) if (enabled_ && bindings_[i].energy>0 &&
        (surface_instances_.empty() || surface_instances_[i].allowed)) ++count;
    return count;
}
// Cold renderer-boundary inspection works with headless/dummy drivers that cannot read material RIDs back.
PackedFloat32Array PresentationMaterialBindings::values(const RID &rid) const {
    PackedFloat32Array values;
    for (const auto &b:bindings_) if (b.rid==rid) {
        values.resize(4); auto *v=values.ptrw(); v[0]=b.red; v[1]=b.green; v[2]=b.blue; v[3]=b.energy; break;
    }
    return values;
}
// Applies only energy multipliers on already owned RIDs, preserving original Color and canonical bases.
void PresentationMaterialBindings::apply_shutters(const std::vector<uint32_t> &owners) {
    writes_=0;
    if (!enabled_) return;
    auto *server=RenderingServer::get_singleton();
    for (uint32_t owner:owners) if (owner<routes_.size()) for (uint32_t index:routes_[owner]) {
        auto &b=bindings_[index];
        const float energy=(surface_?b.surface_base*b.scale:b.lens_base*lens_gain_)*shutter(b.owner);
        if (energy!=b.energy) { server->material_set_param(b.rid,energy_,energy); b.energy=energy; ++writes_; }
        if (surface_) update_surface_visible(index);
    }
}

}
