#include "presentation/presentation_state_godot.h"
#include <algorithm>
#include <chrono>

namespace godot {
using namespace peraviz::presentation;
namespace {
// Samples the main-thread boundary only when tracing has been requested.
int64_t now_us() { return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
// Copies a completed domain frame into Godot once; its arrays contain no intermediate lighting calculation rows.
void pack_domains(Dictionary &result,const peraviz::runtime::SectionedVisualFrame &frame) {
    PackedInt32Array descriptors,integers; PackedFloat32Array floats;
    descriptors.resize(frame.descriptors.size()); integers.resize(frame.integers.size()); floats.resize(frame.floats.size());
    if (!frame.descriptors.empty()) std::copy(frame.descriptors.begin(),frame.descriptors.end(),descriptors.ptrw());
    if (!frame.integers.empty()) std::copy(frame.integers.begin(),frame.integers.end(),integers.ptrw());
    if (!frame.floats.empty()) std::copy(frame.floats.begin(),frame.floats.end(),floats.ptrw());
    result["descriptors"]=descriptors; result["integers"]=integers; result["floats"]=floats;
}
}
// Retires native borrowed plans before Godot-owned bindings disappear.
PeravizPresentationState::~PeravizPresentationState() { retire_async(false); }
// Reclaims one authoritative physical state at explicit renderer/setup boundaries, never during ordinary polling.
void PeravizPresentationState::retire_async(bool replay_domains) {
    if (!async_) return;
    async_->reclaim(state_,projection_);
    resume_pending_=replay_domains;
    if (async_runtime_.is_valid()) {
        const bool exclusive=async_runtime_->retire_async(async_.get());
        if (exclusive && replay_domains && async_runtime_->schema_generation()==async_->schema_generation()) deferred_domains_=async_runtime_->native_core().held_domain_replay();
    }
    async_.reset(); async_runtime_.unref(); async_snapshot_bytes_=async_worker_bytes_=0;
    state_.invalidate_renderer(); projection_.invalidate();
}
// Consumes a complete immutable snapshot through atomic handoff; it contains no wait for native calculations.
Dictionary PeravizPresentationState::poll_async(const Ref<PeravizVisualRuntime> &runtime,int64_t generation,int32_t schema_generation,bool trace) {
    Dictionary result;
    if (runtime.ptr()!=async_runtime_.ptr() || uint64_t(generation)!=async_->binding_generation() || schema_generation!=async_->schema_generation()) { result["valid"]=false; return result; }
    begin_snapshot(trace);
    // Diagnostic isolation may deliberately retire a session at this control boundary.
    if (!async_) return consume_runtime(runtime,generation,schema_generation,trace,false);
    const int64_t start=trace?now_us():0;
    async_->set_trace(trace); async_->flush_input();
    const auto *snapshot=async_->try_acquire();
    if (!snapshot) {
        result["valid"]=!async_->failed(); result["pending"]=!async_->failed();
        result["schema_generation"]=schema_generation; return result;
    }
    struct Lease {
        AsyncPresentationPipeline &session; const CompletedPresentationSnapshot *snapshot;
        // Releases the bank even when validation or boundary packing returns early.
        ~Lease() { session.release(snapshot); }
    } lease{*async_,snapshot};
    if (snapshot->schema_generation!=schema_generation || snapshot->binding_generation!=uint64_t(generation)) { result["valid"]=false; return result; }
    async_sizes_=snapshot->sizes; async_snapshot_bytes_=snapshot->buffer_bytes()*2; async_worker_bytes_=snapshot->parallel.retained_bytes;
    for (const auto &row:snapshot->physical_rows) displayed_physical_[row.index]=row.values;
    runtime->accept_completed(*snapshot);
    auto *indices=indices_masks_.ptrw(); auto *values=values_.ptrw(); size_t count=0;
    for (const auto &row:snapshot->render_rows) {
        indices[count*2]=int32_t(row.index); indices[count*2+1]=int32_t(row.mask);
        std::copy(row.values.begin(),row.values.end(),values+count*ValueCount); ++count;
    }
    const int64_t material_start=trace?now_us():0;
    materials_.apply_completed(snapshot->physical_rows,displayed_physical_,lens_writes_suppressed_);
    const int64_t material_us=trace?now_us()-material_start:0;
    Dictionary presentation;
    presentation["valid"]=true; presentation["native_async"]=true; presentation["generation"]=generation;
    presentation["input_generation"]=int64_t(snapshot->input_generation); presentation["unresolved_rows"]=int64_t(snapshot->unresolved_rows);
    presentation["count"]=int64_t(count); presentation["indices_masks"]=indices_masks_; presentation["values"]=values_;
    result["valid"]=true; result["schema_generation"]=schema_generation; result["runtime_now_seconds"]=snapshot->runtime_now_seconds;
    if (deferred_domains_.descriptors.empty()) pack_domains(result,snapshot->domains);
    else {
        auto merged=std::move(deferred_domains_); deferred_domains_={};
        const auto integers=merged.integers.size(),floats=merged.floats.size();
        for (size_t b=0;b<snapshot->domains.descriptors.size();b+=5) merged.descriptors.insert(merged.descriptors.end(),{
            snapshot->domains.descriptors[b],snapshot->domains.descriptors[b+1],int32_t(snapshot->domains.descriptors[b+2]+integers),
            int32_t(snapshot->domains.descriptors[b+3]+floats),snapshot->domains.descriptors[b+4]});
        merged.integers.insert(merged.integers.end(),snapshot->domains.integers.begin(),snapshot->domains.integers.end());
        merged.floats.insert(merged.floats.end(),snapshot->domains.floats.begin(),snapshot->domains.floats.end());
        pack_domains(result,merged);
    }
    PackedInt32Array fixtures; fixtures.resize(snapshot->updated_fixtures.size());
    if (!snapshot->updated_fixtures.empty()) std::copy(snapshot->updated_fixtures.begin(),snapshot->updated_fixtures.end(),fixtures.ptrw());
    result["updated_fixture_ids"]=fixtures; result["lighting_rows"]=snapshot->lighting_rows;
    if (snapshot->submitted_ns) result["received_at_us"]=int64_t(snapshot->submitted_ns/1000);
    if (trace) {
        PackedInt32Array summary; summary.resize(9); std::copy(snapshot->lighting_summary.begin(),snapshot->lighting_summary.end(),summary.ptrw());
        result["lighting_summary"]=summary;
        const size_t dirty=snapshot->physical_rows.size();
        presentation["physical_dynamic_candidates"]=int64_t(dirty); presentation["dirty_count"]=int64_t(dirty);
        presentation["candidates"]=int64_t(snapshot->candidates); presentation["signature_skipped"]=int64_t(dirty)-int64_t(count);
        presentation["native_evaluation_us"]=snapshot->evaluation_us;
        presentation["native_physical_us"]=snapshot->physical_us; presentation["native_reduction_us"]=snapshot->reduction_us;
        presentation["native_compose_us"]=snapshot->physical_us+snapshot->reduction_us;
        presentation["native_material_us"]=material_us;
        presentation["physical_color_outputs"]=int64_t(materials_.color_outputs());
        presentation["lens_rids_affected"]=int64_t(materials_.affected()); presentation["lens_rids_unchanged"]=int64_t(materials_.unchanged());
        presentation["lens_material_writes"]=int64_t(materials_.writes()); presentation["lens_writes_avoided"]=int64_t(materials_.avoided());
        presentation["intermediate_bytes_avoided"]=snapshot->intermediate_bytes_avoided; presentation["intermediate_bytes_copied"]=0;
        const auto &parallel=snapshot->parallel;
        presentation["native_parallel_tasks"]=int64_t(parallel.tasks); presentation["native_workers_used"]=parallel.workers_used;
        presentation["native_worker_cpu_us"]=int64_t(parallel.worker_cpu_ns/1000);
        presentation["native_task_wall_us"]=int64_t(parallel.task_wall_ns/1000);
        presentation["native_coordination_us"]=int64_t(parallel.coordination_ns/1000);
        presentation["native_worker_failures"]=int64_t(parallel.failures);
        presentation["native_serial_fallbacks"]=int64_t(parallel.serial_batches);
        presentation["native_serial_probes"]=int64_t(parallel.serial_probes);
        presentation["native_policy_backoffs"]=int64_t(parallel.policy_backoffs);
        presentation["native_completed_latency_us"]=snapshot->completion_latency_us;
        const int64_t elapsed=now_us()-start;
        presentation["payload_conversion_us"]=std::max<int64_t>(0,elapsed-material_us);
        presentation["main_thread_publication_us"]=elapsed;
        if (snapshot->submitted_ns) presentation["native_consumed_latency_us"]=std::max<int64_t>(0,now_us()-int64_t(snapshot->submitted_ns/1000));
    }
    result["presentation"]=presentation;
    return result;
}
} // namespace godot
