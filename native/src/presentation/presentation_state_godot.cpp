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
    ClassDB::bind_method(D_METHOD("install_beams", "generation", "objects", "thresholds"), &PeravizPresentationState::install_beams);
    ClassDB::bind_method(D_METHOD("install_lenses", "generation", "rids", "owners", "buffers", "scales"), &PeravizPresentationState::install_lenses);
    ClassDB::bind_method(D_METHOD("clear_lenses"), &PeravizPresentationState::clear_lenses);
    ClassDB::bind_method(D_METHOD("set_lens_visible", "batch", "instance", "visible"), &PeravizPresentationState::set_lens_visible);
    ClassDB::bind_method(D_METHOD("flush_lenses"), &PeravizPresentationState::flush_lenses);
    ClassDB::bind_method(D_METHOD("lens_buffer", "batch"), &PeravizPresentationState::lens_buffer);
    ClassDB::bind_method(D_METHOD("clear_beams"), &PeravizPresentationState::clear_beams);
    ClassDB::bind_method(D_METHOD("set_beam_policy", "enabled", "multiplier"), &PeravizPresentationState::set_beam_policy);
    ClassDB::bind_method(D_METHOD("clear"), &PeravizPresentationState::clear);
    ClassDB::bind_method(D_METHOD("compose", "generation", "descriptors", "integers", "values", "trace"), &PeravizPresentationState::compose);
    ClassDB::bind_method(D_METHOD("consume_runtime", "runtime", "generation", "schema_generation", "trace", "poll_only"), &PeravizPresentationState::consume_runtime,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("get_sizes"), &PeravizPresentationState::get_sizes);
}
// Installs canonical physical routes; renderer-sized buffers are allocated only after render setup.
int64_t PeravizPresentationState::install(const PackedInt32Array &ids, const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    retire_async(false); clear_beams(); clear_lenses();
    const String mode=OS::get_singleton()->get_environment("PERAVIZ_NATIVE_EVALUATION");
    async_disabled_=mode=="serial"; async_forced_=mode=="parallel";
    displayed_physical_.clear(); deferred_domains_={}; resume_pending_=false;
    if (ids.size()!=scales.size() || routes.size()%3!=0) return -1;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    outputs.reserve(ids.size()); targets.reserve(routes.size()/3);
    for (int64_t i=0;i<ids.size();++i) outputs.push_back({ids[i],scales[i]});
    for (int64_t i=0;i<routes.size();i+=3) targets.push_back({routes[i],routes[i+1],uint32_t(routes[i+2])});
    if (!state_.install(outputs,targets)) return -1;
    pipeline_.clear(); projection_.clear(); materials_.clear(); indices_masks_=PackedInt32Array(); values_=PackedFloat32Array();
    fixture_ids_.clear(); fixture_ids_.reserve(targets.size());
    return int64_t(state_.generation());
}
// Retains native Control Group membership as an input to renderer/resource setup.
bool PeravizPresentationState::install_groups(const PackedInt32Array &representatives) {
    retire_async();
    std::vector<int32_t> mapping;
    mapping.reserve(representatives.size());
    for (int64_t i=0;i<representatives.size();++i) mapping.push_back(representatives[i]);
    return state_.install_groups(mapping);
}
// Allocates the only published arrays to the actual renderer-row count, never physical count.
bool PeravizPresentationState::install_render_rows(const PackedInt32Array &membership, const PackedInt32Array &classes) {
    retire_async();
    if (size_t(membership.size())!=state_.bindings().size()) return false;
    std::vector<uint32_t> mapping; std::vector<RenderPresentationClass> modes;
    for (int64_t i=0;i<membership.size();++i) mapping.push_back(uint32_t(membership[i]));
    for (int64_t i=0;i<classes.size();++i) modes.push_back(RenderPresentationClass(classes[i]));
    if (!projection_.install(mapping,modes)) return false;
    clear_beams(); script_rows_.resize(classes.size());
    indices_masks_.resize(classes.size()*2); values_.resize(classes.size()*ValueCount);
    state_.invalidate_renderer();
    return true;
}
// Binds existing prepared lens resources without creating per-frame material objects or dictionaries.
bool PeravizPresentationState::install_materials(const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    retire_async();
    diagnostic_skip_lens_writes_=OS::get_singleton()->get_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES")=="1";
    return materials_.install(state_.bindings().size(),rids,owners,scales,routes);
}
// Applies presentation suppression without changing held native physical Color/Dimmer.
int64_t PeravizPresentationState::set_materials_enabled(bool enabled) { retire_async(); lenses_.set_enabled(enabled); return int64_t(materials_.set_enabled(enabled)); }
// Supports cold inspection/inverse lookup; never used by the renderer's live row loop.
PackedFloat32Array PeravizPresentationState::physical_values(int32_t index) const {
    PackedFloat32Array result;
    const size_t count=async_?displayed_physical_.size():state_.bindings().size();
    if (index<0 || size_t(index)>=count) return result;
    result.resize(ValueCount); const auto values=async_?displayed_physical_[size_t(index)]:state_.render_values(uint32_t(index));
    std::copy(values.begin(),values.end(),result.ptrw()); return result;
}
// Reads the cached values committed to a prepared material RID for cold inspection/tests.
PackedFloat32Array PeravizPresentationState::material_values(const RID &rid) const { return materials_.values(rid); }
// Invalidates generation identity and releases all renderer/member/resource buffers.
void PeravizPresentationState::clear() {
    retire_async(false); clear_beams(); clear_lenses(); script_rows_=PackedInt32Array(); displayed_physical_.clear(); deferred_domains_={}; resume_pending_=false;
    std::vector<int32_t>().swap(fixture_ids_);
    pipeline_.clear(); state_.clear(); projection_.clear(); materials_.clear();
    indices_masks_=PackedInt32Array(); values_=PackedFloat32Array();
}
// Replays renderer resources and lens RIDs from exact held physical state.
void PeravizPresentationState::invalidate_renderer() { retire_async(); state_.invalidate_renderer(); projection_.invalidate(); lenses_.invalidate(); }
// Accumulates changed physical contributions natively and copies only compact dirty renderer rows.
Dictionary PeravizPresentationState::compose(int64_t generation, const PackedInt32Array &descriptors,
        const PackedInt32Array &integers, const PackedFloat32Array &values, bool trace) {
    retire_async();
    Dictionary result;
    begin_snapshot(trace);
    const int64_t start=trace?now_us():0;
    if (projection_.member_count()!=state_.bindings().size() || !state_.compose_sections(uint64_t(generation),descriptors.ptr(),size_t(descriptors.size()),
            integers.ptr(),size_t(integers.size()),values.ptr(),size_t(values.size()))) { result["valid"]=false; return result; }
    const int64_t physical_us=trace?now_us()-start:0;
    const int64_t projection_start=trace?now_us():0;
    projection_.prepare(state_);
    const int64_t projection_us=trace?now_us()-projection_start:0;
    return publish(generation,trace,physical_us,projection_us);
}
// Applies diagnostic transitions before native evaluation or explicit held-state replay.
void PeravizPresentationState::begin_snapshot(bool trace) {
    if (!async_) state_.set_trace_enabled(trace);
    const bool suppress_lenses=trace && diagnostic_skip_lens_writes_;
    // Leaving diagnostic isolation replays exact held values without another DMX packet.
    if (lens_writes_suppressed_!=suppress_lenses) { retire_async(); state_.invalidate_renderer(); }
    lens_writes_suppressed_=suppress_lenses;
}
// Applies final main-thread beam/material resources and packs unchanged renderer-row contracts.
Dictionary PeravizPresentationState::publish(int64_t generation, bool trace, int64_t physical_us, int64_t projection_us) {
    Dictionary result;
    apply_beams(projection_.prepared(),trace,result);
    const bool suppress_lenses=lens_writes_suppressed_;
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
    lenses_.apply(state_,suppress_lenses,trace);
    if (trace) result.merge(lenses_.stats(),true);
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
// Evaluates, composes and reduces without exporting intermediate physical lighting scalars.
Dictionary PeravizPresentationState::consume_runtime(const Ref<PeravizVisualRuntime> &runtime,
        int64_t generation, int32_t schema_generation, bool trace, bool poll_only) {
    Dictionary result;
    if (runtime.is_null() || runtime->schema_generation()!=schema_generation ||
            uint64_t(generation)!=(async_?async_->binding_generation():state_.generation())) {
        result["valid"]=false; return result;
    }
    if (async_) return poll_async(runtime,generation,schema_generation,trace);
    if (!runtime->async_available()) { result["valid"]=false; return result; }
    if (poll_only && !resume_pending_ && deferred_domains_.descriptors.empty()) { result["valid"]=true; result["pending"]=true; return result; }
    resume_pending_=false;
    peraviz::presentation::AsyncEvaluationOptions options;
    options.trace=trace;
    options.force=async_forced_; if (options.force) options.workers=2;
    if (!async_disabled_ && runtime->async_available() && AsyncPresentationPipeline::eligible(runtime->native_core(),options)) {
        begin_snapshot(trace);
        displayed_physical_.resize(state_.bindings().size());
        for (size_t i=0;i<displayed_physical_.size();++i) displayed_physical_[i]=state_.render_values(uint32_t(i));
        try {
            async_=std::make_shared<AsyncPresentationPipeline>(runtime->native_core_handle(),std::move(state_),std::move(projection_),options);
        } catch (...) {
            // Construction restores moved physical ownership; resource-starved environments remain serial.
            async_disabled_=true;
        }
        if (async_) {
            async_sizes_=async_->initial_sizes(); async_runtime_=runtime; runtime->attach_async(async_);
            return poll_async(runtime,generation,schema_generation,trace);
        }
    }
    begin_snapshot(trace);
    if (!pipeline_.consume(runtime->native_core(),state_,projection_,uint64_t(generation),schema_generation,trace)) {
        result["valid"]=false; return result;
    }
    Dictionary presentation=publish(generation,trace,pipeline_.physical_us,pipeline_.reduction_us);
    const int64_t packing_start=trace?now_us():0;
    const auto &frame=pipeline_.frame();
    PackedInt32Array descriptors, integers;
    PackedFloat32Array floats;
    // Only independent domain updates cross the boundary. Their ordering and timestamps are retained.
    int64_t intermediate_bytes=0, lighting_rows=0;
    std::array<int32_t,9> lighting_summary{};
    auto &fixture_ids=fixture_ids_; fixture_ids.clear();
    for (size_t b=0;b<frame.descriptors.size();b+=5) {
        const int32_t type=frame.descriptors[b], count=frame.descriptors[b+1];
        const auto section=std::find_if(runtime->native_core().schema().sections.begin(),runtime->native_core().schema().sections.end(),
                [type](const auto &s) { return s.section_type==type; });
        if (section==runtime->native_core().schema().sections.end()) continue;
        if (type==2 || type==3 || type==4) {
            lighting_rows+=count;
            if (trace) {
                lighting_summary[type-2]+=count;
                for (int32_t row=0;row<count;++row) {
                    const uint32_t mask=uint32_t(frame.integers[frame.descriptors[b+2]+row*section->row_stride_ints+2]);
                    for (int bit=0;bit<6;++bit) if (mask & (1U<<bit)) ++lighting_summary[3+bit];
                }
            }
            for (int32_t row=0;row<count;++row) fixture_ids.push_back(frame.integers[frame.descriptors[b+2]+row*section->row_stride_ints]);
            intermediate_bytes+=20+int64_t(count)*(section->row_stride_ints+section->row_stride_floats)*4;
            continue;
        }
        const int64_t ib=integers.size(), fb=floats.size();
        for (int32_t value : {type,count,int32_t(ib),int32_t(fb),frame.descriptors[b+4]}) descriptors.push_back(value);
        const int64_t ni=int64_t(count)*section->row_stride_ints, nf=int64_t(count)*section->row_stride_floats;
        integers.resize(ib+ni); floats.resize(fb+nf);
        if (ni) std::copy_n(frame.integers.data()+frame.descriptors[b+2],ni,integers.ptrw()+ib);
        if (nf) std::copy_n(frame.floats.data()+frame.descriptors[b+3],nf,floats.ptrw()+fb);
    }
    std::sort(fixture_ids.begin(),fixture_ids.end());
    fixture_ids.erase(std::unique(fixture_ids.begin(),fixture_ids.end()),fixture_ids.end());
    PackedInt32Array updated_fixtures;
    updated_fixtures.resize(fixture_ids.size());
    if (!fixture_ids.empty()) std::copy(fixture_ids.begin(),fixture_ids.end(),updated_fixtures.ptrw());
    result["updated_fixture_ids"]=updated_fixtures; result["lighting_rows"]=lighting_rows;
    result["valid"]=true; result["presentation"]=presentation;
    result["schema_generation"]=frame.schema_generation;
    result["runtime_now_seconds"]=runtime->native_core().runtime_now_seconds();
    if (!deferred_domains_.descriptors.empty()) {
        PackedInt32Array merged; PackedInt32Array merged_ints; PackedFloat32Array merged_floats;
        for (int32_t value:deferred_domains_.descriptors) merged.push_back(value);
        for (int32_t value:deferred_domains_.integers) merged_ints.push_back(value);
        for (float value:deferred_domains_.floats) merged_floats.push_back(value);
        for (int64_t b=0;b<descriptors.size();b+=5) {
            for (int32_t value:{descriptors[b],descriptors[b+1],int32_t(descriptors[b+2]+merged_ints.size()),int32_t(descriptors[b+3]+merged_floats.size()),descriptors[b+4]}) merged.push_back(value);
        }
        merged_ints.append_array(integers); merged_floats.append_array(floats);
        descriptors=merged; integers=merged_ints; floats=merged_floats; deferred_domains_={};
    }
    result["descriptors"]=descriptors; result["integers"]=integers; result["floats"]=floats;
    if (trace) {
        PackedInt32Array summary;
        summary.resize(lighting_summary.size());
        std::copy(lighting_summary.begin(),lighting_summary.end(),summary.ptrw());
        result["lighting_summary"]=summary;
        presentation["payload_conversion_us"]=int64_t(presentation["payload_conversion_us"])+now_us()-packing_start;
        presentation["native_evaluation_us"]=pipeline_.evaluation_us;
        presentation["intermediate_bytes_avoided"]=intermediate_bytes;
        presentation["intermediate_bytes_copied"]=0;
    }
    return result;
}
// Reports physical native capacities separately from genuinely renderer-sized packed storage.
Dictionary PeravizPresentationState::get_sizes() const {
    Dictionary sizes;
    sizes.merge(lenses_.stats(),true);
    sizes["diagnostic_skip_lens_writes_active"]=lens_writes_suppressed_;
    sizes["diagnostic_skip_lens_writes_requested"]=diagnostic_skip_lens_writes_;
    sizes["presentation_contract_revision"]=4;
    sizes["extension_build"]=String(__DATE__ " " __TIME__);
    sizes["unique_lens_material_rids"]=int64_t(materials_.size());
    sizes["physical_outputs"]=int64_t(async_?async_sizes_.physical_outputs:state_.bindings().size()); sizes["render_rows"]=int64_t(async_?async_sizes_.render_rows:projection_.row_count());
    sizes["state_capacity"]=int64_t(async_?async_sizes_.state_capacity:state_.state_capacity()); sizes["dirty_capacity"]=int64_t(async_?async_sizes_.dirty_capacity:state_.dirty_capacity());
    sizes["dirty_high_water"]=int64_t(async_?async_sizes_.high_water:state_.high_water()); sizes["native_buffer_bytes"]=int64_t(async_?async_sizes_.buffer_bytes:state_.buffer_bytes()+projection_.buffer_bytes());
    sizes["packed_buffer_bytes"]=indices_masks_.size()*int64_t(sizeof(int32_t))+values_.size()*int64_t(sizeof(float));
    sizes["native_async_active"]=bool(async_); sizes["native_snapshot_buffer_bytes"]=int64_t(async_snapshot_bytes_);
    sizes["native_worker_scratch_bytes"]=int64_t(async_worker_bytes_);
    sizes["native_input_buffer_bytes"]=int64_t(async_?async_->input_buffer_bytes():0);
    sizes["native_display_cache_bytes"]=int64_t(displayed_physical_.capacity()*sizeof(RenderValues));
    sizes["native_beam_bindings"]=int64_t(beams_.count()); sizes["native_beam_buffer_bytes"]=int64_t(beams_.buffer_bytes()+script_rows_.size()*sizeof(int32_t));
    sizes["native_worker_capacity"]=int64_t(async_?async_->worker_count():0);
    return sizes;
}
} // namespace godot
