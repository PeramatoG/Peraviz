#include "presentation/presentation_state_godot.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <chrono>
#include <algorithm>

namespace godot {
using namespace peraviz::presentation;
namespace {
// Reads a monotonic clock only for explicitly traced presentation work.
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
}
// Exposes setup-only physical/resource binding and a single renderer-oriented snapshot contract.
void PeravizPresentationState::_bind_methods() {
    ClassDB::bind_method(D_METHOD("install", "ids", "scales", "routes"), &PeravizPresentationState::install);
    ClassDB::bind_method(D_METHOD("invalidate_renderer"), &PeravizPresentationState::invalidate_renderer);
    ClassDB::bind_method(D_METHOD("install_groups", "representatives"), &PeravizPresentationState::install_groups);
    ClassDB::bind_method(D_METHOD("install_render_rows", "membership", "classes"), &PeravizPresentationState::install_render_rows);
    ClassDB::bind_method(D_METHOD("install_materials", "rids", "owners", "scales", "routes"), &PeravizPresentationState::install_materials);
    ClassDB::bind_method(D_METHOD("set_materials_enabled", "enabled"), &PeravizPresentationState::set_materials_enabled);
    ClassDB::bind_method(D_METHOD("material_values", "rid"), &PeravizPresentationState::material_values);
    ClassDB::bind_method(D_METHOD("physical_values", "index"), &PeravizPresentationState::physical_values);
    ClassDB::bind_method(D_METHOD("clear"), &PeravizPresentationState::clear);
    ClassDB::bind_method(D_METHOD("compose", "generation", "descriptors", "integers", "values", "trace"), &PeravizPresentationState::compose);
    ClassDB::bind_method(D_METHOD("get_sizes"), &PeravizPresentationState::get_sizes);
}
// Installs canonical physical routes; renderer-sized buffers are allocated only after render setup.
int64_t PeravizPresentationState::install(const PackedInt32Array &ids, const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    if (ids.size()!=scales.size() || routes.size()%3!=0) return -1;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    outputs.reserve(ids.size()); targets.reserve(routes.size()/3);
    for (int64_t i=0;i<ids.size();++i) outputs.push_back({ids[i],scales[i]});
    for (int64_t i=0;i<routes.size();i+=3) targets.push_back({routes[i],routes[i+1],uint32_t(routes[i+2])});
    if (!state_.install(outputs,targets)) return -1;
    projection_.clear(); materials_.clear(); indices_masks_=PackedInt32Array(); values_=PackedFloat32Array();
    return int64_t(state_.generation());
}
// Retains native Control Group membership as an input to renderer/resource setup.
bool PeravizPresentationState::install_groups(const PackedInt32Array &representatives) {
    std::vector<int32_t> mapping;
    mapping.reserve(representatives.size());
    for (int64_t i=0;i<representatives.size();++i) mapping.push_back(representatives[i]);
    return state_.install_groups(mapping);
}
// Allocates the only published arrays to the actual renderer-row count, never physical count.
bool PeravizPresentationState::install_render_rows(const PackedInt32Array &membership, const PackedInt32Array &classes) {
    if (size_t(membership.size())!=state_.bindings().size()) return false;
    std::vector<uint32_t> mapping; std::vector<RenderPresentationClass> modes;
    for (int64_t i=0;i<membership.size();++i) mapping.push_back(uint32_t(membership[i]));
    for (int64_t i=0;i<classes.size();++i) modes.push_back(RenderPresentationClass(classes[i]));
    if (!projection_.install(mapping,modes)) return false;
    indices_masks_.resize(classes.size()*2); values_.resize(classes.size()*ValueCount);
    state_.invalidate_renderer();
    return true;
}
// Binds existing prepared lens resources without creating per-frame material objects or dictionaries.
bool PeravizPresentationState::install_materials(const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    diagnostic_skip_lens_writes_=OS::get_singleton()->get_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES")=="1";
    return materials_.install(state_.bindings().size(),rids,owners,scales,routes);
}
// Applies presentation suppression without changing held native physical Color/Dimmer.
int64_t PeravizPresentationState::set_materials_enabled(bool enabled) { return int64_t(materials_.set_enabled(enabled)); }
// Supports cold inspection/inverse lookup; never used by the renderer's live row loop.
PackedFloat32Array PeravizPresentationState::physical_values(int32_t index) const {
    PackedFloat32Array result;
    if (index<0 || size_t(index)>=state_.bindings().size()) return result;
    result.resize(ValueCount); const auto values=state_.render_values(uint32_t(index));
    std::copy(values.begin(),values.end(),result.ptrw()); return result;
}
// Reads the cached values committed to a prepared material RID for cold inspection/tests.
PackedFloat32Array PeravizPresentationState::material_values(const RID &rid) const { return materials_.values(rid); }
// Invalidates generation identity and releases all renderer/member/resource buffers.
void PeravizPresentationState::clear() {
    state_.clear(); projection_.clear(); materials_.clear();
    indices_masks_=PackedInt32Array(); values_=PackedFloat32Array();
}
// Replays renderer resources and lens RIDs from exact held physical state.
void PeravizPresentationState::invalidate_renderer() { state_.invalidate_renderer(); projection_.invalidate(); }
// Accumulates changed physical contributions natively and copies only compact dirty renderer rows.
Dictionary PeravizPresentationState::compose(int64_t generation, const PackedInt32Array &descriptors,
        const PackedInt32Array &integers, const PackedFloat32Array &values, bool trace) {
    Dictionary result;
    state_.set_trace_enabled(trace);
    const bool suppress_lenses=trace && diagnostic_skip_lens_writes_;
    // Leaving diagnostic isolation replays exact held values without another DMX packet.
    if (lens_writes_suppressed_ && !suppress_lenses) state_.invalidate_renderer();
    lens_writes_suppressed_=suppress_lenses;
    const int64_t start=trace?now_us():0;
    if (projection_.member_count()!=state_.bindings().size() || !state_.compose_sections(uint64_t(generation),descriptors.ptr(),size_t(descriptors.size()),
            integers.ptr(),size_t(integers.size()),values.ptr(),size_t(values.size()))) { result["valid"]=false; return result; }
    const int64_t physical_us=trace?now_us()-start:0;
    const int64_t projection_start=trace?now_us():0;
    projection_.prepare(state_);
    const int64_t projection_us=trace?now_us()-projection_start:0;
    const int64_t compose_us=physical_us+projection_us;
    const int64_t copy_start=trace?now_us():0;
    auto *indices=indices_masks_.ptrw(); auto *packed=values_.ptrw();
    int64_t count=0;
    for (const auto &row:projection_.prepared()) {
        indices[count*2]=int32_t(row.index); indices[count*2+1]=int32_t(row.mask);
        std::copy(row.values.begin(),row.values.end(),packed+count*ValueCount); ++count;
    }
    const int64_t conversion_us=trace?now_us()-copy_start:0;
    // Godot boundary work is main-thread-only and addresses cached material RIDs, never nodes.
    const int64_t material_start=trace?now_us():0;
    materials_.apply(state_,suppress_lenses);
    const int64_t material_us=trace?now_us()-material_start:0;
    const size_t dirty_count=state_.dirty_indices().size();
    result["valid"]=true; result["generation"]=generation; result["unresolved_rows"]=int64_t(state_.unresolved_rows());
    result["count"]=count; result["indices_masks"]=indices_masks_; result["values"]=values_;
    if (trace) {
        result["physical_dynamic_candidates"]=int64_t(dirty_count);
        result["native_physical_us"]=physical_us; result["native_reduction_us"]=projection_us;
        result["native_compose_us"]=compose_us; result["payload_conversion_us"]=conversion_us;
        result["dirty_count"]=int64_t(dirty_count); result["candidates"]=int64_t(std::max(state_.candidates(),dirty_count));
        result["signature_skipped"]=int64_t(dirty_count)-count;
        result["diagnostic_skip_lens_writes"]=diagnostic_skip_lens_writes_;
        result["native_material_us"]=material_us;
        result["physical_color_outputs"]=int64_t(materials_.color_outputs());
        result["lens_rids_affected"]=int64_t(materials_.affected()); result["lens_rids_unchanged"]=int64_t(materials_.unchanged());
        result["lens_material_writes"]=int64_t(materials_.writes()); result["lens_writes_avoided"]=int64_t(materials_.avoided());
    }
    state_.finish_snapshot(uint64_t(generation));
    return result;
}
// Reports physical native capacities separately from genuinely renderer-sized packed storage.
Dictionary PeravizPresentationState::get_sizes() const {
    Dictionary sizes;
    sizes["diagnostic_skip_lens_writes_active"]=lens_writes_suppressed_;
    sizes["diagnostic_skip_lens_writes_requested"]=diagnostic_skip_lens_writes_;
    sizes["presentation_contract_revision"]=4;
    sizes["extension_build"]=String(__DATE__ " " __TIME__);
    sizes["unique_lens_material_rids"]=int64_t(materials_.size());
    sizes["physical_outputs"]=int64_t(state_.bindings().size()); sizes["render_rows"]=int64_t(projection_.row_count());
    sizes["state_capacity"]=int64_t(state_.state_capacity()); sizes["dirty_capacity"]=int64_t(state_.dirty_capacity());
    sizes["dirty_high_water"]=int64_t(state_.high_water()); sizes["native_buffer_bytes"]=int64_t(state_.buffer_bytes()+projection_.buffer_bytes());
    sizes["packed_buffer_bytes"]=indices_masks_.size()*int64_t(sizeof(int32_t))+values_.size()*int64_t(sizeof(float));
    return sizes;
}
} // namespace godot
