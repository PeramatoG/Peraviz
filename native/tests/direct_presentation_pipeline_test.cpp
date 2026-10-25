#include "presentation/direct_presentation_pipeline.h"
#include <array>
#include <cmath>
#include <iostream>
#include <numeric>

namespace {
using namespace peraviz::runtime;
using namespace peraviz::presentation;
using Clock=std::chrono::steady_clock;
// Builds generic shared-source or independently patched RGB/Dimmer/Zoom emitters.
CompiledRuntimeScene scene_for(bool compact) {
    CompiledRuntimeScene scene;
    const int sources=compact?20:1000;
    for (int i=0;i<sources;++i) {
        const int universe=i/80, offset=(i%80)*6, id=i+1;
        scene.fixtures.push_back({id,"generic-"+std::to_string(id),"Generic","RGB",universe,offset+1});
        const std::array<CompiledSemantic,5> semantics={CompiledSemantic::Dimmer,CompiledSemantic::ColorAddRed,
            CompiledSemantic::ColorAddGreen,CompiledSemantic::ColorAddBlue,CompiledSemantic::Zoom};
        for (int c=0;c<5;++c) scene.source_programs.push_back({i*5+c+1,semantics[c],{{universe,offset+c,0}},0,255,0.0,c==4?40.0:1.0});
        for (int member=0;member<(compact?50:1);++member) {
            const int output=compact?i*50+member:i, physical_target=10001+output;
            scene.properties.push_back({output*2+1,id,physical_target,physical_target,CompiledSemantic::Dimmer,{{i*5+1,1.0}}});
            scene.properties.push_back({output*2+2,id,physical_target,physical_target,CompiledSemantic::Zoom,{{i*5+5,1.0}}});
            CompiledColorTargetProgram color;
            color.color_target_id=physical_target; color.fixture_id=id; color.beam_render_target_id=physical_target; color.additive_source=true;
            for (int c=1;c<4;++c) color.inputs.push_back({i*5+c+1,semantics[c],0.0,true});
            scene.color_targets.push_back(color);
        }
    }
    return scene;
}
// Compares the former intermediate scalar-copy route against the borrowed native transaction.
bool workload(bool compact) {
    auto scene=scene_for(compact);
    PeravizVisualRuntimeCore reference, direct;
    reference.install_compiled_scene(scene); direct.install_compiled_scene(scene);
    direct.set_performance_trace_enabled(true);
    DensePresentationState a,b;
    RenderGroupProjection pa,pb;
    DirectPresentationPipeline pipeline;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    std::vector<uint32_t> membership;
    for (int i=0;i<1000;++i) {
        outputs.push_back({20001+i,0.032f});
        for (int section:{2,3,4}) targets.push_back({section,10001+i,uint32_t(i)});
        membership.push_back(compact?i/50:i);
    }
    const size_t rows=compact?20:1000;
    std::vector<RenderPresentationClass> classes(rows,compact?RenderPresentationClass::Aggregated:RenderPresentationClass::Individual);
    if (!a.install(outputs,targets) || !b.install(outputs,targets) || !pa.install(membership,classes) || !pb.install(membership,classes)) return false;
    int64_t reference_ns=0,direct_ns=0,copied=0,evaluation_us=0;
    size_t produced=0;
    uint64_t digest=1469598103934665603ULL;
    const auto hash=[&](const auto &values) {
        const auto *bytes=reinterpret_cast<const unsigned char *>(values.data());
        for (size_t i=0;i<values.size()*sizeof(values[0]);++i) { digest^=bytes[i]; digest*=1099511628211ULL; }
    };
    size_t capacity=0;
    // Includes repeated unchanged packets, blackouts, held replay, and changing independent colors.
    for (int step=0;step<96;++step) {
        const int sample=step/2;
        for (int u=0;u<(compact?1:13);++u) {
            std::array<uint8_t,512> dmx{};
            for (int offset=0;offset<480;offset+=6) for (int c=0;c<5;++c)
                dmx[offset+c]=uint8_t(sample==0?0:(sample*17+u*23+offset*3+c*41)%256);
            reference.submit_universe_frame(u,dmx.data(),512); direct.submit_universe_frame(u,dmx.data(),512);
        }
        if (step==49) { a.invalidate_renderer(); b.invalidate_renderer(); pa.invalidate(); pb.invalidate(); }
        auto start=Clock::now();
        const auto frame=reference.consume_latest_visual_frame();
        // Models the old pack/unpack scalar traffic, without pretending to measure Godot API overhead.
        const auto descriptors=frame.descriptors, integers=frame.integers;
        const auto floats=frame.floats;
        copied+=(descriptors.size()+integers.size()+floats.size())*4;
        if (!a.compose_sections(a.generation(),descriptors.data(),descriptors.size(),integers.data(),integers.size(),floats.data(),floats.size())) return false;
        pa.prepare(a);
        reference_ns+=std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now()-start).count();
        start=Clock::now();
        if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,true)) return false;
        evaluation_us+=pipeline.evaluation_us;
        direct_ns+=std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now()-start).count();
        const auto &native=pipeline.frame();
        if (frame.descriptors!=native.descriptors || frame.integers!=native.integers || frame.floats!=native.floats || a.dirty_indices()!=b.dirty_indices()) return false;
        if (pa.prepared().size()!=pb.prepared().size()) return false;
        if (step%2 && step!=49 && !pb.prepared().empty()) return false;
        if (step%2==0 && pb.prepared().size()!=rows) return false;
        for (size_t i=0;i<outputs.size();++i) {
            if (a.bindings()[i].canonical_id!=b.bindings()[i].canonical_id || a.render_values(i)!=b.render_values(i) || a.pending_mask(i)!=b.pending_mask(i)) return false;
            // Independently calculated dimmer catches a pair of equally wrong empty pipelines.
            const int source=compact?int(i)/50:int(i), u=source/80, offset=(source%80)*6;
            const float expected=float(sample==0?0:(sample*17+u*23+offset*3)%256)/255.0f;
            if (std::abs(b.render_values(i)[Dimmer]-expected)>1e-6f) return false;
        }
        for (size_t r=0;r<pa.prepared().size();++r) {
            const auto &x=pa.prepared()[r], &y=pb.prepared()[r];
            if (x.index!=y.index || x.mask!=y.mask || x.values!=y.values) return false;
        }
        hash(native.descriptors); hash(native.integers); hash(native.floats); hash(b.dirty_indices());
        for (const auto &row:pb.prepared()) { hash(std::array<uint32_t,2>{row.index,row.mask}); hash(row.values); }
        produced+=pb.prepared().size();
        if (step==2) capacity=native.floats.capacity();
        if (step>2 && capacity!=native.floats.capacity()) return false;
        a.finish_snapshot(a.generation()); b.finish_snapshot(b.generation());
    }
    // Sparse updates affect one shared source / one independent source; unchanged peers stay held.
    int64_t sparse_us=0,sparse_evaluation_us=0;
    size_t sparse_rows=0, sparse_dirty=0;
#ifndef PERAVIZ_EVALUATION_REFERENCE
    const auto before=direct.stats();
#endif
    for (int tick=0;tick<32;++tick) {
        std::array<uint8_t,512> dmx{};
        for (int offset=0;offset<480;offset+=6) for (int c=0;c<5;++c)
            dmx[offset+c]=uint8_t((47*17+offset*3+c*41)%256);
        dmx[0]=uint8_t(20+tick);
        direct.submit_universe_frame(0,dmx.data(),512);
        const auto start=Clock::now();
        if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,true)) return false;
        sparse_evaluation_us+=pipeline.evaluation_us;
        sparse_us+=std::chrono::duration_cast<std::chrono::microseconds>(Clock::now()-start).count();
        sparse_rows+=pb.prepared().size(); sparse_dirty+=b.dirty_indices().size();
        if (pb.prepared().size()!=1 || b.dirty_indices().size()!=(compact?50:1)) return false;
        b.finish_snapshot(b.generation());
    }
    std::cout << "evaluation-plan " << (compact?"compact":"independent") << " instances=" << scene.fixtures.size()
        << " evaluation_us=" << evaluation_us << " sparse_evaluation_us=" << sparse_evaluation_us << " sparse_us=" << sparse_us << " sparse_rows=" << sparse_rows << " sparse_dirty=" << sparse_dirty;
#ifndef PERAVIZ_EVALUATION_REFERENCE
    const auto &after=direct.stats();
    std::cout << " high_fanout_source_evaluations=" << before.source_programs_evaluated
        << " sparse_source_evaluations=" << after.source_programs_evaluated-before.source_programs_evaluated
        << " sparse_consumers_avoided=" << after.evaluation_consumers_avoided-before.evaluation_consumers_avoided;
    for (const auto &[key,value]:direct.state_sizes()) if (std::string(key).find("evaluation_")==0) std::cout << " " << key << "=" << value;
#endif
    std::cout << " failures=0\n";
    // Stale tokens must leave pending DMX untouched; a valid token then consumes it.
    std::array<uint8_t,512> changed{}; changed.fill(123);
    direct.submit_universe_frame(0,changed.data(),512);
    if (pipeline.consume(direct,b,pb,b.generation()+1,direct.schema().schema_generation,true) ||
            pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation+1,false)) return false;
    if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,true) || pb.prepared().empty()) return false;
    b.finish_snapshot(b.generation());
    b.invalidate_renderer(); pb.invalidate();
    if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,true) || pb.prepared().size()!=rows) return false;
    std::cout << "direct-pipeline " << (compact?"compact":"independent") << " outputs=1000 rows=" << rows
        << " reference_us=" << reference_ns/1000 << " direct_us=" << direct_ns/1000
        << " intermediate_bytes_reference=" << copied << " intermediate_bytes_direct=0 produced_rows=" << produced << " digest=" << digest << " failures=0\n";
    return true;
}
}
// Runs the two bounded workloads without FPS thresholds or hardware dependencies.
bool test_direct_presentation_pipeline() {
    if (!workload(true) || !workload(false)) { std::cerr << "Direct presentation equivalence failed\n"; return false; }
    return true;
}

// Reuses the established generic workload for focused asynchronous ownership and equivalence tests.
peraviz::runtime::CompiledRuntimeScene make_native_parallel_workload(bool compact) { return scene_for(compact); }
