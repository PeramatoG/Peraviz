#include "presentation/async_presentation_pipeline.h"
#include "presentation/direct_presentation_pipeline.h"
#include "runtime/native_worker_pool.h"
#include <array>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <thread>

peraviz::runtime::CompiledRuntimeScene make_native_parallel_workload(bool compact);
namespace {
using namespace peraviz::runtime;
using namespace peraviz::presentation;
using Clock=std::chrono::steady_clock;
// Reports one targeted failure without introducing a separate test framework or FPS threshold.
bool check(bool ok,const char *message) { if (!ok) std::cerr << "native parallel: " << message << '\n'; return ok; }
// Adds supported calibrated inputs and ordered optical layers to the existing generated workload.
CompiledRuntimeScene scene_for(bool compact) {
    auto scene=make_native_parallel_workload(compact);
    CompiledEmitterResource emitter; emitter.resource_id=1; emitter.valid=true;
    emitter.fallback_linear_r=1; emitter.fallback_linear_g=0.25; emitter.fallback_linear_b=0.1;
    scene.emitter_resources.push_back(emitter);
    CompiledFilterResource filter; filter.resource_id=2; filter.valid=true; filter.fallback_transmission=0.6;
    filter.fallback_linear_r=0.8; filter.fallback_linear_g=0.3; filter.fallback_linear_b=1;
    scene.filter_resources.push_back(filter);
    for (size_t i=0;i<scene.color_targets.size();++i) {
        if (i%17==0) scene.color_targets[i].inputs[0].emitter_resource_id=1;
        if (i%19==0) scene.color_targets[i].inputs[1].filter_resource_id=2;
    }
    auto convergent=scene.color_targets[1]; convergent.color_target_id=999999;
    convergent.inputs[0].semantic=CompiledSemantic::ColorAddBlue; convergent.inputs[2].semantic=CompiledSemantic::ColorAddRed;
    scene.color_targets.push_back(std::move(convergent));
    if (!compact) {
        auto shared_target=scene.color_targets[80]; shared_target.color_target_id=999998;
        shared_target.fixture_id=1; shared_target.beam_render_target_id=10002;
        scene.color_targets.push_back(std::move(shared_target));
    }
    for (int wheel=0;wheel<2;++wheel) {
        CompiledWheelPalette palette; palette.wheel_renderer_id=101+wheel; palette.fixture_id=1;
        CompiledWheelPaletteSlot first; first.slot_index=1; first.linear_red=1; first.linear_green=0.6f; first.linear_blue=0.4f;
        CompiledWheelPaletteSlot second; second.slot_index=2; second.linear_red=0.2f; second.linear_green=0.4f; second.linear_blue=1; second.gain=0.7f;
        palette.slots={first,second}; scene.wheel_palettes.push_back(palette);
        scene.wheel_bindings.push_back({100+wheel,1,10001,101+wheel,4,CompiledWheelMode::Select,true,0,{{0,127,1},{128,255,2}}});
    }
    return scene;
}
// Binds the same canonical physical output collection and native aggregation in each execution route.
bool bind(DensePresentationState &state,RenderGroupProjection &projection,bool compact) {
    std::vector<OutputBinding> outputs; std::vector<TargetBinding> targets; std::vector<uint32_t> membership;
    for (int i=0;i<1000;++i) {
        outputs.push_back({20001+i,0.032f});
        for (int section:{2,3,4}) targets.push_back({section,10001+i,uint32_t(i)});
        membership.push_back(compact?i/50:i);
    }
    return state.install(outputs,targets) && projection.install(membership,std::vector<RenderPresentationClass>(compact?20:1000,
        compact?RenderPresentationClass::Aggregated:RenderPresentationClass::Individual));
}
// Only tests wait for a result; the production presentation path itself uses a single atomic poll.
const CompletedPresentationSnapshot *await(AsyncPresentationPipeline &session) {
    const auto deadline=Clock::now()+std::chrono::seconds(5);
    while (Clock::now()<deadline) { if (const auto *snapshot=session.try_acquire()) return snapshot; if (session.failed()) break; std::this_thread::sleep_for(std::chrono::microseconds(50)); }
    return nullptr;
}
// Blocks pure calculation deliberately so tests can prove publication cannot expose partial jobs.
class GateExecutor final : public NativeBatchExecutor {
public:
    NativeWorkerPool pool{2,true};
    std::mutex mutex; std::condition_variable condition;
    bool permit=false; size_t entered=0;
    bool block_next=true; std::atomic<bool> fail_once{true};
    struct Call { GateExecutor *owner; Function function; void *context; bool gated; };
    // Executes the production pool with the first pure phase held before touching any result slot.
    static void callback(void *data,size_t begin,size_t end) {
        auto &call=*static_cast<Call *>(data); auto &self=*call.owner;
        if (call.gated) { std::unique_lock<std::mutex> lock(self.mutex); ++self.entered; self.condition.notify_all(); self.condition.wait(lock,[&] { return self.permit; }); }
        if (self.fail_once.exchange(false)) throw std::runtime_error("deliberate pure worker failure");
        call.function(call.context,begin,end);
    }
    // Keeps ownership/failure tests independent of hardware-dependent adaptive decisions.
    bool forced() const override { return true; }
    // Allows the deterministic test to exercise real parallel ranges regardless of CI CPU quota.
    bool worthwhile(size_t count,size_t) const override { return count>=2; }
    // Reuses real failure handling; callback retry remains a pure range replacement after the barrier.
    NativeBatchMetrics run(size_t count,size_t minimum,Function function,void *context,bool trace) override {
        Call call{this,function,context,block_next}; block_next=false;
        return pool.run(count,minimum,callback,&call,trace);
    }
    // Waits only in test control code until both real native workers reach the gate.
    bool wait_started() { std::unique_lock<std::mutex> lock(mutex); return condition.wait_for(lock,std::chrono::seconds(5),[&] { return entered>=2; }); }
    // Releases a deliberately paused test phase before safe native cancellation/shutdown.
    void release() { std::lock_guard<std::mutex> lock(mutex); permit=true; condition.notify_all(); }
};
// Compares actual async completion with the optimized serial authority, including sparse/held/optical updates.
bool equivalence(bool compact) {
    auto scene=scene_for(compact);
    PeravizVisualRuntimeCore serial; serial.install_compiled_scene(scene); serial.set_performance_trace_enabled(true);
    auto core=std::make_shared<PeravizVisualRuntimeCore>(); core->install_compiled_scene(scene);
    DensePresentationState a,b; RenderGroupProjection pa,pb;
    if (!bind(a,pa,compact) || !bind(b,pb,compact)) return false;
    if (!compact && !check(core->async_eligible_workload(),"independent production workload must be eligible")) return false;
    if (compact && !check(!core->async_eligible_workload(),"shared-control production workload must retain the serial fallback")) return false;
    std::array<std::array<uint8_t,512>,13> inputs{};
    for (int universe=0;universe<(compact?1:13);++universe) {
        serial.submit_universe_frame(universe,inputs[universe].data(),512); core->submit_universe_frame(universe,inputs[universe].data(),512);
    }
    DirectPresentationPipeline pipeline;
    if (!pipeline.consume(serial,a,pa,a.generation(),serial.schema().schema_generation,true)) return false;
    GateExecutor gate;
    AsyncEvaluationOptions options; options.workers=2; options.force=true; options.trace=true;
    AsyncPresentationPipeline session(core,std::move(b),std::move(pb),options,compact?&gate:nullptr);
    if (compact) {
        if (!gate.wait_started()) { gate.release(); return check(false,"native workers did not reach the publication gate"); }
        for (int poll=0;poll<10000;++poll) if (session.try_acquire()) { gate.release(); return check(false,"partial snapshot became visible before the barrier"); }
        gate.release();
    }
    uint64_t previous_generation=0,session_generation=0;
    uint64_t serial_us=0,parallel_us=0,reduction_us=0,cpu_ns=0,coord_ns=0,tasks=0,latency_us=0,dirty=0,rows=0,failures=0;
    size_t buffers=0,scratch=0,fallbacks=0;
    for (int step=0;step<20;++step) {
        if (step) {
            // Full, repeated, and single-source changes cover both high-fan-out and bounded sparse batches.
            const bool sparse=step%4==3;
            for (int universe=0;universe<(compact?1:13);++universe) {
                if (sparse && universe) continue;
                if (sparse) inputs[universe][0]=uint8_t(inputs[universe][0]+1);
                else if (step%4!=2) for (int offset=0;offset<480;offset+=6) for (int c=0;c<5;++c)
                    inputs[universe][offset+c]=uint8_t((step*17+universe*23+offset*3+c*41)%256);
                serial.submit_universe_frame(universe,inputs[universe].data(),512);
            }
        }
        if (step) {
            if (!pipeline.consume(serial,a,pa,a.generation(),serial.schema().schema_generation,true)) return false;
            for (int universe=0;universe<(compact?1:13);++universe) {
                if (step%4==3 && universe) continue;
                session.submit(universe,inputs[universe].data(),512);
            }
            session.flush_input();
        }
        const auto *snapshot=await(session);
        if (!check(snapshot!=nullptr,"asynchronous native generation failed to complete")) return false;
        bool ok=snapshot->schema_generation==serial.schema().schema_generation && snapshot->input_generation>previous_generation;
        previous_generation=snapshot->input_generation; session_generation=snapshot->session_generation;
        ok=ok && snapshot->render_rows.size()==pa.prepared().size() && snapshot->physical_rows.size()==a.dirty_indices().size();
        for (size_t i=0;ok && i<snapshot->physical_rows.size();++i) {
            const auto &row=snapshot->physical_rows[i]; const auto index=a.dirty_indices()[i];
            ok=row.index==index && row.mask==a.pending_mask(index) && row.values==a.render_values(index);
        }
        for (size_t i=0;ok && i<snapshot->render_rows.size();++i) {
            const auto &x=snapshot->render_rows[i],&y=pa.prepared()[i];
            ok=x.index==y.index && x.mask==y.mask && x.values==y.values;
        }
        // Every independent-domain record must retain its exact canonical typed payload and ordering.
        const auto &frame=pipeline.frame(); size_t db=0;
        for (size_t i=0;ok && i<frame.descriptors.size();i+=5) {
            const int type=frame.descriptors[i]; if (type==2 || type==3 || type==4) continue;
            ok=db+5<=snapshot->domains.descriptors.size() && snapshot->domains.descriptors[db]==type && snapshot->domains.descriptors[db+1]==frame.descriptors[i+1];
            const auto definition=std::find_if(serial.schema().sections.begin(),serial.schema().sections.end(),[&](const auto &value) { return value.section_type==type; });
            const size_t ni=size_t(frame.descriptors[i+1])*definition->row_stride_ints,nf=size_t(frame.descriptors[i+1])*definition->row_stride_floats;
            for (size_t j=0;ok && j<ni;++j) ok=frame.integers[size_t(frame.descriptors[i+2])+j]==snapshot->domains.integers[size_t(snapshot->domains.descriptors[db+2])+j];
            for (size_t j=0;ok && j<nf;++j) ok=frame.floats[size_t(frame.descriptors[i+3])+j]==snapshot->domains.floats[size_t(snapshot->domains.descriptors[db+3])+j];
            db+=5;
        }
        ok=ok && db==snapshot->domains.descriptors.size();
        serial_us+=uint64_t(pipeline.evaluation_us); parallel_us+=uint64_t(snapshot->evaluation_us); reduction_us+=uint64_t(snapshot->physical_us+snapshot->reduction_us);
        tasks+=snapshot->parallel.tasks; cpu_ns+=snapshot->parallel.worker_cpu_ns; coord_ns+=snapshot->parallel.coordination_ns;
        latency_us+=uint64_t(snapshot->completion_latency_us); dirty+=snapshot->physical_rows.size(); rows+=snapshot->render_rows.size(); failures+=snapshot->parallel.failures;
        fallbacks+=size_t(snapshot->parallel.serial_batches); buffers=std::max(buffers,snapshot->buffer_bytes()*2); scratch=std::max(scratch,snapshot->parallel.retained_bytes);
        session.release(snapshot); a.finish_snapshot(a.generation());
        if (!check(ok,"serial/parallel physical values, masks, domains or ordering differ")) return false;
    }
    if (!check(tasks>1 && (!compact || failures==1),"production calculations must run parallel tasks and safely retry a deliberate worker failure")) return false;
    if (!check(session.try_acquire()==nullptr,"hold must not publish a partial or repeated generation")) return false;
    session.reclaim(b,pb); b.invalidate_renderer(); pb.invalidate(); a.invalidate_renderer(); pa.invalidate();
    AsyncPresentationPipeline replacement(core,std::move(b),std::move(pb),options);
    // Repeated old retirement must not reset the replacement executor or its borrowed graph.
    session.stop();
    if (!pipeline.consume(serial,a,pa,a.generation(),serial.schema().schema_generation,true)) return false;
    const auto *replay=await(replacement);
    const bool replay_ok=replay && replay->session_generation!=session_generation && replay->render_rows.size()==pa.prepared().size() && replay->physical_rows.size()==1000;
    if (replay) replacement.release(replay);
    replacement.stop();
    std::cout << "native-parallel " << (compact?"shared-forced-equivalence":"independent") << " serial_eval_us=" << serial_us
        << " parallel_eval_us=" << parallel_us << " compose_reduce_us=" << reduction_us << " worker_cpu_us=" << cpu_ns/1000
        << " coordination_us=" << coord_ns/1000 << " tasks=" << tasks << " serial_fallbacks=" << fallbacks
        << " completed_latency_us=" << latency_us << " dirty_outputs=" << dirty << " rows=" << rows
        << " snapshot_bytes=" << buffers << " worker_scratch_bytes=" << scratch << " failures_recovered=" << failures << '\n';
    return check(replay_ok,"renderer retirement must replay exact held physical state without new DMX");
}
// Keeps a tiny independently patched fixture on the original allocation-light serial transaction.
bool small_serial() {
    auto scene=make_native_parallel_workload(false);
    scene.fixtures.resize(1); scene.source_programs.resize(5); scene.properties.resize(2); scene.color_targets.resize(1);
    PeravizVisualRuntimeCore core; core.install_compiled_scene(scene);
    if (!check(!core.async_eligible_workload(),"small scene must not create an asynchronous pool")) return false;
    DensePresentationState state; RenderGroupProjection projection;
    if (!state.install({{20001,0.032f}},{{2,10001,0},{3,10001,0},{4,10001,0}}) ||
            !projection.install({0},{RenderPresentationClass::Individual})) return false;
    DirectPresentationPipeline pipeline; std::array<uint8_t,512> input{}; int64_t evaluation=0,reduction=0;
    for (int step=0;step<20;++step) {
        input.fill(uint8_t(step*11)); core.submit_universe_frame(0,input.data(),512);
        if (!pipeline.consume(core,state,projection,state.generation(),core.schema().schema_generation,true)) return false;
        evaluation+=pipeline.evaluation_us; reduction+=pipeline.physical_us+pipeline.reduction_us;
        state.finish_snapshot(state.generation());
    }
    std::cout << "native-parallel small-serial serial_eval_us=" << evaluation << " compose_reduce_us=" << reduction << " tasks=0 rows=20 snapshot_bytes=0\n";
    return check(core.parallel_metrics().tasks==0,"small serial fallback dispatched workers");
}
// Coalesces arbitrarily many queued packets while retaining latest values from different universes.
bool coalescing() {
    auto core=std::make_shared<PeravizVisualRuntimeCore>(); core->install_compiled_scene(scene_for(false));
    DensePresentationState state; RenderGroupProjection projection;
    if (!bind(state,projection,false)) return false;
    std::array<uint8_t,512> seed{}; core->submit_universe_frame(0,seed.data(),512);
    GateExecutor gate; gate.fail_once=false;
    AsyncEvaluationOptions options; options.workers=2; options.force=true;
    AsyncPresentationPipeline session(core,std::move(state),std::move(projection),options,&gate);
    if (!gate.wait_started()) { gate.release(); return false; }
    std::array<uint8_t,512> first{},second{}; first.fill(42); second.fill(210);
    session.submit(0,first.data(),512); session.flush_input();
    for (int packet=0;packet<200;++packet) { session.submit(1,second.data(),512); session.flush_input(); }
    gate.release();
    const auto *initial=await(session); if (!initial) return false; session.release(initial);
    const auto *latest=await(session); bool valid=latest && latest->input_generation==202;
    bool a=false,b=false;
    if (latest) {
        for (const auto &row:latest->physical_rows) {
            if (row.index==0) a=row.values[0]==42.0f/255.0f;
            if (row.index==80) b=row.values[0]==210.0f/255.0f;
        }
        session.release(latest);
    }
    session.stop();
    return check(valid && a && b,"bounded coalescing lost another universe's latest state");
}
// Exercises normal adaptive observations using actual native workers, without timing-dependent assertions.
bool adaptive_policy() {
    auto core=std::make_shared<PeravizVisualRuntimeCore>(); core->install_compiled_scene(scene_for(false));
    DensePresentationState state; RenderGroupProjection projection;
    if (!bind(state,projection,false)) return false;
    NativeWorkerPool pool(2,false);
    if (!check(!pool.worthwhile(1,1024),"small batches must remain serial")) return false;
    AsyncEvaluationOptions options; options.force=true;
    AsyncPresentationPipeline session(core,std::move(state),std::move(projection),options,&pool);
    uint64_t tasks=0,probes=0; std::array<uint8_t,512> input{};
    for (int step=0;step<4;++step) {
        if (step) {
            input.fill(uint8_t(step*31));
            for (int universe=0;universe<13;++universe) session.submit(universe,input.data(),512);
            session.flush_input();
        }
        const auto *snapshot=await(session); if (!snapshot) return false;
        tasks+=snapshot->parallel.tasks; probes+=snapshot->parallel.serial_probes;
        session.release(snapshot);
    }
    session.stop();
    return check(tasks>=2 && probes>=1,"adaptive production policy did not probe serial and execute useful parallel work");
}
// Cancels an in-flight generation before definitions can be replaced, then verifies a fresh scene completes.
bool cancellation() {
    auto core=std::make_shared<PeravizVisualRuntimeCore>(); core->install_compiled_scene(scene_for(false));
    std::array<uint8_t,512> input{}; input.fill(123); core->submit_universe_frame(0,input.data(),512);
    DensePresentationState state; RenderGroupProjection projection;
    if (!bind(state,projection,false)) return false;
    GateExecutor gate; gate.fail_once=false;
    AsyncEvaluationOptions options; options.workers=2; options.force=true;
    AsyncPresentationPipeline session(core,std::move(state),std::move(projection),options,&gate);
    if (!gate.wait_started()) { gate.release(); return check(false,"cancellation gate did not start"); }
    std::thread stop([&] { session.stop(); });
    while (session.active()) std::this_thread::yield();
    const bool hidden=session.try_acquire()==nullptr;
    gate.release(); stop.join(); session.reclaim(state,projection);
    const auto old_schema=core->schema().schema_generation;
    core->install_compiled_scene(scene_for(false));
    if (!check(hidden && core->schema().schema_generation!=old_schema && session.try_acquire()==nullptr,"cancelled scene published stale results")) return false;
    state.clear(); projection.clear();
    if (!bind(state,projection,false)) return false;
    core->submit_universe_frame(0,input.data(),512);
    AsyncPresentationPipeline fresh(core,std::move(state),std::move(projection),options);
    const auto *snapshot=await(fresh); const bool valid=snapshot && snapshot->schema_generation==core->schema().schema_generation;
    if (snapshot) fresh.release(snapshot); fresh.stop();
    return check(valid,"replacement scene did not safely reuse native execution");
}
}
// Runs focused numerical, ownership, publication and lifecycle validation with no timing assertions.
bool test_parallel_presentation() { return small_serial() && equivalence(true) && equivalence(false) && coalescing() && adaptive_policy() && cancellation(); }
