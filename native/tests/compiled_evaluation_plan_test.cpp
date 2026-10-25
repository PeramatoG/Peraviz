#include "runtime/compiled_evaluation_plan.h"
#include "runtime/peraviz_visual_runtime.h"
#include <array>
#include <iostream>

namespace {
using namespace peraviz::runtime;
// Reports one focused dependency failure without requiring a new test framework.
bool check(bool ok,const char *message) { if (!ok) std::cerr << "evaluation plan: " << message << '\n'; return ok; }
// Exercises nested activation edges, sparse invalidation, cache lifetime, stable consumers and invalid graphs.
bool dependency_graph() {
    std::vector<CompiledDmxSourceProgram> programs(3);
    for (int i=0;i<3;++i) { programs[i].program_id=i+1; programs[i].sources.push_back({0,i,0}); }
    programs[1].activation.target_kind=peraviz::gdtf_runtime::ModeMasterTargetKind::ChannelFunction;
    programs[1].activation.master_program_id=1;
    programs[2].activation=programs[1].activation; programs[2].activation.master_program_id=2;
    CompiledEvaluationPlan plan;
    std::vector<CompiledRuntimeDiagnostic> diagnostics;
    plan.install({&programs[0],&programs[1],&programs[2]},diagnostics);
    const auto source=plan.source_index(3);
    plan.add_consumer(EvaluationDomain::GoboMotion,0,301,{source},true);
    plan.add_consumer(EvaluationDomain::GoboSelection,0,302,{source},true);
    plan.add_consumer(EvaluationDomain::Property,0,303,{source},false);
    plan.finish_install();
    plan.begin_update({2});
    std::vector<int> dirty;
    for (int i:plan.dirty_consumers()) dirty.push_back(i);
    if (!check(dirty==std::vector<int>({0,1,2}),"shared source must nominate every owned consumer in order")) return false;
    plan.store(source,{42,0.5f,180.0f,3,true});
    plan.store_activation(source,true);
    if (!check(plan.activation_cached(source) && plan.activation(source),"activation must be shared within one complete dependency generation")) return false;
    plan.begin_update({0});
    dirty.clear(); for (int i:plan.dirty_consumers()) dirty.push_back(i);
    if (!check(dirty==std::vector<int>({0,1}),"master-only changes must reach activation consumers without changing unsupported property semantics")) return false;
    if (!check(!plan.needs_evaluation(source) && !plan.activation_cached(source) && !plan.source_changed(source) && plan.value(source).raw_value==42,"master change must retain unchanged dependent scalar decoding")) return false;
    plan.begin_update({});
    if (!check(plan.dirty_consumers().begin()==plan.dirty_consumers().end(),"no-change update must nominate nothing")) return false;
    plan.begin_update({2,2});
    if (!check(plan.needs_evaluation(source),"changed own bytes must invalidate cached result")) return false;
    programs[0].activation=programs[1].activation; programs[0].activation.master_program_id=3;
    plan.install({&programs[0],&programs[1],&programs[2]},diagnostics);
    if (!check(!diagnostics.empty() && diagnostics.back().code=="PVZ-EVALUATION-CYCLIC-MASTER","cycle diagnostic must survive graph compilation")) return false;
    programs[0].activation.master_program_id=99;
    diagnostics.clear(); plan.install({&programs[0],&programs[1],&programs[2]},diagnostics);
    return check(!diagnostics.empty() && diagnostics.front().code=="PVZ-EVALUATION-MISSING-MASTER","missing master must remain diagnosed");
}
// Verifies actual shared gobo consumers cache activation once and reconsider master-only changes.
bool shared_activation() {
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1,"generic","Generic","Mode",0,1});
    scene.source_programs.push_back({1,CompiledSemantic::Unknown,{{0,0,0}}});
    scene.source_programs.push_back({2,CompiledSemantic::Unknown,{{0,1,0}}});
    auto &condition=scene.source_programs[0].activation;
    condition.target_kind=peraviz::gdtf_runtime::ModeMasterTargetKind::DmxChannel;
    condition.master_program_id=2; condition.from=128; condition.to=255;
    scene.gobo_bindings.push_back({1,1,201,1,1,1,CompiledGoboSelectionMode::SeatedStatic,{{0,255,1}}});
    scene.gobo_bindings.push_back({2,1,202,1,1,1,CompiledGoboSelectionMode::SeatedStatic,{{0,255,1}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene); runtime.set_performance_trace_enabled(true);
    std::array<uint8_t,512> dmx{}; dmx[0]=100; dmx[1]=200;
    runtime.submit_universe_frame(0,dmx.data(),512);
    const auto first=runtime.consume_latest_visual_frame();
    if (!check(first.integers.size()==18 && first.integers[1]==201 && first.integers[10]==202,"shared gobo source must preserve distinct ordered Beam identities")) return false;
    if (!check(runtime.stats().source_programs_evaluated==2 && runtime.stats().activation_programs_evaluated==1 && runtime.stats().activation_cache_hits==1,"shared raw and activation contexts must evaluate once")) return false;
    dmx[1]=0; runtime.submit_universe_frame(0,dmx.data(),512);
    if (!check(runtime.consume_latest_visual_frame().descriptors.empty(),"deactivated static selection must preserve established held behavior")) return false;
    if (!check(runtime.stats().source_programs_evaluated==3 && runtime.stats().activation_programs_evaluated==2,"master-only update must refresh activation without decoding unchanged dependent bytes")) return false;
    dmx[1]=200; runtime.submit_universe_frame(0,dmx.data(),512);
    if (!check(runtime.consume_latest_visual_frame().descriptors.empty(),"reactivation of unchanged held selection must remain deduplicated")) return false;
    return check(runtime.stats().activation_programs_evaluated==3,"reactivation generation must not reuse stale inactive state");
}
// Checks shared immutable mappings across patches/modes/revisions without sharing target identities or mutable caches.
bool instance_independence() {
    CompiledRuntimeScene scene;
    for (int i=0;i<3;++i) {
        const int fixture=i+1,program=i+1,offset=i*8;
        scene.fixtures.push_back({fixture,"generic-"+std::to_string(fixture),"Generic","Mode",0,offset+1});
        scene.source_programs.push_back({program,CompiledSemantic::Dimmer,{{0,offset,0}},0,255,0.0,1.0,"Dimmer","Dimmer"});
        for (int member=0;member<2;++member)
            scene.properties.push_back({i*2+member+1,fixture,100+i*2+member,200+i*2+member,CompiledSemantic::Dimmer,{{program,1.0}}});
    }
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene); runtime.set_performance_trace_enabled(true);
    const auto size=[&](const char *key) { for (const auto &[name,value]:runtime.state_sizes()) if (std::string(name)==key) return value; return size_t(0); };
    if (!check(size("evaluation_mapping_definitions")==1 && size("evaluation_sources")==3,"identical modes must reuse one immutable mapping, with three instance sources")) return false;
    std::array<uint8_t,512> dmx{}; dmx[0]=32; dmx[8]=128; dmx[16]=255;
    runtime.submit_universe_frame(0,dmx.data(),512);
    const auto first=runtime.consume_latest_visual_frame();
    if (!check(runtime.stats().source_programs_evaluated==3 && runtime.stats().source_cache_hits==3,"each shared source must decode exactly once")) return false;
    size_t rows=0;
    for (size_t b=0;b<first.descriptors.size();b+=5) if (first.descriptors[b]==2) {
        rows+=first.descriptors[b+1];
        for (int row=0;row<first.descriptors[b+1];++row) {
            const int fixture=first.integers[first.descriptors[b+2]+row*3];
            const float value=first.floats[first.descriptors[b+3]+row*5];
            if (!check(value==float(dmx[(fixture-1)*8])/255.0f,"patched fixtures must retain independent physical values")) return false;
        }
    }
    if (!check(rows==6,"every canonical property target must survive shared mapping reuse")) return false;
    dmx[8]=200; runtime.submit_universe_frame(0,dmx.data(),512);
    const auto sparse=runtime.consume_latest_visual_frame();
    if (!check(runtime.stats().source_programs_evaluated==4 && runtime.stats().evaluation_consumers_avoided==4,"sparse update must decode one source and avoid unrelated targets")) return false;
    if (!check(sparse.integers.size()==6 && sparse.integers[0]==2 && sparse.integers[3]==2,"sparse dirty order must preserve only the owning fixture's targets")) return false;
    runtime.submit_universe_frame(0,dmx.data(),512);
    if (!check(runtime.consume_latest_visual_frame().descriptors.empty(),"unchanged DMX must suppress all work")) return false;
    scene.fixtures[1].dmx_mode_name="Other";
    scene.source_programs[2].physical_to=0.5;
    runtime.install_compiled_scene(scene);
    if (!check(size("evaluation_mapping_definitions")==3 && size("evaluation_fixture_modes")==3,"different modes or mapping content revisions must not alias")) return false;
    runtime.clear();
    return check(size("evaluation_sources")==0 && size("evaluation_mapping_definitions")==0,"scene retirement must release graph and instance workspaces");
}
}
// Runs the focused dependency/instance tests alongside existing semantic/temporal regressions.
bool test_compiled_evaluation_plan() { return dependency_graph() && shared_activation() && instance_independence(); }
