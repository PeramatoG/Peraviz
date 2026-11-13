#include "runtime/peraviz_visual_runtime.h"
#include "runtime/realtime_dmx_coordinator.h"
#include "runtime/native_worker_pool.h"
#include "presentation/async_presentation_pipeline.h"
#include <thread>
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "gdtf_runtime/resolved_dmx_addresses.h"
#include "archive/zip_archive.h"
#include "mvr_scene_loader.h"
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
using namespace peraviz;
using namespace peraviz::runtime;
namespace {
constexpr const char *uuid="10000000-0000-0000-0000-000000000001";
using Colors=std::map<int,std::array<float,4>>;

// Fails deterministically with the scenario's actionable assertion.
void require(bool condition,const char *message) { if (!condition) throw std::runtime_error(message); }

// Reads exact archive bytes to prove source fidelity through native compilation and playback.
std::string bytes(const std::filesystem::path &path) {
    std::ifstream file(path,std::ios::binary);
    return {std::istreambuf_iterator<char>(file),std::istreambuf_iterator<char>()};
}

// Creates public synthetic GDTF/MVR ZIPs with sixty Overwrite references and independent RGB emitters.
SceneModel strip_scene(const std::filesystem::path &root,int count=1,bool multibreak=false,const std::string &extra_attribute="") {
    std::string geometry="<Geometry Name=\"Root\">";
    for (int i=0;i<60;++i) geometry+="<GeometryReference Name=\"P"+std::to_string(i)+"\" Geometry=\"Cell\"><Break DMXBreak=\"1\" DMXOffset=\""+std::to_string(1+3*i)+"\"/></GeometryReference>";
    geometry+="</Geometry><Geometry Name=\"Cell\"><Beam Name=\"Pixel\" BeamType=\"Glow\"/></Geometry>";
    std::string channels;
    for (int i=0;i<3;++i) {
        const std::string attribute=std::string("ColorAdd_")+"RGB"[i];
        channels+="<DMXChannel DMXBreak=\"Overwrite\" Offset=\""+std::to_string(i+1)+"\" Geometry=\"Pixel\"><LogicalChannel Attribute=\""+attribute+"\"><ChannelFunction Attribute=\""+attribute+"\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel></DMXChannel>";
    }
    if (multibreak) channels+="<DMXChannel DMXBreak=\"2\" Offset=\"1\" Geometry=\"Root\"><LogicalChannel Attribute=\"Dimmer\"><ChannelFunction Attribute=\"Dimmer\"/></LogicalChannel></DMXChannel>";
    if (!extra_attribute.empty()) channels+="<DMXChannel Offset=\"181\" Geometry=\"Root\"><LogicalChannel Attribute=\""+extra_attribute+"\"><ChannelFunction Attribute=\""+extra_attribute+"\"/></LogicalChannel></DMXChannel>";
    const std::string xml="<GDTF DataVersion=\"1.2\"><FixtureType Name=\"Strip\"><Geometries>"+geometry+"</Geometries><DMXModes><DMXMode Name=\"RGB\" Geometry=\"Root\"><DMXChannels>"+channels+"</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
    { archive::ZipArchive zip; require(zip.open_create_or_modify(root/"strip.gdtf"),"Create GDTF"); require(zip.write_file("description.xml",xml)&&zip.close(),"Write GDTF"); }
    std::string fixtures;
    for (int i=0;i<count;++i) fixtures+="<Fixture uuid=\"10000000-0000-0000-0000-00000000000"+std::to_string(i+1)+"\"><GDTFSpec>strip.gdtf</GDTFSpec><GDTFMode>RGB</GDTFMode><Addresses><Address>1.1</Address>"+(multibreak?std::string("<Address break=\"1\">4.1</Address>"):std::string())+"</Addresses></Fixture>";
    { archive::ZipArchive zip; require(zip.open_create_or_modify(root/"strip.mvr"),"Create MVR"); require(zip.write_file("GeneralSceneDescription.xml","<GeneralSceneDescription verMajor=\"1\" verMinor=\"6\"><Scene><Layers><Layer uuid=\"layer\"><ChildList>"+fixtures+"</ChildList></Layer></Layers></Scene></GeneralSceneDescription>")&&zip.write_file("strip.gdtf",bytes(root/"strip.gdtf"))&&zip.close(),"Write MVR"); }
    return load_mvr((root/"strip.mvr").string());
}

// Changes only the in-memory test's standard MVR patch before compiling a runtime override.
void patch_at(SceneModel &model,int universe,int channel) {
    for (auto &patch:model.fixture_patches) {
        patch.mvr_universe=universe; patch.mvr_address=channel;
        patch.addresses[0].universe=universe; patch.addresses[0].address=channel;
    }
}

// Extracts renderer-ready Color rows and rejects duplicate physical output ownership.
Colors colors(const SectionedVisualFrame &frame) {
    Colors result;
    for (size_t d=0;d<frame.descriptors.size();d+=5) if (frame.descriptors[d]==int(VisualSectionType::EmitterColor)) {
        for (int row=0;row<frame.descriptors[d+1];++row) {
            const int io=frame.descriptors[d+2]+row*3,fo=frame.descriptors[d+3]+row*4;
            require(result.emplace(frame.integers[io+1],std::array<float,4>{frame.floats[fo],frame.floats[fo+1],frame.floats[fo+2],frame.floats[fo+3]}).second,"Duplicate color target in one coordinator cycle");
        }
    }
    return result;
}

// Verifies the first physical pixel's color and implicit intensity gain in a compact native frame.
void expect_color(const Colors &rows,int target,float r,float g,float b,float gain=1) {
    const auto it=rows.find(target); require(it!=rows.end(),"Expected physical pixel update");
    const float expected[]={r,g,b,gain};
    for (int i=0;i<4;++i) require(std::fabs(it->second[i]-expected[i])<0.0001f,"Incorrect latest-held renderer-ready color/gain");
}

// Exercises exact contiguous mapping, physical row composition, ordering, replay and unchanged suppression.
int test_strip(SceneModel &model,int start,int universe_offset,const gdtf_runtime::RuntimeRoutingOptions &options) {
    patch_at(model,1,start);
    auto scene=gdtf_runtime::compile_runtime_scene(model,universe_offset,options);
    require(scene.fixtures.size()==1 && scene.color_targets.size()==60 && scene.source_programs.size()==180,"Expected complete sixty-pixel routing");
    std::set<int> routed;
    for (const auto &program:scene.source_programs) for (const auto &byte:program.sources) routed.insert((byte.universe_id-universe_offset-1)*512+byte.address);
    require(routed.size()==180 && *routed.begin()==start-1 && *routed.rbegin()==start+178,"Continuous 180-byte routing must have no alignment gaps");
    int target=0;
    for (const auto &beam:scene.beam_profiles) if (beam.geometry_path.find("/P0/")!=std::string::npos) target=beam.render_target_id;
    require(target>0,"First reference must retain a canonical physical target");
    PeravizVisualRuntimeCore core; core.install_compiled_scene(scene);
    dmx::RealtimeUniverseMailbox mailbox; RealtimeDmxCoordinator coordinator;
    coordinator.install_subscription(core,mailbox);
    std::set<int> subscribed;
    for (const auto &[universe,slots]:core.realtime_interest_offsets()) for (int slot:slots) subscribed.insert((universe-universe_offset-1)*512+slot);
    require(subscribed==routed,"Receiver subscription must cover every exact physical source byte");
    const int u=1+universe_offset;
    std::array<uint8_t,512> first{},second{}; first[start-1]=255;
    mailbox.publish(u,first.data(),512,0,1);
    if (start+179>512) mailbox.publish(u+1,second.data(),512,0,2);
    coordinator.pump(core,mailbox);
    auto initial=colors(core.consume_latest_visual_frame()); require(initial.size()==60,"All sixty independent emitters must initialize once"); expect_color(initial,target,1,0,0);
    if (start>=511) {
        const int blue=(start+1)%512;
        second[blue]=255; mailbox.publish(u+1,second.data(),512,0,3); coordinator.pump(core,mailbox);
        expect_color(colors(core.consume_latest_visual_frame()),target,1,0,1);
        first[start-1]=0;
        // Reverse arrival order and both dirty inputs before one snapshot must produce only the final color.
        second[blue]=128; mailbox.publish(u+1,second.data(),512,0,4); mailbox.publish(u,first.data(),512,0,5);
        coordinator.pump(core,mailbox);
        const auto blue_rows=colors(core.consume_latest_visual_frame()); require(blue_rows.size()==1,"Two changed universes must yield one physical update"); expect_color(blue_rows,target,0,0,1,128.0f/255);
        require(!mailbox.publish(u+1,second.data(),512,0,6),"Identical packet should be filtered by the mailbox");
        core.submit_universe_frame(u+1,second.data(),512); require(colors(core.consume_latest_visual_frame()).empty(),"Identical packet must not dirty the renderer");
        PeravizVisualRuntimeCore replacement; replacement.install_compiled_scene(scene);
        require(coordinator.install_subscription(replacement,mailbox).states_submitted==2,"Subscription replacement must replay both held universes");
        expect_color(colors(replacement.consume_latest_visual_frame()),target,0,0,1,128.0f/255);
        const auto held=core.held_universes(); core.install_compiled_scene(scene);
        for (auto it=held.rbegin();it!=held.rend();++it) core.submit_universe_frame(it->id,it->values.data(),int(it->values.size()));
        expect_color(colors(core.consume_latest_visual_frame()),target,0,0,1,128.0f/255);
    }
    return target;
}

// Keeps ordered coarse/fine bytes and Dimmer normalization exact when one scalar spans two universes.
void test_split_scalar() {
    CompiledRuntimeScene scene; scene.fixtures.push_back({1,"split","type","mode",0,512});
    scene.source_programs.push_back({1,CompiledSemantic::ColorAddRed,{{0,511,0},{1,0,1}},0,65535,0,1});
    CompiledColorTargetProgram target; target.fixture_id=1; target.color_target_id=2; target.beam_render_target_id=3; target.additive_source=true;
    CompiledColorInputBinding input; input.source_program_id=1; input.semantic=CompiledSemantic::ColorAddRed; target.inputs.push_back(input); scene.color_targets.push_back(target);
    scene.source_programs.push_back({2,CompiledSemantic::Dimmer,{{0,511,0},{1,0,1}},0,65535,0,1});
    scene.properties.push_back({4,1,5,3,CompiledSemantic::Dimmer,{{2,1}}});
    PeravizVisualRuntimeCore core; core.install_compiled_scene(scene);
    std::array<uint8_t,512> first{},second{}; first[511]=0x12; second[0]=0x34;
    core.submit_universe_frame(1,second.data(),512); core.submit_universe_frame(0,first.data(),512);
    const auto frame=core.consume_latest_visual_frame(); expect_color(colors(frame),3,1,0,0,4660.0f/65535);
    bool intensity=false;
    for (size_t d=0;d<frame.descriptors.size();d+=5) if (frame.descriptors[d]==int(VisualSectionType::EmitterIntensity)) {
        intensity=true; require(std::fabs(frame.floats[frame.descriptors[d+3]]-4660.0f/65535)<0.0001f,"Coarse/fine Dimmer byte order changed");
    }
    require(intensity,"Split scalar must reach native intensity output");
    second[0]=0x56; core.submit_universe_frame(1,second.data(),512);
    expect_color(colors(core.consume_latest_visual_frame()),3,1,0,0,4694.0f/65535);
}

// Compares real forced native worker decoding and color cooking with the serial held-state authority.
void test_span_workers() {
    CompiledRuntimeScene scene; scene.fixtures.push_back({1,"workers","type","mode",0,512});
    const CompiledSemantic semantics[]={CompiledSemantic::ColorAddRed,CompiledSemantic::ColorAddGreen,CompiledSemantic::ColorAddBlue};
    for (int pixel=0;pixel<1200;++pixel) {
        CompiledColorTargetProgram target; target.fixture_id=1; target.color_target_id=10000+pixel; target.beam_render_target_id=20000+pixel; target.additive_source=true;
        for (int color=0;color<3;++color) {
            const int id=pixel*3+color+1;
            const std::vector<CompiledDmxByteSource> source=color==0?std::vector<CompiledDmxByteSource>{{0,511,0},{1,0,1}}:std::vector<CompiledDmxByteSource>{{color==1?0:1,color==1?510:1,0}};
            scene.source_programs.push_back({id,semantics[color],source,0,color==0?65535U:255U,0,1});
            CompiledColorInputBinding input; input.source_program_id=id; input.semantic=semantics[color]; target.inputs.push_back(input);
        }
        scene.color_targets.push_back(target);
    }
    NativeWorkerPool pool(2,true);
    PeravizVisualRuntimeCore serial,parallel; serial.install_compiled_scene(scene); parallel.install_compiled_scene(scene);
    require(parallel.async_eligible_workload(),"Cross-universe input must retain async eligibility");
    parallel.set_native_executor(&pool);
    std::array<uint8_t,512> first{},second{}; first[511]=0x12; second[0]=0x34;
    for (auto *core:{&serial,&parallel}) { core->submit_universe_frame(1,second.data(),512); core->submit_universe_frame(0,first.data(),512); }
    require(colors(serial.consume_latest_visual_frame())==colors(parallel.consume_latest_visual_frame()),"Forced worker cross-universe composition differs from serial");
    require(parallel.parallel_metrics().parallel_batches>0,"Test must execute real native parallel ranges");
    second[1]=255;
    for (auto *core:{&serial,&parallel}) core->submit_universe_frame(1,second.data(),512);
    const auto expected=colors(serial.consume_latest_visual_frame()),actual=colors(parallel.consume_latest_visual_frame());
    require(expected.size()==1200 && actual==expected,"Next-universe-only worker update lost held coarse/color inputs");
    parallel.set_native_executor(nullptr);
    using namespace peraviz::presentation;
    auto async_core=std::make_shared<PeravizVisualRuntimeCore>();
    for (auto &target:scene.color_targets) target.implicit_intensity=true;
    async_core->install_compiled_scene(scene);
    DensePresentationState physical; RenderGroupProjection projection;
    std::vector<OutputBinding> outputs; std::vector<TargetBinding> routes; std::vector<uint32_t> membership;
    for (int pixel=0;pixel<1200;++pixel) {
        outputs.push_back({20000+pixel,1}); membership.push_back(pixel);
        routes.push_back({2,20000+pixel,uint32_t(pixel)}); routes.push_back({3,20000+pixel,uint32_t(pixel)});
    }
    require(physical.install(outputs,routes) && projection.install(membership,std::vector<RenderPresentationClass>(1200,RenderPresentationClass::Individual)),"Async physical output installation");
    first.fill(0); second.fill(0); second[1]=255;
    async_core->submit_universe_frame(1,second.data(),512); async_core->submit_universe_frame(0,first.data(),512);
    AsyncEvaluationOptions execution; execution.workers=2; execution.force=true;
    AsyncPresentationPipeline session(async_core,std::move(physical),std::move(projection),execution);
    for (int step=0;step<3;++step) {
        if (step==1) { second[1]=128; session.submit(1,second.data(),512); session.flush_input(); }
        if (step==2) { first[511]=255; second.fill(0); session.submit(1,second.data(),512); session.submit(0,first.data(),512); session.flush_input(); }
        const CompletedPresentationSnapshot *snapshot=nullptr;
        const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
        while (std::chrono::steady_clock::now()<deadline && !(snapshot=session.try_acquire())) std::this_thread::sleep_for(std::chrono::microseconds(50));
        require(snapshot && !session.failed() && snapshot->physical_rows.size()==1200,"Async boundary update must publish each physical emitter once");
        std::set<uint32_t> indices;
        for (const auto &row:snapshot->physical_rows) {
            require(indices.insert(row.index).second,"Duplicate async physical emitter");
            const float gain=step==0?1.0f:step==1?128.0f/255:65280.0f/65535;
            require(std::fabs(row.values[MaterialEnergy]-4*gain)<0.0001f && row.values[step==2?Red:Blue]>0.999f && row.values[step==2?Blue:Red]<0.0001f,"Async final material/color must compose all held physical universes");
        }
        session.release(snapshot);
    }
    session.stop();
}

}

// Covers production ZIP import, opt-in admission, strict compatibility and native visual outputs.
bool test_auto_span() {
    const auto root=std::filesystem::current_path()/"auto_span_fixture";
    std::filesystem::create_directories(root);
    try {
        auto model=strip_scene(root);
        require(model.fixture_patches.size()==1,"Synthetic MVR fixture must load");
        const auto gdtf_before=bytes(root/"strip.gdtf"),mvr_before=bytes(root/"strip.mvr");
        gdtf_runtime::RuntimeRoutingOptions options; options.auto_span_fixture_uuids.insert(uuid);
        int canonical=0;
        for (int offset:{-1,0}) for (int start:{1,400,511,512}) {
            const int target=test_strip(model,start,offset,options);
            if (canonical) require(target==canonical,"Patch policy must preserve canonical physical target IDs");
            canonical=target;
        }
        require(test_strip(model,1,-1,{})==canonical,"Strict rendering must retain the same canonical target");
        patch_at(model,1,1); const auto normal=gdtf_runtime::compile_runtime_scene(model,-1); require(normal.color_targets.size()==60,"Strict single-universe fixture regressed");
        patch_at(model,1,511); gdtf_runtime::RuntimeRoutingOptions off; off.policy=gdtf_runtime::AutoSpanPolicy::Off;
        const auto strict=gdtf_runtime::compile_runtime_scene(model,-1,off);
        require(strict.fixtures.size()==1 && strict.color_targets.empty() && std::all_of(strict.source_programs.begin(),strict.source_programs.end(),[](const auto &source){return source.sources.front().universe_id==0;}) && !strict.diagnostics.empty(),"Off must omit incomplete RGB groups without decoding missing bytes");
        patch_at(model,32768,400); const auto overflow=gdtf_runtime::compile_runtime_scene(model,-1,options);
        require(overflow.fixtures.empty() && !overflow.diagnostics.empty() && overflow.diagnostics.back().message.find("Port-Address")!=std::string::npos,"Port-Address overflow must reject the complete fixture explicitly");
        patch_at(model,32768,1); require(gdtf_runtime::compile_runtime_scene(model,-1,options).fixtures.size()==1,"Highest valid Port-Address must remain usable");
        patch_at(model,32767,400); require(gdtf_runtime::compile_runtime_scene(model,-1,options).fixtures.size()==1,"Spanning into the highest valid Port-Address must work");
        patch_at(model,1,511); const auto before_patch=model.fixture_patches[0]; gdtf_runtime::compile_runtime_scene(model,-1,options);
        require(model.fixture_patches[0].addresses[0].universe==before_patch.addresses[0].universe && model.fixture_patches[0].addresses[0].address==before_patch.addresses[0].address,"Runtime override must not mutate canonical patch records");
        require(bytes(root/"strip.gdtf")==gdtf_before && bytes(root/"strip.mvr")==mvr_before,"Source archives must remain byte-for-byte unchanged");
        auto copatched=strip_scene(root,2); patch_at(copatched,1,511);
        options.auto_span_fixture_uuids.insert("10000000-0000-0000-0000-000000000002");
        const auto shared=gdtf_runtime::compile_runtime_scene(copatched,-1,options); require(shared.color_targets.size()==120,"Co-patched fixtures must preserve independent emitters");
        PeravizVisualRuntimeCore core; core.install_compiled_scene(shared); std::array<uint8_t,512> data{}; data[510]=255;
        core.submit_universe_frame(0,data.data(),512); data.fill(0); core.submit_universe_frame(1,data.data(),512);
        require(colors(core.consume_latest_visual_frame()).size()==120,"Shared physical ranges must not merge output ownership");
        auto multibreak=strip_scene(root,1,true);
        const auto independent=gdtf_runtime::compile_runtime_scene(multibreak,-1); require(independent.fixtures.size()==1,"Strict explicit multibreak behavior regressed");
        const auto unsupported=gdtf_runtime::compile_runtime_scene(multibreak,-1,options);
        require(unsupported.fixtures.empty() && unsupported.diagnostics.back().message.find("effective GDTF break")!=std::string::npos,"Auto Span must not reinterpret independent breaks");
        auto temporal=strip_scene(root,1,false,"Shutter1");
        const auto rejected_temporal=gdtf_runtime::compile_runtime_scene(temporal,-1,options);
        require(rejected_temporal.fixtures.empty() && rejected_temporal.diagnostics.back().message.find("disable Auto Span")!=std::string::npos,"Unsupported Auto Span semantics need an actionable diagnostic");
        test_split_scalar();
        test_span_workers();
        std::filesystem::remove_all(root);
        std::cout<<"Auto Span native integration passed\n"; return true;
    } catch (const std::exception &error) { std::cerr<<"Auto Span: "<<error.what()<<'\n'; return false; }
}
