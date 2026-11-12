#include "archive/zip_archive.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "mvr_scene_loader.h"
#include "runtime/peraviz_visual_runtime.h"
#include "runtime/realtime_dmx_coordinator.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace peraviz;
using namespace peraviz::gdtf_runtime;
using namespace peraviz::runtime;
namespace {
// Gives each deterministic setup/output assertion a focused failure message.
void check(bool value,const char *message) { if (!value) throw std::runtime_error(message); }
// Produces a minimal selected-mode control without borrowing vendor fixture data.
std::string channel(const std::string &offset,const std::string &attribute,int cell) {
    return "<DMXChannel Offset=\""+offset+"\" Geometry=\"Cell"+std::to_string(cell)+"\"><LogicalChannel Attribute=\""+attribute+"\"><ChannelFunction Attribute=\""+attribute+"\" PhysicalFrom=\"0\" PhysicalTo=\""+(attribute=="Pan"?"100":"1")+"\"/></LogicalChannel></DMXChannel>";
}
// Generates one public ZIP model with independent 30-channel outputs and alternative semantic modes.
SceneModel fixture_scene(const std::filesystem::path &root,const std::string &extra="",int destination=9) {
    std::string beams,controls;
    for (int i=0;i<30;++i) { beams+="<Beam Name=\"Cell"+std::to_string(i)+"\" BeamType=\"Glow\"/>"; controls+=channel(std::to_string(i+1),"Dimmer",i); }
    const auto mode=[](const std::string &name,const std::string &channels) { return "<DMXMode Name=\""+name+"\" Geometry=\"Root\"><DMXChannels>"+channels+"</DMXChannels></DMXMode>"; };
    std::string rgbw=channel("1","ColorAdd_R",0)+channel("2","ColorAdd_G",0)+channel("3","ColorAdd_B",0)+channel("4","ColorAdd_W",0)+channel("2","Dimmer",1);
    auto second_break=channel("1","Dimmer",1); second_break.insert(std::string("<DMXChannel").size()," DMXBreak=\"2\"");
    const std::string xml="<GDTF DataVersion=\"1.2\"><FixtureType Name=\"Synthetic\"><Geometries><Geometry Name=\"Root\">"+beams+"</Geometry></Geometries><DMXModes>"+mode("Thirty",controls)+mode("Other",channel("1","Pan",0)+channel("2","Dimmer",1)+channel("3","Dimmer",2)+channel("4","Dimmer",3))+mode("Wide",channel("1,2","Dimmer",0)+channel("3,4,5,6","Dimmer",1)+channel("7","Dimmer",2))+mode("RGBW",rgbw)+mode("Multi",channel("1,2","Dimmer",0)+second_break)+mode("Unknown",channel("1","Fog1",0))+mode("Shutter",channel("1","Shutter1",0))+mode("Gobo",channel("1","Gobo1",0))+mode("Wheel",channel("1","Color1",0))+"</DMXModes></FixtureType></GDTF>";
    { archive::ZipArchive zip; check(zip.open_create_or_modify(root/"policy.gdtf"),"Create GDTF"); check(zip.write_file("description.xml",xml)&&zip.close(),"Write GDTF"); }
    const auto fixture=[](const std::string &id,const std::string &mode,const std::string &patch) {return "<Fixture uuid=\""+id+"\"><GDTFSpec>policy.gdtf</GDTFSpec><GDTFMode>"+mode+"</GDTFMode><Addresses><Address>"+patch+"</Address></Addresses></Fixture>";};
    std::string instances=fixture("A","Thirty","1.500");
    if (extra=="other") instances+=fixture("B","Other","2."+std::to_string(destination));
    if (extra=="candidate") instances+=fixture("B","Thirty","1.500");
    if (extra=="copatch") instances+=fixture("B","Other","1.500");
    if (extra=="unknown") instances+="<Fixture uuid=\"B\"><GDTFSpec>missing.gdtf</GDTFSpec><GDTFMode>Missing</GDTFMode><Addresses><Address>2.1</Address></Addresses></Fixture>";
    std::ifstream stream(root/"policy.gdtf",std::ios::binary); const std::string data{std::istreambuf_iterator<char>(stream),{}};
    { archive::ZipArchive zip; check(zip.open_create_or_modify(root/"policy.mvr"),"Create MVR"); check(zip.write_file("policy.gdtf",data)&&zip.write_file("GeneralSceneDescription.xml","<GeneralSceneDescription><Scene><Layers><Layer uuid=\"layer\"><ChildList>"+instances+"</ChildList></Layer></Layers></Scene></GeneralSceneDescription>")&&zip.close(),"Write MVR"); }
    return load_mvr((root/"policy.mvr").string());
}
// Counts retained independent controls by canonical fixture identity, not declaration order.
size_t controls(const CompiledRuntimeScene &scene,const std::string &uuid) {
    for (const auto &fixture:scene.fixtures) if (fixture.fixture_uuid==uuid)
        return std::count_if(scene.properties.begin(),scene.properties.end(),[&](const auto &p){return p.fixture_id==fixture.fixture_id;});
    return 0;
}
// Checks bounded status codes without depending on unrelated parser warnings.
bool status(const CompiledRuntimeScene &scene,const std::string &code) {
    return std::any_of(scene.diagnostics.begin(),scene.diagnostics.end(),[&](const auto &d){return d.code==code;});
}
// Exercises actual native physical interpretation of shared bytes through the normal mailbox coordinator.
void shared_outputs(const CompiledRuntimeScene &scene) {
    PeravizVisualRuntimeCore core; core.install_compiled_scene(scene);
    dmx::RealtimeUniverseMailbox mailbox; RealtimeDmxCoordinator coordinator; coordinator.install_subscription(core,mailbox);
    std::array<uint8_t,512> data{}; data[8]=128;
    mailbox.publish(1,data.data(),512,0,1); data.fill(0); mailbox.publish(0,data.data(),512,0,2); coordinator.pump(core,mailbox);
    const auto frame=core.consume_latest_visual_frame(); bool dimmer=false,pan=false;
    int a=0,b=0; for (const auto &fixture:scene.fixtures) (fixture.fixture_uuid=="A"?a:b)=fixture.fixture_id;
    for (size_t d=0;d<frame.descriptors.size();d+=5) for (int row=0;row<frame.descriptors[d+1];++row) {
        const int type=frame.descriptors[d],io=frame.descriptors[d+2]+row*(type==1?4:3),fo=frame.descriptors[d+3]+row*(type==1?2:5);
        if (type==2 && frame.integers[io]==a && std::fabs(frame.floats[fo]-128.0f/255)<0.0001f) dimmer=true;
        if (type==1 && frame.integers[io]==b && std::fabs(frame.floats[fo]-100*128.0f/255)<0.0001f) pan=true;
    }
    check(dimmer && pan,"Overlap must feed identical bytes to independent Dimmer and Pan semantics");
}
}
// Covers deterministic automatic admission, competing continuations, conservative unknowns and complete-control fallback.
bool test_automatic_auto_span() {
    const auto root=std::filesystem::current_path()/"automatic_policy_fixture"; std::filesystem::create_directories(root);
    try {
        auto free=fixture_scene(root);
        for (auto policy:{AutoSpanPolicy::Off,AutoSpanPolicy::AutoSafe,AutoSpanPolicy::AutoOverlap}) {
            RuntimeRoutingOptions options; options.policy=policy;
            const auto scene=compile_runtime_scene(free,-1,options);
            check(controls(scene,"A")==size_t(policy==AutoSpanPolicy::Off?13:30),"Free continuation policy admission or strict retention failed");
        }
        for (int destination:{1,9,17}) {
            auto occupied=fixture_scene(root,"other",destination);
            for (auto policy:{AutoSpanPolicy::Off,AutoSpanPolicy::AutoSafe,AutoSpanPolicy::AutoOverlap}) {
                RuntimeRoutingOptions options; options.policy=policy;
                const auto scene=compile_runtime_scene(occupied,-1,options);
                check(controls(scene,"A")==size_t(policy==AutoSpanPolicy::AutoOverlap?30:13) && controls(scene,"B")==4,"Collision suppressed complete independent fixture controls");
                if (policy==AutoSpanPolicy::AutoSafe) check(status(scene,"PVZ-AUTO-SPAN-DENIED-OVERLAP"),"Missing safe overlap diagnostic");
                if (policy==AutoSpanPolicy::AutoOverlap) check(status(scene,"PVZ-AUTO-SPAN-OVERLAP"),"Missing permissive overlap warning");
                std::reverse(occupied.fixture_patches.begin(),occupied.fixture_patches.end());
                const auto reversed=compile_runtime_scene(occupied,-1,options);
                check(controls(reversed,"A")==controls(scene,"A") && controls(reversed,"B")==4,"Fixture order changed automatic admission");
            }
            if (destination==9) { RuntimeRoutingOptions overlap; overlap.policy=AutoSpanPolicy::AutoOverlap; shared_outputs(compile_runtime_scene(occupied,-1,overlap)); }
        }
        auto competing=fixture_scene(root,"candidate");
        const auto safe=compile_runtime_scene(competing,-1);
        check(controls(safe,"A")==13 && controls(safe,"B")==13,"Neither competing inferred continuation may win by declaration order");
        RuntimeRoutingOptions overlap; overlap.policy=AutoSpanPolicy::AutoOverlap;
        const auto both=compile_runtime_scene(competing,-1,overlap);
        check(controls(both,"A")==30 && controls(both,"B")==30,"Permissive continuations must preserve both candidates");
        auto copatch=fixture_scene(root,"copatch"); const auto co=compile_runtime_scene(copatch,-1);
        check(controls(co,"A")==30 && controls(co,"B")==4,"Ordinary same-universe co-patching must not prevent a free continuation");
        auto unknown=fixture_scene(root,"unknown"); const auto denied=compile_runtime_scene(unknown,-1);
        check(controls(denied,"A")==13 && status(denied,"PVZ-AUTO-SPAN-DENIED-UNKNOWN"),"Unknown occupancy was incorrectly treated as free");
        auto wide=fixture_scene(root); wide.fixture_patches[0].dmx_mode="Wide"; wide.fixture_patches[0].mvr_address=511; wide.fixture_patches[0].addresses[0].address=511;
        RuntimeRoutingOptions off; off.policy=AutoSpanPolicy::Off;
        const auto partial=compile_runtime_scene(wide,-1,off);
        check(controls(partial,"A")==1 && partial.source_programs.front().sources.size()==2,"Strict fallback must retain complete 16-bit but never half of a 32-bit control");
        wide.fixture_patches[0].mvr_address=512; wide.fixture_patches[0].addresses[0].address=512;
        check(compile_runtime_scene(wide,-1,off).properties.empty(),"Split 16-bit control was decoded partially");
        wide.fixture_patches[0].mvr_address=509; wide.fixture_patches[0].addresses[0].address=509;
        const auto wide_span=compile_runtime_scene(wide,-1,overlap);
        PeravizVisualRuntimeCore wide_runtime; wide_runtime.install_compiled_scene(wide_span);
        std::array<uint8_t,512> coarse{},fine{}; coarse[510]=0x12; coarse[511]=0x34; fine[0]=0x56; fine[1]=0x78;
        wide_runtime.submit_universe_frame(1,fine.data(),512); wide_runtime.submit_universe_frame(0,coarse.data(),512);
        const auto wide_frame=wide_runtime.consume_latest_visual_frame(); bool ordered32=false;
        const float expected32=float(double(0x12345678U)/double(0xffffffffU));
        for (size_t d=0;d<wide_frame.descriptors.size();d+=5) if (wide_frame.descriptors[d]==2)
            for (int row=0;row<wide_frame.descriptors[d+1];++row) {
                const int index=wide_frame.descriptors[d+3]+row*5;
                if (std::fabs(wide_frame.floats[index]-expected32)<0.00001f && std::fabs(wide_frame.floats[index+4]-4*expected32)<0.00001f) ordered32=true;
            }
        check(ordered32,"Split 32-bit control lost ordered bytes or final material intensity");
        check(controls(compile_runtime_scene(wide,-1,off),"A")==1,"Strict fallback decoded part of a split 32-bit source");
        wide.fixture_patches[0].dmx_mode="RGBW";
        wide.fixture_patches[0].mvr_address=509; wide.fixture_patches[0].addresses[0].address=509;
        check(compile_runtime_scene(wide,-1,off).color_targets.size()==1,"Complete strict RGBW group was lost");
        wide.fixture_patches[0].mvr_address=511; wide.fixture_patches[0].addresses[0].address=511;
        const auto incomplete_rgbw=compile_runtime_scene(wide,-1,off);
        check(incomplete_rgbw.color_targets.empty() && controls(incomplete_rgbw,"A")==1,"Incomplete RGBW must be omitted without dropping an independent complete Dimmer");
        wide.fixture_patches[0].dmx_mode="Multi"; wide.fixture_patches[0].mvr_address=512; wide.fixture_patches[0].addresses[0].address=512;
        wide.fixture_patches[0].addresses.push_back({1,4,1,1,true});
        const auto independent_break=compile_runtime_scene(wide,-1,overlap);
        check(controls(independent_break,"A")==1 && independent_break.source_programs.front().sources.front().universe_id==3 && !status(independent_break,"PVZ-AUTO-SPAN-APPLIED"),"Explicit breaks must stay independent and strictly retain their complete controls");
        wide.fixture_patches[0].addresses.pop_back();
        for (const auto &mode:{"Unknown","Shutter","Gobo","Wheel"}) { wide.fixture_patches[0].dmx_mode=mode; const auto guarded=compile_runtime_scene(wide,-1,overlap); check(!status(guarded,"PVZ-AUTO-SPAN-APPLIED"),"Unsupported semantics admitted by automatic policy"); }
        // Potential continuation interests remain identical across policies, enabling held replay without a packet.
        PeravizVisualRuntimeCore before,after; dmx::RealtimeUniverseMailbox mailbox; RealtimeDmxCoordinator coordinator;
        before.install_compiled_scene(compile_runtime_scene(free,-1,off)); coordinator.install_subscription(before,mailbox);
        std::array<uint8_t,512> data{}; data[0]=200; mailbox.publish(1,data.data(),512,0,1); data.fill(0); mailbox.publish(0,data.data(),512,0,2);
        after.install_compiled_scene(compile_runtime_scene(free,-1,overlap));
        check(coordinator.install_subscription(after,mailbox).states_submitted==2,"Policy change lost held continuation input");
        check(!after.consume_latest_visual_frame().descriptors.empty(),"Policy change did not rehydrate native physical output");
        FixtureTypeCache cache; compile_runtime_scene(free,-1,{},&cache); const auto *identity=&cache.begin()->second; compile_runtime_scene(free,-1,off,&cache);
        check(cache.size()==1 && identity==&cache.begin()->second,"Policy-only rebuild reparsed immutable GDTF data");
        std::filesystem::remove_all(root); return true;
    } catch (const std::exception &error) { std::cerr<<"Automatic Auto Span: "<<error.what()<<'\n'; return false; }
}
