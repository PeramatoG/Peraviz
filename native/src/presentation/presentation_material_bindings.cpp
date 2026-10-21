#include "presentation/presentation_material_bindings.h"
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/color.hpp>
#include <cmath>
#include "runtime/visual_runtime_types.h"

namespace godot {
// Installs renderer-owned material resources and exact physical inverse routes once per generation.
bool PresentationMaterialBindings::install(size_t count, const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    if (rids.size()!=owners.size() || owners.size()!=scales.size() || routes.size()%2!=0) return false;
    for (int64_t i=0;i<owners.size();++i) if (owners[i]<0 || size_t(owners[i])>=count ||
        rids[i].get_type()!=Variant::RID || !std::isfinite(scales[i]) || scales[i]<0) return false;
    for (int64_t i=0;i<routes.size();i+=2) if (routes[i]<0 || size_t(routes[i])>=count || routes[i+1]<0 || routes[i+1]>=owners.size()) return false;
    clear(); routes_.resize(count); bindings_.reserve(owners.size()); dirty_.reserve(owners.size());
    for (int64_t i=0;i<owners.size();++i) { Binding b; b.rid=rids[i]; b.owner=uint32_t(owners[i]); b.scale=scales[i]; bindings_.push_back(b); }
    for (int64_t i=0;i<routes.size();i+=2) { routes_[routes[i]].push_back(uint32_t(routes[i+1])); ++bindings_[routes[i+1]].users; }
    return true;
}
// Releases RIDs and scene-sized routes before their owning Godot resources are retired.
void PresentationMaterialBindings::clear() { decltype(bindings_)().swap(bindings_); decltype(routes_)().swap(routes_); decltype(dirty_)().swap(dirty_); writes_=avoided_=color_outputs_=unchanged_=0; }
// Suppression preserves physical held values; enabling forces current material values to replay.
size_t PresentationMaterialBindings::set_enabled(bool enabled) {
    size_t writes=0;
    if (enabled && !enabled_) invalidate();
    if (!enabled) for (auto &b:bindings_) if (b.energy!=0) {
        RenderingServer::get_singleton()->material_set_param(b.rid,energy_,0.0f); b.energy=0; ++writes;
    }
    enabled_=enabled;
    return writes;
}
// Invalidates cached renderer mutations without changing native semantic or material ownership.
void PresentationMaterialBindings::invalidate() { for (auto &b:bindings_) b.red=b.green=b.blue=b.energy=-1; }
// Coalesces shared lens RIDs in native main-thread glue; independent pixel lenses remain exact.
void PresentationMaterialBindings::apply(const peraviz::presentation::DensePresentationState &physical, bool suppress_writes) {
    using namespace peraviz::presentation;
    writes_=avoided_=color_outputs_=unchanged_=0; dirty_.clear();
    if (!enabled_) return;
    for (uint32_t index:physical.dirty_indices()) {
        const uint32_t mask=physical.pending_mask(index);
        if (mask & peraviz::runtime::VisualChangeColor) ++color_outputs_;
        // Zoom alone cannot change lens emission; retain topology invalidation and held-state replay.
        if (!(mask & (peraviz::runtime::VisualChangeColor | peraviz::runtime::VisualChangeDimmer |
                peraviz::runtime::VisualChangeMaterial | peraviz::runtime::VisualChangeBeamTopology))) continue;
        if (index<routes_.size()) for (uint32_t material:routes_[index]) {
            auto &b=bindings_[material]; if (!b.dirty) { b.dirty=true; dirty_.push_back(material); }
        }
    }
    auto *server=RenderingServer::get_singleton();
    for (uint32_t index:dirty_) {
        auto &b=bindings_[index]; b.dirty=false;
        if (suppress_writes) continue;
        const auto v=physical.render_values(b.owner);
        const float energy=v[MaterialEnergy]*b.scale;
        const size_t before=writes_;
        if (b.red!=v[Red] || b.green!=v[Green] || b.blue!=v[Blue]) {
            server->material_set_param(b.rid,emission_,Color(v[Red],v[Green],v[Blue],1));
            b.red=v[Red]; b.green=v[Green]; b.blue=v[Blue]; ++writes_; avoided_+=b.users>0?b.users-1:0;
        }
        if (std::abs(b.energy-energy)>std::max(0.00001f,0.00001f*std::abs(b.energy))) {
            server->material_set_param(b.rid,energy_,energy); b.energy=energy;
            ++writes_; avoided_+=b.users>0?b.users-1:0;
        }
        if (writes_==before) ++unchanged_;
    }
}
// Cold renderer-boundary inspection works with headless/dummy drivers that cannot read material RIDs back.
PackedFloat32Array PresentationMaterialBindings::values(const RID &rid) const {
    PackedFloat32Array values;
    for (const auto &b:bindings_) if (b.rid==rid) {
        values.resize(4); auto *v=values.ptrw(); v[0]=b.red; v[1]=b.green; v[2]=b.blue; v[3]=b.energy; break;
    }
    return values;
}
}
