#include "runtime/peraviz_visual_runtime.h"
#include "runtime/compiled_runtime_scene_codec.h"
#include "presentation/shutter_playback.h"
#include <array>
#include <cmath>
#include <iostream>

namespace {
using namespace peraviz::runtime;
using namespace peraviz::gdtf_runtime;
using peraviz::presentation::ShutterPlayback;
// Reports deterministic numerical failures without hardware-dependent timing thresholds.
bool check(bool ok,const char *message) { if (!ok) std::cerr<<"Shutter: "<<message<<'\n'; return ok; }
// Compares normalized envelopes with only floating-point tolerance.
bool close(double a,double b) { return std::abs(a-b)<0.00001; }
// Builds a minimal typed scene using the real native source graph on two independent universes.
CompiledRuntimeScene fixture() {
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1,"public-shutter","public.gdtf","Mode",0,1});
    CompiledDmxSourceProgram dimmer; dimmer.program_id=1; dimmer.semantic=CompiledSemantic::Dimmer;
    dimmer.sources={{0,0,0}}; scene.source_programs.push_back(dimmer);
    CompiledComponentProperty property; property.property_id=1; property.fixture_id=1; property.component_id=77;
    property.render_target_id=77; property.semantic=CompiledSemantic::Dimmer; property.contributors.push_back({1}); scene.properties.push_back(property);
    for (int id=2;id<=7;++id) {
        CompiledDmxSourceProgram p; p.program_id=id; p.sources={{2,100,0}};
        p.dmx_from=id==2?0:id==3?10:id==4?20:id==5?120:id==6?160:200;
        p.dmx_to=id==2?9:id==3?19:id==4?119:id==5?159:id==6?199:255;
        p.physical_from=2; p.physical_to=id==4?10:2;
        scene.source_programs.push_back(p);
        CompiledShutterBinding b; b.fixture_id=1; b.beam_target_id=77; b.source_program_id=id;
        b.wave=id==2?ShutterWave::Closed:id==3?ShutterWave::Open:id==4?ShutterWave::Strobe:id==5?ShutterWave::Pulse:id==6?ShutterWave::PulseOpen:ShutterWave::PulseClose;
        b.dmx_from=p.dmx_from; b.dmx_to=p.dmx_to; b.physical_from=p.physical_from; b.physical_to=p.physical_to;
        scene.shutter_bindings.push_back(b);
    }
    return scene;
}
// Extracts persistent state through the actual public sectioned contract.
ShutterParameters parameters(const SectionedVisualFrame &frame) {
    for (size_t b=0;b<frame.descriptors.size();b+=5) if (frame.descriptors[b]==int(VisualSectionType::ShutterState)) {
        const auto *i=frame.integers.data()+frame.descriptors[b+2]; const auto *f=frame.floats.data()+frame.descriptors[b+3];
        return {ShutterWave(i[3]),i[6],i[4],i[5],f[0],f[1],f[2],f[3],f[4],f[5]};
    }
    return {};
}
// Adopts native state without any GDScript semantic translation.
void ingest(ShutterPlayback &playback,const SectionedVisualFrame &frame) {
    playback.ingest(frame.descriptors.data(),frame.descriptors.size(),frame.integers.data(),frame.integers.size(),frame.floats.data(),frame.floats.size());
}
}
// Verifies Annex F, persistent hold, source routing, state transitions and generation-independent phase.
bool test_shutter_runtime() {
    using namespace peraviz::gdtf_runtime;
    if (!check(shutter_attribute("Shutter12StrobePulseClose").index==12 && shutter_attribute("Shutter12StrobePulseClose").wave==ShutterWave::PulseClose && shutter_attribute("Shutter3StrobeRandom").wave==ShutterWave::RandomStrobe,"Official numbered periodic and random families")) return false;
    ShutterParameters p; p.wave=ShutterWave::Strobe; p.frequency=10;
    if (!check(close(shutter_envelope(p,0),0) && close(shutter_envelope(p,0.074),0) && close(shutter_envelope(p,0.08),1) && close(shutter_envelope(p,0.11),0),"10 Hz uses a 25 ms end-offset flash, not a 50% square wave")) return false;
    p.frequency=2;
    if (!check(close(shutter_envelope(p,0.46),0) && close(shutter_envelope(p,0.48),1),"2 Hz preserves flash duration in seconds")) return false;
    for (auto wave:{ShutterWave::Pulse,ShutterWave::PulseOpen,ShutterWave::PulseClose}) {
        p.wave=wave;
        const double expected=wave==ShutterWave::Pulse?0.5:wave==ShutterWave::PulseOpen?0.25:0.75;
        if (!check(close(shutter_envelope(p,0.125),expected),"Default Annex F pulse/ramp samples")) return false;
    }
    p.wave=ShutterWave::Pulse; p.duty=0.5; p.offset=0.5;
    if (!check(close(shutter_envelope(p,0.125),1) && close(shutter_envelope(p,0.3),0),"Explicit duty/end offset")) return false;
    p.offset=0.25;
    if (!check(close(shutter_envelope(p,0),1),"Wrapped end offset")) return false;
    auto scene=fixture();
    const auto packed=peraviz::runtime::encode_compiled_runtime_scene(scene);
    const auto decoded=peraviz::runtime::decode_compiled_runtime_scene(packed.integers,packed.floats);
    if (!check(decoded.valid && decoded.scene.shutter_bindings.size()==6,"Typed shutter codec round trip")) return false;
    PeravizVisualRuntimeCore core; core.install_compiled_scene(decoded.scene); core.set_performance_trace_enabled(true); core.set_runtime_now_seconds_for_testing(0);
    ShutterPlayback playback; playback.install({{77,1}});
    std::array<uint8_t,512> primary{},secondary{}; primary[0]=255; secondary[100]=20;
    core.submit_universe_frame(0,primary.data(),512); core.submit_universe_frame(2,secondary.data(),512);
    auto frame=core.consume_latest_visual_frame();
    if (!check(validate_sectioned_visual_frame(core.schema(),frame).valid,"Persistent frame validates against its schema")) return false;
    ingest(playback,frame);
    auto state=parameters(frame);
    if (!check(state.wave==ShutterWave::Strobe && close(state.frequency,2) && close(state.phase,0),"Explicit break chooses the intended source and PhysicalFrom")) return false;
    const auto evaluations=core.stats().source_programs_evaluated;
    if (!check(evaluations>0,"Physical source counters are enabled for the hold regression")) return false;
    for (double now:{0.48,1.48,3.48,8.48}) {
        playback.tick(now);
        if (!check(close(playback.envelopes()[0],1),"Strobe persists for seconds with zero new packets")) return false;
    }
    if (!check(core.stats().source_programs_evaluated==evaluations,"Temporal ticks never re-evaluate physical sources")) return false;
    core.set_runtime_now_seconds_for_testing(0.125);
    core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame();
    if (!check(frame.descriptors.empty(),"Identical DMX does not publish a new parameter state")) return false;
    secondary[100]=119; core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame();
    state=parameters(frame); ingest(playback,frame);
    if (!check(close(state.frequency,10) && close(state.phase,0.25),"Frequency edit integrates old phase instead of resetting")) return false;
    core.set_runtime_now_seconds_for_testing(2); secondary[100]=120; core.submit_universe_frame(2,secondary.data(),512);
    frame=core.consume_latest_visual_frame(); ingest(playback,frame); state=parameters(frame);
    playback.tick(2.25);
    if (!check(state.wave==ShutterWave::Pulse && close(state.phase,0) && close(playback.envelopes()[0],1),"Function change starts pulse at activation, then advances during hold")) return false;
    core.set_runtime_now_seconds_for_testing(3); secondary[100]=10; core.submit_universe_frame(2,secondary.data(),512);
    frame=core.consume_latest_visual_frame(); ingest(playback,frame); playback.tick(3);
    if (!check(close(playback.envelopes()[0],1) && playback.active()==0,"Open immediately stops periodic activity")) return false;
    secondary[100]=0; core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame(); ingest(playback,frame); playback.tick(3);
    const auto idle=playback.evaluations(); playback.tick(1000);
    if (!check(close(playback.envelopes()[0],0) && idle==playback.evaluations(),"Closed is steady with no per-frame waveform work")) return false;
    secondary[100]=20; core.set_runtime_now_seconds_for_testing(5); core.submit_universe_frame(2,secondary.data(),512);
    frame=core.consume_latest_visual_frame(); ingest(playback,frame); playback.tick(5.48);
    const auto replay=core.held_domain_replay(); ingest(playback,replay); playback.tick(5.48);
    if (!check(close(playback.envelopes()[0],1),"Held replay preserves phase/revision")) return false;
    auto mode_scene=fixture();
    CompiledDmxSourceProgram master; master.program_id=99; master.sources={{2,101,0}}; mode_scene.source_programs.push_back(master);
    auto &strobe=mode_scene.source_programs[3];
    strobe.activation.target_kind=ModeMasterTargetKind::DmxChannel; strobe.activation.master_program_id=99; strobe.activation.from=128; strobe.activation.to=255;
    core.install_compiled_scene(mode_scene); core.set_runtime_now_seconds_for_testing(0); secondary[100]=20; secondary[101]=0;
    core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame();
    if (!check(parameters(frame).wave==ShutterWave::Open,"Inactive ModeMaster stops the shutter")) return false;
    secondary[101]=128; core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame();
    if (!check(parameters(frame).wave==ShutterWave::Strobe,"Independent mode channel activates the same generic native source graph")) return false;
    // Different numbered shutters on one emitter compose without merging their logical identities.
    auto layered=fixture();
    auto second=layered.shutter_bindings.front(); second.shutter_index=2; second.wave=ShutterWave::Closed;
    second.source_program_id=99; second.dmx_from=0; second.dmx_to=255;
    master.sources={{2,101,0}}; layered.source_programs.push_back(master); layered.shutter_bindings.push_back(second);
    core.install_compiled_scene(layered); core.set_runtime_now_seconds_for_testing(0);
    playback.install({{77,1}}); secondary[100]=20; secondary[101]=0;
    core.submit_universe_frame(2,secondary.data(),512); frame=core.consume_latest_visual_frame(); ingest(playback,frame); playback.tick(0.48);
    if (!check(playback.layers()==2 && close(playback.envelopes()[0],0),"Independent closed numbered shutter gates the otherwise open flash")) return false;
    // Unsupported activation contexts are diagnosed once per fixture and never become default-universe sources.
    master.sources={{3,101,0}};
    auto unresolved=mode_scene; unresolved.source_programs.back()=master;
    core.install_compiled_scene(unresolved); core.submit_universe_frame(2,secondary.data(),512);
    frame=core.consume_latest_visual_frame();
    bool diagnosed=false;
    for (const auto &d:core.diagnostics()) diagnosed|=d.code=="PVZ-SHUTTER-ACTIVATION-UNRESOLVED";
    if (!check(diagnosed && parameters(frame).revision==0,"Cross-universe activation remains explicit and unbound")) return false;
    return true;
}
