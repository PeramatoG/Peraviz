#include "archive/zip_archive.h"
#include "mvr_scene_loader.h"
#include <fstream>
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "runtime/peraviz_visual_runtime.h"
#include "presentation/shutter_playback.h"
#include "gdtf_runtime/shutter_sampling.h"
#include <array>
#include <chrono>
#include <filesystem>
#include <iostream>

namespace {
using namespace peraviz;
using namespace gdtf_runtime;
using namespace runtime;
// Reports numerical/parser regressions with their causal assertion.
bool verify(bool value,const char *message) { if (!value) std::cerr<<"Shutter fidelity: "<<message<<'\n'; return value; }
// Keeps numerical assertions independent of CPU/GPU speed.
bool near(double a,double b) { return std::abs(a-b)<0.00001; }
// Drives the production archive compiler and real ordered-byte graph, rather than synthesizing semantic rows.
struct Probe {
    std::filesystem::path root=std::filesystem::temp_directory_path()/("public-shutter-fidelity-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    CompiledRuntimeScene scene;
    PeravizVisualRuntimeCore core;
    int serial=0,bytes=1;
    // Retires all public synthetic archives even after a failed assertion.
    ~Probe() { std::filesystem::remove_all(root); }
    // Creates a fresh resource identity per fixture so production immutable template caching remains valid.
    void compile(const std::string &functions,int resolution=1,const std::string &additional_logical="",const std::string &attribute="Shutter1",const std::string &metadata="") {
        bytes=resolution; std::filesystem::create_directories(root);
        const auto path=root/("source-"+std::to_string(++serial)+".gdtf");
        std::string offsets="1"; for (int b=2;b<=bytes;++b) offsets+=","+std::to_string(b);
        const std::string attributes=metadata.empty()?"<Attribute Name=\"Shutter1Strobe\" PhysicalUnit=\"Frequency\"/><Attribute Name=\"Shutter1StrobePulse\" PhysicalUnit=\"Frequency\"/>":metadata;
        const std::string xml="<GDTF DataVersion=\"1.2\"><FixtureType Name=\"Public\"><AttributeDefinitions><Attributes>"
            +attributes+"</Attributes></AttributeDefinitions><Geometries><Geometry Name=\"Root\"><Beam Name=\"Beam\" BeamType=\"Wash\" BeamAngle=\"25\" LuminousFlux=\"1000\"/></Geometry></Geometries>"
            "<DMXModes><DMXMode Name=\"Mode\" Geometry=\"Root\"><DMXChannels><DMXChannel Offset=\"512\" Geometry=\"Root\"><LogicalChannel Attribute=\"Dimmer\"><ChannelFunction Attribute=\"Dimmer\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel></DMXChannel>"
            "<DMXChannel Offset=\""+offsets+"\" Geometry=\"Root\"><LogicalChannel Attribute=\""+attribute+"\">"+functions+"</LogicalChannel>"+additional_logical+"</DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
        { archive::ZipArchive zip; zip.open_create_or_modify(path); zip.write_file("description.xml",xml); zip.close(); }
        const auto mvr=root/("source-"+std::to_string(serial)+".mvr");
        const std::string source="<GeneralSceneDescription verMajor=\"1\" verMinor=\"6\"><Scene><Layers><Layer uuid=\"public-layer\"><ChildList><Fixture uuid=\"public-fixture\"><GDTFSpec>"+path.filename().string()+"</GDTFSpec><GDTFMode>Mode</GDTFMode><Addresses><Address>1.1</Address></Addresses></Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
        std::ifstream file(path,std::ios::binary); const std::string resource((std::istreambuf_iterator<char>(file)),std::istreambuf_iterator<char>());
        { archive::ZipArchive zip; zip.open_create_or_modify(mvr); zip.write_file("GeneralSceneDescription.xml",source); zip.write_file(path.filename().string(),resource); zip.close(); }
        auto model=load_mvr(mvr.string(),false,false);
        scene=compile_runtime_scene(model,-1); core.install_compiled_scene(scene); core.set_runtime_now_seconds_for_testing(0);
    }
    // Converts raw 8/16/24/32-bit inputs in declared coarse/fine order, preserving function-local ranges.
    ShutterParameters raw(uint32_t value) {
        std::array<uint8_t,512> frame{}; frame[511]=255;
        for (int b=0;b<bytes;++b) frame[b]=uint8_t(value>>(8*(bytes-b-1)));
        core.submit_universe_frame(0,frame.data(),512); core.consume_latest_visual_frame();
        const auto held=core.held_domain_replay();
        for (size_t b=0;b<held.descriptors.size();b+=5) if (held.descriptors[b]==int(VisualSectionType::ShutterState)) {
            const auto *i=held.integers.data()+held.descriptors[b+2]; const auto *f=held.floats.data()+held.descriptors[b+3];
            ShutterParameters p{ShutterWave(i[3]),i[6],i[4],i[5],f[0],f[1],f[2],f[3],f[4],f[5]}; p.activation=i[7]; p.seed=uint32_t(i[9]); return p;
        }
        return {};
    }
};
}
// Verifies standards defaults, supplied values, inclusive boundaries and ordered resolution through actual GDTF ZIP parsing.
bool test_shutter_fidelity() {
    Probe probe;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\"/>");
    if (!verify(probe.raw(255).wave==ShutterWave::Strobe && near(probe.raw(255).frequency,1),"Omitted physical fields use valid 0/1 defaults")) return false;
    if (!verify(probe.raw(0).wave==ShutterWave::Strobe && near(probe.raw(0).frequency,0),"Zero Hz remains zero, not an arbitrary rate or malformed default")) return false;
    for (const auto &d:probe.scene.diagnostics) if (!verify(d.code!="PVZ-GDTF-PHYSICAL-MISSING" && d.code!="PVZ-SHUTTER-SEMANTICS-UNSUPPORTED","Valid defaults do not produce false diagnostics")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalTo=\"12\"/>");
    if (!verify(near(probe.raw(255).frequency,12),"Explicit PhysicalTo is read independently of missing PhysicalFrom")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalTo=\"+12.5\"/>");
    if (!verify(near(probe.raw(255).frequency,12.5),"GDTF decimal parsing is locale-independent and accepts an explicit positive sign")) return false;
    for (const auto &field:{"PhysicalFrom=\"bad\"","PhysicalTo=\"nan\"","PhysicalTo=\"inf\"","PhysicalTo=\"2oops\""}) {
        probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" "+std::string(field)+"/>");
        auto p=probe.raw(128);
        if (!verify(p.wave==ShutterWave::Unsupported && p.status==2,"Malformed supplied physical metadata is diagnosed and never flashes")) return false;
    }
    for (const auto &fields:{"PhysicalFrom=\"5\"","PhysicalTo=\"6\""}) {
        probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"2\" PhysicalTo=\"10\"><ChannelSet "+std::string(fields)+"/></ChannelFunction>");
        if (!verify(near(probe.raw(0).frequency,std::string(fields).find("PhysicalFrom")==0?5:2) && near(probe.raw(255).frequency,std::string(fields).find("PhysicalFrom")==0?10:6),"One-sided ChannelSet physical overrides inherit the other parent endpoint")) return false;
    }
    probe.compile("<ChannelFunction Attribute=\"StrobeRate\" PhysicalFrom=\"0.1\" PhysicalTo=\"0.2\"/>");
    bool rate_diagnosed=false;
    for (const auto &d:probe.scene.diagnostics) rate_diagnosed|=d.code=="PVZ-SHUTTER-RATE-UNSUPPORTED";
    if (!verify(rate_diagnosed && probe.raw(255).status==2,"StrobeRate remains an explicit unsupported time parameter, never frequency Hz")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"-2\" PhysicalTo=\"-1\"/>");
    if (!verify(probe.raw(0).status==2,"Negative frequency cannot produce an arbitrary positive strobe")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"2\" PhysicalTo=\"10\"/>",1,"","Shutter1","<Attribute Name=\"Shutter1Strobe\"><SubPhysicalUnit Type=\"Duration\" PhysicalFrom=\"0.01\" PhysicalTo=\"0.01\"/></Attribute>");
    if (!verify(probe.raw(128).status==0 && near(probe.raw(128).duration,0.01),"Declared duration retains contextual Time semantics with default None unit")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"2\" PhysicalTo=\"10\"/>",1,"","Shutter1","<Attribute Name=\"Shutter1Strobe\"><SubPhysicalUnit Type=\"Duration\" PhysicalFrom=\"bad\" PhysicalTo=\"0\"/></Attribute>");
    if (!verify(probe.raw(128).status==2,"Malformed SubPhysicalUnit text cannot silently become a valid zero-duration default")) return false;
    probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"2\" PhysicalTo=\"10\"/><ChannelFunction Attribute=\"Shutter1StrobePulse\"/><ChannelFunction Name=\"Closed\" Attribute=\"Shutter1\" DMXFrom=\"100/1\"/>");
    bool duplicate_diagnosed=false;
    for (const auto &d:probe.scene.diagnostics) duplicate_diagnosed|=d.code=="PVZ-SHUTTER-RANGE-INVALID";
    if (!verify(duplicate_diagnosed && probe.raw(50).wave==ShutterWave::Open && probe.raw(128).wave==ShutterWave::Closed,"Duplicate unconditional function starts cannot select the first arbitrary strobe; independent valid ranges remain usable")) return false;
    const std::string open="<ChannelFunction Name=\"Open\" Attribute=\"Shutter1\"/>";
    const std::string closed="<ChannelFunction Name=\"Closed\" Attribute=\"Shutter1\" DMXFrom=\"40/1\"/>";
    probe.compile(open+"<ChannelFunction Attribute=\"Shutter1Strobe\" DMXFrom=\"20/1\" PhysicalFrom=\"2\" PhysicalTo=\"10\"/>"+closed);
    for (uint32_t raw:{19,20,39,40}) {
        const auto p=probe.raw(raw);
        if (!verify(raw==19?p.wave==ShutterWave::Open:raw==40?p.wave==ShutterWave::Closed:p.wave==ShutterWave::Strobe && near(p.frequency,raw==20?2:10),"Function start-1/start/end/end+1 select exact waveform and Hz")) return false;
    }
    probe.compile(open+"<ChannelFunction Attribute=\"Shutter1Strobe\" DMXFrom=\"20/1\" PhysicalFrom=\"8\" PhysicalTo=\"4\"><ChannelSet/><ChannelSet DMXFrom=\"30/1\" PhysicalFrom=\"12\" PhysicalTo=\"12\"/><ChannelSet DMXFrom=\"39/1\" PhysicalFrom=\"7\" PhysicalTo=\"7\"/></ChannelFunction>"+closed);
    for (const auto &[raw,hz]:std::array<std::pair<uint32_t,double>,6>{{{20,8},{29,4},{30,12},{38,12},{39,7},{40,0}}}) {
        const auto p=probe.raw(raw);
        if (!verify(raw==40?p.wave==ShutterWave::Closed:near(p.frequency,hz),"Default set start, inherited descending endpoints, fixed values and inclusive narrow boundaries")) return false;
    }
    for (int bytes=1;bytes<=4;++bytes) {
        const uint32_t maximum=bytes==4?UINT32_MAX:uint32_t((uint64_t(1)<<(bytes*8))-1);
        const uint32_t start=maximum/4, end=maximum/2;
        const std::string from=std::to_string(start)+"/"+std::to_string(bytes), to=std::to_string(end+1)+"/"+std::to_string(bytes);
        probe.compile(open+"<ChannelFunction Attribute=\"Shutter1Strobe\" DMXFrom=\""+from+"\" PhysicalFrom=\"20\" PhysicalTo=\"2\"/><ChannelFunction Name=\"Closed\" Attribute=\"Shutter1\" DMXFrom=\""+to+"\"/>",bytes);
        for (uint32_t raw:{start-1,start,(start+end)/2,end,end+1}) {
            const auto p=probe.raw(raw); const double hz=20-18*double(raw-start)/double(end-start);
            if (!verify(raw<start?p.wave==ShutterWave::Open:raw>end?p.wave==ShutterWave::Closed:near(p.frequency,hz),"Ordered 8/16/24/32-bit source maps only its active function range, including descending interpolation")) return false;
        }
    }
    for (const auto &sets:{"<ChannelSet/><ChannelSet DMXFrom=\"0/1\"/>","<ChannelSet DMXFrom=\"oops\"/>","<ChannelSet PhysicalTo=\"junk\"/>"}) {
        probe.compile("<ChannelFunction Attribute=\"Shutter1Strobe\" PhysicalFrom=\"2\" PhysicalTo=\"10\">"+std::string(sets)+"</ChannelFunction>");
        if (!verify(probe.raw(128).status==2,"Malformed sets never invent coverage or flashing")) return false;
    }
    probe.compile("<ChannelFunction Attribute=\"NoFeature\"/><ChannelFunction Attribute=\"Shutter1Strobe\" DMXFrom=\"20/1\" PhysicalFrom=\"2\" PhysicalTo=\"10\"/><ChannelFunction Attribute=\"NoFeature\" DMXFrom=\"40/1\"/>",1,
        "<LogicalChannel Attribute=\"Shutter1StrobePulse\"><ChannelFunction Attribute=\"NoFeature\"/><ChannelFunction Attribute=\"Shutter1StrobePulse\" DMXFrom=\"60/1\" PhysicalFrom=\"3\" PhysicalTo=\"3\"/><ChannelFunction Attribute=\"NoFeature\" DMXFrom=\"80/1\"/></LogicalChannel>");
    for (uint32_t raw:{19,20,39,40,59,60,79,80}) {
        const auto p=probe.raw(raw);
        if (!verify(raw>=20 && raw<40?p.wave==ShutterWave::Strobe:raw>=60 && raw<80?p.wave==ShutterWave::Pulse:p.wave==ShutterWave::Open,"Mutually exclusive split LogicalChannels create neither activation gaps nor overlapping shutters")) return false;
    }
    for (const auto &label:{"  Shutter: OPEN  ","open-shutter","Shutter (Closed)","CLOSED_shutter"})
        if (!verify(shutter_label(label)!=ShutterWave::Unsupported,"Normalized unambiguous polarity labels")) return false;
    for (const auto &label:{"offset","strobe off","shutter offset","closed loop","Open/Closed","off"})
        if (!verify(shutter_label(label)==ShutterWave::Unsupported,"Misleading manufacturer text never establishes polarity")) return false;
    for (const auto &family:{"StrobeRandom","StrobeRandomPulse","StrobeRandomPulseOpen","StrobeRandomPulseClose"}) {
        probe.compile("<ChannelFunction Attribute=\"Shutter12"+std::string(family)+"\" PhysicalFrom=\"5\" PhysicalTo=\"10\"/>");
        auto p=probe.raw(255);
        if (!verify(shutter_random(p.wave) && near(p.frequency,10) && p.status==1,"All numbered random families compile as explicitly approximate, physical-rate-driven waveforms")) return false;
        p.duty=0.1; p.offset=1;
        const double width=shutter_shape(p.wave)==ShutterWave::Strobe?p.duration*p.frequency:p.duty;
        double previous=shutter_event_start(p,0); bool varied=false;
        for (int event=1;event<1000;++event) {
            const double next=shutter_event_start(p,event), interval=next-previous;
            if (!verify(interval>=0.5 && interval<=1.5,"Random event intervals stay bounded without mutable RNG or catch-up loops")) return false;
            varied|=std::abs(interval-1)>0.01; previous=next;
        }
        if (!verify(varied && std::abs((shutter_event_start(p,999)-shutter_event_start(p,0))/999-1)<0.001,"Nominal physical frequency controls the long-run event rate deterministically")) return false;
        const double time=(p.offset-width+shutter_event_start(p,5)+width*0.25)/p.frequency;
        const auto shape=shutter_shape(p.wave); const double expected=shape==ShutterWave::Strobe?1:shape==ShutterWave::Pulse?0.5:shape==ShutterWave::PulseOpen?0.25:0.75;
        if (!verify(near(shutter_envelope(p,time),expected),"Random square, triangle, opening and closing shapes remain distinct")) return false;
        auto independent=p; ++independent.seed;
        if (!verify(shutter_event_start(p,5)!=shutter_event_start(independent,5),"Physical identities have independent deterministic random timing")) return false;
        auto next=p; next.frequency=5;
        if (!verify(update_shutter(p,next,100) && p.activation==next.activation && p.phase>900,"Frequency change preserves random event progression and activation identity")) return false;
        const auto revision=p.revision;
        if (!verify(!update_shutter(p,next,101) && p.revision==revision,"Identical random state never restarts its sequence")) return false;
        next=p; next.function_id+=1;
        if (!verify(update_shutter(p,next,102) && p.phase==0 && p.activation==revision+1,"A new function activation starts a distinct sequence")) return false;
    }
    probe.compile("<ChannelFunction Attribute=\"Shutter1StrobeRandom\" PhysicalFrom=\"50\" PhysicalTo=\"50\"/>");
    auto long_flash=probe.raw(255);
    const double width=long_flash.duration*long_flash.frequency;
    for (int event=2;event<100;++event) {
        const double start=(long_flash.offset-width+shutter_event_start(long_flash,event))/long_flash.frequency;
        if (!verify(near(shutter_envelope(long_flash,start+long_flash.duration*0.01),1),"Random flashes retain their full 25 ms Duration even when longer than the nominal period")) return false;
    }
    long_flash.frequency=100;
    if (!verify(near(shutter_envelope(long_flash,0),1) && near(shutter_envelope(long_flash,3.14159),1),"Overlapping long random flashes remain lit without truncating their physical duration")) return false;
    for (const auto &wave:{ShutterWave::Pulse,ShutterWave::PulseOpen,ShutterWave::PulseClose}) for (double duty:{0.01,0.95}) for (double offset:{0.0,0.25,0.75,1.0}) {
        ShutterParameters p; p.wave=wave; p.frequency=2; p.duty=duty; p.offset=offset;
        const double cycle=shutter_fraction(offset-duty+0.25*duty);
        const double expected=wave==ShutterWave::Pulse?0.5:wave==ShutterWave::PulseOpen?0.25:0.75;
        if (!verify(near(shutter_envelope(p,cycle/p.frequency),expected),"Annex F end offsets and low/high duty cycles preserve triangle/ramp samples")) return false;
    }
    ShutterParameters short_flash; short_flash.wave=ShutterWave::Strobe; short_flash.frequency=10; short_flash.duration=0.001;
    const auto samples=shutter_sampling(short_flash);
    if (!verify(samples[1].events==20 && samples[1].visible_events<20 && near(samples[1].event_window_seconds,0.02),"Exact 1 ms flashes can alias at 30 FPS without any wrong DMX/Hz mapping")) return false;
    std::cout<<"SHUTTER_SAMPLING 10 Hz / 1 ms, 20 exact events:";
    for (const auto &sample:samples) std::cout<<" "<<sample.fps<<"fps="<<sample.visible_events;
    std::cout<<'\n';
    return true;
}
