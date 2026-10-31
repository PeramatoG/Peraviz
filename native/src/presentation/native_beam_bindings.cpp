#include "presentation/native_beam_bindings.h"
#include "runtime/visual_runtime_types.h"
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <unordered_map>
#include <godot_cpp/core/object.hpp>
#include <algorithm>
#include <cmath>

namespace godot {
namespace {
// Godot resources are mutated exclusively on its presentation thread, never by the native coordinator.
bool main_thread() { auto *os=OS::get_singleton(); return os->get_thread_caller_id()==os->get_main_thread_id(); }
}
// Installs weak, generation-scoped object identities; Godot retains all scene/resource ownership.
bool NativeBeamBindings::install(const PackedInt64Array &objects,const PackedFloat64Array &thresholds) {
    if (!main_thread() || objects.size()!=thresholds.size()) return false;
    for (int64_t i=0;i<objects.size();++i) if (!std::isfinite(thresholds[i]) || thresholds[i]<0 ||
            (objects[i] && !Object::cast_to<MeshInstance3D>(ObjectDB::get_instance(uint64_t(objects[i]))))) return false;
    clear(); entries_.resize(objects.size());
    for (int64_t i=0;i<objects.size();++i) { entries_[i].object=uint64_t(objects[i]); entries_[i].threshold=thresholds[i]; count_+=objects[i]!=0; }
    return true;
}
// Coalesces already compatible shared material RIDs at the cold renderer boundary.
bool NativeBeamBindings::install_group_materials(const Array &materials) {
    if (size_t(materials.size())!=entries_.size()) return false;
    std::unordered_map<uint64_t,int32_t> slots;
    for (int64_t i=0;i<materials.size();++i) if (materials[i].get_type()==Variant::RID) {
        RID rid=materials[i]; if (!rid.is_valid()) continue;
        auto found=slots.emplace(rid.get_id(),int32_t(groups_.size()));
        if (found.second) groups_.push_back({rid,{},{}});
        entries_[i].group=found.first->second;
    }
    return true;
}
// Replays temporal overrides after another presentation path writes the same retained renderer resource.
void NativeBeamBindings::invalidate(uint32_t row) {
    if (row>=entries_.size()) return;
    auto &entry=entries_[row]; entry.known=false;
    if (entry.group>=0) groups_[entry.group].known=false;
}
// Releases weak bindings before renderer nodes can be replaced or destroyed.
void NativeBeamBindings::clear() { std::vector<Entry>().swap(entries_); std::vector<Group>().swap(groups_); count_=0; }
// Invalidates derived mutation signatures at presentation-policy boundaries without touching simulation.
void NativeBeamBindings::set_policy(bool enabled,double multiplier) {
    multiplier=std::isfinite(multiplier)?std::max(multiplier,0.0):0.0f;
    if (enabled_!=enabled || multiplier_!=multiplier) for (auto &entry:entries_) entry.known=false;
    enabled_=enabled; multiplier_=multiplier;
}
// Applies final native rows directly to the same Vector Prism nodes and exact instance uniforms.
NativeBeamApplyStats NativeBeamBindings::apply(const std::vector<peraviz::presentation::PreparedRenderRow> &rows,int32_t *fallback,size_t &fallback_count) {
    using namespace peraviz::presentation;
    NativeBeamApplyStats stats; fallback_count=0;
    const bool enabled=enabled_ && count_ && main_thread();
    for (size_t i=0;i<rows.size();++i) {
        const auto &row=rows[i]; Entry *entry=row.index<entries_.size()?&entries_[row.index]:nullptr;
        if (!enabled || !entry || !entry->object || (row.mask & (peraviz::runtime::VisualChangeZoom | peraviz::runtime::VisualChangeBeamTopology))) {
            if (entry) entry->known=false;
            fallback[fallback_count++]=int32_t(i); continue;
        }
        auto *beam=Object::cast_to<MeshInstance3D>(ObjectDB::get_instance(entry->object));
        if (!beam) { ++stats.stale; entry->object=0; entry->known=false; --count_; fallback[fallback_count++]=int32_t(i); continue; }
        const auto &v=row.values;
        const double base=double(v[BeamIntensity])*multiplier_;
        const double intensity=entry->group>=0?std::max(base,0.0):std::clamp(base,0.0,50.0);
        const bool visible=intensity>entry->threshold;
        bool changed=false;
        // Node visibility stays authoritative so ancestor transforms, culling and tree visibility remain exact.
        if (beam->is_visible()!=visible) { beam->set_visible(visible); ++stats.visibility; changed=true; }
        if (visible) {
            const Color dynamic(v[Red],v[Green],v[Blue],intensity);
            if (!entry->known) { beam->set_instance_shader_parameter(maximum_,50.0f); ++stats.parameters; changed=true; }
            Group *group=entry->group>=0?&groups_[entry->group]:nullptr;
            if (group ? (!group->known || group->dynamic!=dynamic) : (!entry->known || entry->dynamic!=dynamic)) {
                if (group) { RenderingServer::get_singleton()->material_set_param(group->rid,group_dynamic_,dynamic); group->dynamic=dynamic; group->known=true; }
                else beam->set_instance_shader_parameter(dynamic_,dynamic);
                entry->dynamic=dynamic;
                ++stats.parameters; ++stats.dynamic; changed=true;
            }
            entry->known=true;
        }
        ++stats.applied; if (changed) ++stats.changed; else ++stats.unchanged;
    }
    return stats;
}
} // namespace godot
