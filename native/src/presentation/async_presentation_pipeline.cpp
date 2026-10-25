#include "presentation/async_presentation_pipeline.h"
#include "presentation/direct_presentation_pipeline.h"
#include "runtime/native_worker_pool.h"
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <stdexcept>
#include <unordered_map>

namespace peraviz::presentation {
namespace {
std::atomic<uint64_t> next_session{0};
// Samples wall time only for requested latency/diagnostic measurements.
uint64_t now_ns() { return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
// Captures native capacities at a point where the coordinator has exclusive ownership.
NativePresentationSizes sizes_of(const DensePresentationState &state,const RenderGroupProjection &projection) {
    return {state.bindings().size(),projection.row_count(),state.state_capacity(),state.dirty_capacity(),state.high_water(),state.buffer_bytes()+projection.buffer_bytes()};
}
}
struct AsyncPresentationPipeline::Impl {
    enum Status:int { Free,Writing,Queued,Reading };
    struct InputValue { int id=0; int length=0; uint64_t sequence=0,received_us=0; std::array<uint8_t,512> data{}; };
    struct InputBank { std::atomic<int> status{Free}; std::vector<InputValue> frames; uint64_t generation=0,submitted=0; };
    struct OutputBank { std::atomic<int> status{Free}; CompletedPresentationSnapshot snapshot; };
    std::shared_ptr<runtime::PeravizVisualRuntimeCore> core;
    DensePresentationState state;
    RenderGroupProjection projection;
    DirectPresentationPipeline pipeline;
    std::unique_ptr<runtime::NativeWorkerPool> pool;
    runtime::NativeBatchExecutor *executor=nullptr;
    std::thread coordinator;
    std::array<InputBank,3> inputs;
    std::array<OutputBank,2> outputs;
    std::vector<InputValue> latest; // Main-thread producer ownership only.
    std::unordered_map<int,size_t> input_indices;
    std::vector<uint64_t> consumed_sequences;
    std::atomic<int> queued_input{-1},ready_output{-1};
    std::atomic<bool> stopping{false},failed{false},trace{false};
    std::mutex wake_mutex;
    std::condition_variable wake;
    uint64_t producer_sequence=1,producer_generation=1;
    bool producer_dirty=false,reclaimed=false,retired=false;
    const uint64_t session;
    const int32_t schema;
    const uint64_t binding;
    const NativePresentationSizes initial;
    // Reserves bounded raw-input and immutable-result banks before the coordinator starts.
    Impl(std::shared_ptr<runtime::PeravizVisualRuntimeCore> value,DensePresentationState &&physical,
            RenderGroupProjection &&render,AsyncEvaluationOptions options,runtime::NativeBatchExecutor *override_executor):
            core(std::move(value)),state(std::move(physical)),projection(std::move(render)),
            session(++next_session),schema(core->schema().schema_generation),binding(state.generation()),initial(sizes_of(state,projection)) {
        try {
        if (core->has_gobo_domains()) throw std::invalid_argument("Temporal/gobo domains require the serial transaction");
        trace.store(options.trace,std::memory_order_relaxed);
        const auto held=core->held_universes(); latest.resize(held.size()); consumed_sequences.resize(held.size(),1);
        for (size_t i=0;i<held.size();++i) {
            auto &frame=latest[i]; frame.id=held[i].id; frame.length=int(held[i].values.size()); frame.sequence=1;
            std::copy(held[i].values.begin(),held[i].values.end(),frame.data.begin()); input_indices.emplace(frame.id,i);
        }
        for (auto &bank:inputs) bank.frames.resize(latest.size());
        for (auto &bank:outputs) { bank.snapshot.physical_rows.reserve(initial.physical_outputs); bank.snapshot.render_rows.reserve(initial.render_rows); bank.snapshot.updated_fixtures.reserve(initial.physical_outputs*3); }
        if (override_executor) executor=override_executor;
        else { pool=std::make_unique<runtime::NativeWorkerPool>(options.workers,options.force); executor=pool.get(); }
        core->set_native_executor(executor);
        coordinator=std::thread([this] { run(); });
        } catch (...) {
            core->set_native_executor(nullptr);
            physical=std::move(state); render=std::move(projection);
            throw;
        }
    }
    // Copies only final compact resources and independent domains before publishing any output bank.
    void complete(CompletedPresentationSnapshot &snapshot,uint64_t input_generation,uint64_t submitted,bool measured) {
        snapshot.session_generation=session; snapshot.schema_generation=schema; snapshot.binding_generation=binding;
        snapshot.input_generation=input_generation; snapshot.runtime_now_seconds=core->runtime_now_seconds();
        snapshot.render_rows.assign(projection.prepared().begin(),projection.prepared().end());
        snapshot.physical_rows.clear();
        for (uint32_t index:state.dirty_indices()) snapshot.physical_rows.push_back({index,state.pending_mask(index),projection.member_values(index)});
        snapshot.domains.descriptors.clear(); snapshot.domains.integers.clear(); snapshot.domains.floats.clear();
        snapshot.domains.schema_generation=schema; snapshot.updated_fixtures.clear(); snapshot.lighting_summary={};
        snapshot.lighting_rows=0; snapshot.intermediate_bytes_avoided=0;
        const auto &frame=pipeline.frame(); const auto &schema_view=core->schema();
        for (size_t b=0;b<frame.descriptors.size();b+=5) {
            const int type=frame.descriptors[b],count=frame.descriptors[b+1];
            const auto section=std::find_if(schema_view.sections.begin(),schema_view.sections.end(),[&](const auto &s) { return s.section_type==type; });
            if (section==schema_view.sections.end()) continue;
            if (type==2 || type==3 || type==4) {
                snapshot.lighting_rows+=count;
                snapshot.intermediate_bytes_avoided+=20+int64_t(count)*(section->row_stride_ints+section->row_stride_floats)*4;
                snapshot.lighting_summary[size_t(type-2)]+=count;
                for (int row=0;row<count;++row) {
                    const size_t index=size_t(frame.descriptors[b+2])+size_t(row)*section->row_stride_ints;
                    snapshot.updated_fixtures.push_back(frame.integers[index]);
                    if (measured) for (int bit=0;bit<6;++bit) if (uint32_t(frame.integers[index+2])&(1U<<bit)) ++snapshot.lighting_summary[size_t(bit+3)];
                }
                continue;
            }
            auto &domains=snapshot.domains;
            domains.descriptors.insert(domains.descriptors.end(),{type,count,int32_t(domains.integers.size()),int32_t(domains.floats.size()),frame.descriptors[b+4]});
            const auto ib=frame.integers.begin()+frame.descriptors[b+2];
            const auto fb=frame.floats.begin()+frame.descriptors[b+3];
            domains.integers.insert(domains.integers.end(),ib,ib+count*section->row_stride_ints);
            domains.floats.insert(domains.floats.end(),fb,fb+count*section->row_stride_floats);
        }
        std::sort(snapshot.updated_fixtures.begin(),snapshot.updated_fixtures.end());
        snapshot.updated_fixtures.erase(std::unique(snapshot.updated_fixtures.begin(),snapshot.updated_fixtures.end()),snapshot.updated_fixtures.end());
        snapshot.unresolved_rows=state.unresolved_rows(); snapshot.candidates=std::max(state.candidates(),snapshot.physical_rows.size());
        snapshot.runtime_stats=core->stats(); snapshot.runtime_sizes=core->state_sizes(); snapshot.sizes=sizes_of(state,projection);
        snapshot.parallel=core->parallel_metrics();
        snapshot.evaluation_us=measured?pipeline.evaluation_us:0; snapshot.physical_us=measured?pipeline.physical_us:0; snapshot.reduction_us=measured?pipeline.reduction_us:0;
        snapshot.submitted_ns=submitted; snapshot.completed_ns=measured?now_ns():0;
        snapshot.completion_latency_us=submitted && snapshot.completed_ns>=submitted?int64_t((snapshot.completed_ns-submitted)/1000):0;
        state.finish_snapshot(binding);
    }
    // Runs pure worker phases and deterministic native state/reduction as the sole canonical writer.
    void run() noexcept {
        try {
            bool initial_batch=true; uint64_t generation=1,submitted=0;
            while (!stopping.load(std::memory_order_acquire)) {
                {
                    std::unique_lock<std::mutex> lock(wake_mutex);
                    wake.wait_for(lock,std::chrono::milliseconds(1),[&] { return stopping.load() || initial_batch || queued_input.load()!=-1; });
                    if (!initial_batch && queued_input.load()==-1 && !stopping.load()) continue;
                }
                if (stopping.load()) break;
                const int input=queued_input.exchange(-1,std::memory_order_acq_rel);
                if (input>=0) {
                    auto &bank=inputs[size_t(input)]; bank.status.store(Reading,std::memory_order_release);
                    generation=bank.generation; submitted=bank.submitted;
                    uint64_t received=0;
                    for (size_t i=0;i<bank.frames.size();++i) {
                        const auto &frame=bank.frames[i];
                        if (frame.length>0 && frame.sequence!=consumed_sequences[i]) {
                            core->submit_universe_frame(frame.id,frame.data.data(),frame.length); consumed_sequences[i]=frame.sequence;
                            if (frame.received_us && (!received || frame.received_us<received)) received=frame.received_us;
                        }
                    }
                    if (received) submitted=received*1000;
                    bank.status.store(Free,std::memory_order_release);
                }
                initial_batch=false;
                int output=-1;
                while (output<0 && !stopping.load()) {
                    for (size_t i=0;i<outputs.size();++i) { int free=Free; if (outputs[i].status.compare_exchange_strong(free,Writing)) { output=int(i); break; } }
                    if (output<0) { std::unique_lock<std::mutex> lock(wake_mutex); wake.wait_for(lock,std::chrono::milliseconds(2)); }
                }
                if (stopping.load()) break;
                const bool measured=trace.load(std::memory_order_acquire);
                core->set_performance_trace_enabled(measured); state.set_trace_enabled(measured);
                if (!pipeline.consume(*core,state,projection,binding,schema,measured)) throw std::runtime_error("Native presentation generation rejected");
                auto &bank=outputs[size_t(output)]; complete(bank.snapshot,generation,submitted,measured);
                bank.status.store(Queued,std::memory_order_release);
                // Never replace an unread delta: a bounded second complete result waits natively for publication.
                for (;;) {
                    if (stopping.load()) break;
                    int none=-1;
                    if (ready_output.compare_exchange_strong(none,output,std::memory_order_release,std::memory_order_relaxed)) { break; }
                    std::unique_lock<std::mutex> lock(wake_mutex); wake.wait_for(lock,std::chrono::milliseconds(2));
                }
            }
        } catch (...) { failed.store(true,std::memory_order_release); }
    }
};
// Requires enough independent work and hardware; temporal/gobo scenes deliberately keep the serial transaction.
bool AsyncPresentationPipeline::eligible(const runtime::PeravizVisualRuntimeCore &core,AsyncEvaluationOptions options) {
    return !core.has_gobo_domains() && (options.force || (core.async_eligible_workload() && runtime::NativeWorkerPool::recommended_workers()>=2));
}
// Moves canonical physical ownership into one native coordinator before it can execute jobs.
AsyncPresentationPipeline::AsyncPresentationPipeline(std::shared_ptr<runtime::PeravizVisualRuntimeCore> core,
        DensePresentationState &&state,RenderGroupProjection &&projection,AsyncEvaluationOptions options,runtime::NativeBatchExecutor *executor):
        impl_(std::make_unique<Impl>(std::move(core),std::move(state),std::move(projection),options,executor)) {}
// Invalidates publication and joins only at a lifecycle boundary.
AsyncPresentationPipeline::~AsyncPresentationPipeline() { stop(); }
// Updates producer-owned latest input without taking a lock held by workers or the coordinator.
bool AsyncPresentationPipeline::submit(int universe,const uint8_t *data,int length,uint64_t received_us) {
    auto &p=*impl_; if (!active() || !data || length<=0) return false;
    const auto found=p.input_indices.find(universe); if (found==p.input_indices.end()) return false;
    auto &frame=p.latest[found->second]; frame.length=std::min(length,512); frame.sequence=++p.producer_sequence; frame.received_us=received_us;
    std::copy_n(data,frame.length,frame.data.begin()); p.producer_dirty=true; return true;
}
// Publishes a consistent latest-state input generation into one of three bounded native banks.
bool AsyncPresentationPipeline::flush_input() {
    auto &p=*impl_; if (!p.producer_dirty || !active()) return false;
    for (size_t i=0;i<p.inputs.size();++i) {
        int free=Impl::Free;
        if (!p.inputs[i].status.compare_exchange_strong(free,Impl::Writing)) continue;
        auto &bank=p.inputs[i]; std::copy(p.latest.begin(),p.latest.end(),bank.frames.begin());
        bank.generation=++p.producer_generation; bank.submitted=p.trace.load()?now_ns():0;
        bank.status.store(Impl::Queued,std::memory_order_release);
        const int old=p.queued_input.exchange(int(i),std::memory_order_acq_rel);
        if (old>=0) p.inputs[size_t(old)].status.store(Impl::Free,std::memory_order_release);
        p.producer_dirty=false; p.wake.notify_one(); return true;
    }
    return false;
}
// Acquires only fully completed immutable results; this path never waits on native work.
const CompletedPresentationSnapshot *AsyncPresentationPipeline::try_acquire() {
    auto &p=*impl_; if (!active()) return nullptr;
    const int index=p.ready_output.exchange(-1,std::memory_order_acq_rel); if (index<0) return nullptr;
    auto &bank=p.outputs[size_t(index)]; bank.status.store(Impl::Reading,std::memory_order_release); p.wake.notify_one();
    return &bank.snapshot;
}
// Returns a fully consumed bank after all main-thread resource values have been copied/applied.
void AsyncPresentationPipeline::release(const CompletedPresentationSnapshot *snapshot) {
    for (auto &bank:impl_->outputs) if (&bank.snapshot==snapshot) { bank.status.store(Impl::Free,std::memory_order_release); impl_->wake.notify_one(); return; }
}
// Transfers trace configuration atomically; workers never inspect Godot state.
void AsyncPresentationPipeline::set_trace(bool enabled) { impl_->trace.store(enabled,std::memory_order_release); }
// Checks the publication gate without touching worker-owned canonical state.
bool AsyncPresentationPipeline::active() const { return !impl_->stopping.load(std::memory_order_acquire) && !impl_->failed.load(std::memory_order_acquire); }
// Exposes failure without allowing a partial result to publish.
bool AsyncPresentationPipeline::failed() const { return impl_->failed.load(std::memory_order_acquire); }
// Cancels before joining so old generations cannot become visible during native retirement.
void AsyncPresentationPipeline::stop() {
    auto &p=*impl_; if (p.retired) return;
    p.stopping.store(true,std::memory_order_release); p.wake.notify_all();
    if (p.coordinator.joinable()) p.coordinator.join();
    // Restore unconsumed producer input before another session may acquire this core.
    if (p.core->schema().schema_generation==p.schema) {
        for (size_t i=0;i<p.latest.size();++i) {
            const auto &frame=p.latest[i];
            if (frame.length>0 && frame.sequence!=p.consumed_sequences[i]) p.core->submit_universe_frame(frame.id,frame.data.data(),frame.length);
        }
    }
    p.core->set_native_executor(nullptr); p.ready_output.store(-1,std::memory_order_release); p.retired=true;
}
// Returns the same authoritative state at a cold renderer/setup boundary, never a duplicate owner.
void AsyncPresentationPipeline::reclaim(DensePresentationState &state,RenderGroupProjection &projection) {
    stop(); if (impl_->reclaimed) return;
    state=std::move(impl_->state); projection=std::move(impl_->projection); impl_->reclaimed=true;
}
// Returns immutable binding identity for main-thread publication validation.
uint64_t AsyncPresentationPipeline::binding_generation() const { return impl_->binding; }
// Returns immutable scene identity without reading a running core.
int32_t AsyncPresentationPipeline::schema_generation() const { return impl_->schema; }
// Returns setup capacities until a first completed snapshot is available.
NativePresentationSizes AsyncPresentationPipeline::initial_sizes() const { return impl_->initial; }
// Reports bounded native input bank storage separately from snapshots and platform thread stacks.
size_t AsyncPresentationPipeline::input_buffer_bytes() const { return impl_->latest.capacity()*sizeof(Impl::InputValue)*4; }
// Reports owned native worker capacity separately from actual tasks used in a completed batch.
uint32_t AsyncPresentationPipeline::worker_count() const { return impl_->pool?impl_->pool->worker_count():0; }
} // namespace peraviz::presentation
