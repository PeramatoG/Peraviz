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
        const int universe=i/80, offset=(i%80)*6, id=i+1, target=10001+i;
        scene.fixtures.push_back({id,"generic-"+std::to_string(id),"Generic","RGB",universe,offset+1});
        const std::array<CompiledSemantic,5> semantics={CompiledSemantic::Dimmer,CompiledSemantic::ColorAddRed,
            CompiledSemantic::ColorAddGreen,CompiledSemantic::ColorAddBlue,CompiledSemantic::Zoom};
        for (int c=0;c<5;++c) scene.source_programs.push_back({i*5+c+1,semantics[c],{{universe,offset+c,0}},0,255,0.0,c==4?40.0:1.0});
        scene.properties.push_back({i*2+1,id,target,target,CompiledSemantic::Dimmer,{{i*5+1,1.0}}});
        scene.properties.push_back({i*2+2,id,target,target,CompiledSemantic::Zoom,{{i*5+5,1.0}}});
        CompiledColorTargetProgram color;
        color.color_target_id=target; color.fixture_id=id; color.beam_render_target_id=target; color.additive_source=true;
        for (int c=1;c<4;++c) color.inputs.push_back({i*5+c+1,semantics[c],0.0,true});
        scene.color_targets.push_back(color);
    }
    return scene;
}
// Compares the former intermediate scalar-copy route against the borrowed native transaction.
bool workload(bool compact) {
    auto scene=scene_for(compact);
    PeravizVisualRuntimeCore reference, direct;
    reference.install_compiled_scene(scene); direct.install_compiled_scene(scene);
    DensePresentationState a,b;
    RenderGroupProjection pa,pb;
    DirectPresentationPipeline pipeline;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    std::vector<uint32_t> membership;
    for (int i=0;i<1000;++i) {
        outputs.push_back({20001+i,0.032f});
        const int source=compact?i/50:i;
        for (int section:{2,3,4}) targets.push_back({section,10001+source,uint32_t(i)});
        membership.push_back(compact?i/50:i);
    }
    const size_t rows=compact?20:1000;
    std::vector<RenderPresentationClass> classes(rows,compact?RenderPresentationClass::Aggregated:RenderPresentationClass::Individual);
    if (!a.install(outputs,targets) || !b.install(outputs,targets) || !pa.install(membership,classes) || !pb.install(membership,classes)) return false;
    int64_t reference_ns=0,direct_ns=0,copied=0;
    size_t produced=0;
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
        if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,false)) return false;
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
        produced+=pb.prepared().size();
        if (step==2) capacity=native.floats.capacity();
        if (step>2 && capacity!=native.floats.capacity()) return false;
        a.finish_snapshot(a.generation()); b.finish_snapshot(b.generation());
    }
    // Stale tokens must leave pending DMX untouched; a valid token then consumes it.
    std::array<uint8_t,512> changed{}; changed.fill(123);
    direct.submit_universe_frame(0,changed.data(),512);
    if (pipeline.consume(direct,b,pb,b.generation()+1,direct.schema().schema_generation,false) ||
            pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation+1,false)) return false;
    if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,false) || pb.prepared().empty()) return false;
    b.finish_snapshot(b.generation());
    b.invalidate_renderer(); pb.invalidate();
    if (!pipeline.consume(direct,b,pb,b.generation(),direct.schema().schema_generation,false) || pb.prepared().size()!=rows) return false;
    std::cout << "direct-pipeline " << (compact?"compact":"independent") << " outputs=1000 rows=" << rows
        << " reference_us=" << reference_ns/1000 << " direct_us=" << direct_ns/1000
        << " intermediate_bytes_reference=" << copied << " intermediate_bytes_direct=0 produced_rows=" << produced << " failures=0\n";
    return true;
}
}
// Runs the two bounded workloads without FPS thresholds or hardware dependencies.
bool test_direct_presentation_pipeline() {
    if (!workload(true) || !workload(false)) { std::cerr << "Direct presentation equivalence failed\n"; return false; }
    return true;
}
