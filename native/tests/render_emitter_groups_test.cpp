#include "presentation/render_group_projection.h"
#include "presentation/wheel_presentation_eligibility.h"
#include <cstdlib>
#include <cmath>
#include <iostream>
#include <new>
#include <set>

using namespace peraviz;
using namespace peraviz::runtime;
using namespace peraviz::presentation;
static size_t allocations=0;
// Counts allocations to guard the warmed incremental projection path.
void *operator new(std::size_t n) { ++allocations; if (void *p=std::malloc(n?n:1)) return p; throw std::bad_alloc(); }
// Releases allocation-probe memory.
void operator delete(void *p) noexcept { std::free(p); }
// Supports C++17 sized deallocation.
void operator delete(void *p,std::size_t) noexcept { std::free(p); }
// Fails deterministically in Debug and Release.
static void check(bool ok,const char *message) { if (!ok) { std::cerr<<message<<'\n'; std::exit(1); } }
struct Rig { CompiledRuntimeScene scene; SceneModel model; };
// Creates physical sources with canonical transforms, reliable radii and selected-mode control topology.
static Rig make_rig(int fixtures=1,int count=50) {
    Rig rig;
    for (int f=0;f<fixtures;++f) {
        const std::string uuid="instance-"+std::to_string(f);
        SceneNode root; root.node_id=uuid+"/root"; root.gdtf_geometry_key=uuid+"/Root"; root.gdtf_geometry_path="Root";
        rig.model.nodes.push_back(root);
        CompiledDmxSourceProgram source; source.program_id=f*100+1; source.sources={{0,f*2,0}}; source.semantic=CompiledSemantic::Dimmer;
        rig.scene.source_programs.push_back(source);
        CompiledComponentProperty dimmer; dimmer.fixture_id=f+1; dimmer.property_id=5000+f; dimmer.render_target_id=5000+f;
        dimmer.semantic=CompiledSemantic::Dimmer; dimmer.geometry_name="Root"; dimmer.contributors.push_back({source.program_id,1});
        rig.scene.properties.push_back(dimmer);
        source.program_id+=1; source.semantic=CompiledSemantic::ColorAddRed; source.sources[0].address+=1;
        rig.scene.source_programs.push_back(source);
        for (int i=0;i<count;++i) {
            SceneNode node; node.node_id=uuid+"/physical-"+std::to_string(i); node.parent_id=root.node_id;
            node.gdtf_geometry_path="Root/Emitter"+std::to_string(i); node.gdtf_geometry_key=uuid+"/"+node.gdtf_geometry_path;
            node.is_beam=true; node.has_beam_radius=true; node.beam_radius=0.01f;
            node.local_transform.position={float(i%10)*0.018f,0,float(i/10)*0.018f};
            rig.model.nodes.push_back(node);
            CompiledBeamOpticalProfile p; p.fixture_id=f+1; p.fixture_uuid=uuid; p.render_target_id=f*1000+i+1;
            p.geometry_key=node.gdtf_geometry_key; p.geometry_path=node.gdtf_geometry_path;
            p.beam_radius_m=0.01; p.beam_radius_source="explicit"; p.luminous_flux=p.effective_luminous_flux_lm=320;
            p.projected_lumen_scale=p.emission_lumen_scale=0.032;
            rig.scene.beam_profiles.push_back(p);
            CompiledColorTargetProgram color; color.fixture_id=f+1; color.beam_render_target_id=p.render_target_id;
            color.color_target_id=10000+p.render_target_id; color.inputs.push_back({source.program_id,source.semantic});
            rig.scene.color_targets.push_back(color);
        }
    }
    return rig;
}
// Compiles renderer groups with exact inverse control membership.
static std::vector<RenderEmitterGroup> groups(const Rig &rig) { return compile_render_emitter_groups(rig.scene,rig.model,compile_control_groups(rig.scene)); }
// Adds canonical seated Color-wheel bindings without fixture/model-name exceptions.
static void add_color_wheel(Rig &rig) {
    CompiledDmxSourceProgram source; source.program_id=777; source.sources={{0,7,0}}; source.attribute_name="Color1";
    rig.scene.source_programs.push_back(source);
    CompiledWheelPalette palette; palette.fixture_id=1; palette.wheel_renderer_id=888;
    CompiledWheelPaletteSlot open; open.slot_index=1; open.uniform_color_presentation=true;
    auto red=open; red.slot_index=2; red.linear_green=red.linear_blue=red.srgb_green=red.srgb_blue=0; red.gain=0.5f;
    palette.slots={open,red}; rig.scene.wheel_palettes.push_back(palette);
    for (const auto &beam:rig.scene.beam_profiles) {
        CompiledWheelTargetBinding binding; binding.fixture_id=beam.fixture_id; binding.binding_id=10000+beam.render_target_id;
        binding.beam_render_target_id=beam.render_target_id; binding.source_program_id=777; binding.wheel_renderer_id=888;
        binding.channel_sets={{0,127,1},{128,255,2}};
        rig.scene.wheel_bindings.push_back(binding);
    }
}
// Separates proven shared wheel authority from optical aggregation of independent colors.
static void test_color_wheel_eligibility() {
    auto rig=make_rig(); add_color_wheel(rig);
    check(compile_control_groups(rig.scene).size()==1 && groups(rig).size()==1,"Proven seated uniform Color wheels allow shared controls and one optical aggregate");
    auto independent=rig;
    auto source=rig.scene.source_programs.back(); source.program_id=778; source.sources[0].address=8;
    independent.scene.source_programs.push_back(source); independent.scene.wheel_bindings[0].source_program_id=778;
    check(compile_control_groups(independent.scene).size()==2 && groups(independent).size()==1,"Different wheel authorities split controls while compatible optics still aggregate");
    for (auto mode:{CompiledWheelMode::Index,CompiledWheelMode::Spin,CompiledWheelMode::Random,CompiledWheelMode::AudioUnsupported,CompiledWheelMode::OtherUnsupported}) {
        auto unsupported=rig; for (auto &binding:unsupported.scene.wheel_bindings) binding.mode=mode;
        check(groups(unsupported).size()==1 && groups(unsupported)[0].approximate_color_members==50,"Uniform resolved indexed/temporal approximations aggregate without claiming missing effect fidelity");
    }
    auto effects=make_rig();
    CompiledDmxSourceProgram fx; fx.program_id=778; fx.sources={{0,8,0}};
    effects.scene.source_programs.push_back(fx); fx.program_id=779; fx.sources[0].address=9; effects.scene.source_programs.push_back(fx);
    for (auto &beam:effects.scene.beam_profiles) {
        beam.color_presentation_status=ColorPresentationStatus::UnsupportedEffectApproximation;
        beam.approximated_color_source_programs={778};
    }
    effects.scene.beam_profiles[0].approximated_color_source_programs={779};
    check(compile_control_groups(effects.scene).size()==2 && groups(effects).size()==1 && groups(effects)[0].approximate_color_members==50,
        "Independent unsupported FX sources retain exact control authority while sharing resolved optical approximation");
    auto mixed=rig; auto extra=rig.scene.wheel_bindings[0]; extra.binding_id=99999; extra.mode=CompiledWheelMode::Index; mixed.scene.wheel_bindings.push_back(extra);
    check(groups(mixed).size()==2,"Overlapping ambiguous wheel control stays conservative regardless of the current mode");
    auto media=rig; media.scene.wheel_palettes[0].slots[1].media_file_name="pattern";
    check(groups(media).size()==50,"Patterned slots stay individual even if their current aggregate RGB matches");
    auto unknown=rig; unknown.scene.wheel_palettes[0].slots[0].uniform_color_presentation=false;
    check(groups(unknown).size()==50,"Absent setup proof stays conservative, including decoded semantic-only palettes");
    auto ownership=rig; ownership.scene.wheel_bindings[0].beam_render_target_id=0;
    check(groups(ownership).size()==50,"Unknown wheel output ownership vetoes the fixture conservatively");
    ownership=rig; ownership.scene.wheel_bindings[0].fixture_id=0;
    check(groups(ownership).size()==2,"Unknown fixture ownership vetoes its known output");
    auto missing=rig; missing.scene.wheel_bindings[0].source_program_id=999;
    check(groups(missing).size()==2,"Missing source authority remains individual");
    missing=rig; missing.scene.wheel_palettes.clear(); check(groups(missing).size()==50,"Missing wheel palettes remain individual");
    auto overlap=rig; extra=rig.scene.wheel_bindings[0]; extra.binding_id=99999; overlap.scene.wheel_bindings.push_back(extra);
    check(groups(overlap).size()==2,"Overlapping wheel functions retain conservative fallback");
    auto zoom=rig; CompiledComponentProperty property; property.fixture_id=1; property.property_id=9090; property.semantic=CompiledSemantic::Zoom;
    property.geometry_name=rig.scene.beam_profiles[0].geometry_path; property.contributors.push_back({777,1}); zoom.scene.properties.push_back(property);
    check(groups(zoom).size()==2,"A uniform Color wheel never overrides independent Zoom authority");
    auto gobo=rig; CompiledGoboMotionBinding motion; motion.fixture_id=1; motion.beam_render_target_id=1; gobo.scene.gobo_motion_bindings.push_back(motion);
    check(groups(gobo).size()==2,"Color-only wheel eligibility never bypasses gobo motion ownership");
}
// Exercises geometry counterexamples, mixed pixel radiometry, compact rows and allocation-free scaling.
int main() {
    test_color_wheel_eligibility();
    auto rig=make_rig();
    auto render=groups(rig);
    check(render.size()==1 && render[0].presentation==RenderPresentationClass::Aggregated && render[0].physical_ids.size()==50,"Compact common-aperture sources classify as one aggregate");
    check(render[0].control_group_ids.size()==1 && render[0].nominal_flux==16000 && render[0].beam_angle==25,"Inverse controls, summed flux and unchanged optical angles remain exact");
    const auto fixed_origin=render[0].origin;
    auto aura=rig.scene.beam_profiles[0]; aura.render_target_id=999; aura.beam_type="None"; aura.has_projected_beam=false; aura.projected_lumen_scale=0;
    rig.scene.beam_profiles.push_back(aura);
    render=groups(rig);
    check(render.size()==2 && render[1].presentation==RenderPresentationClass::Individual && render[1].physical_ids[0]==999,"Aura remains independent and emission-only");
    auto separated=make_rig(1,2); separated.model.nodes[1].local_transform.position.x=-1; separated.model.nodes[2].local_transform.position.x=1;
    check(compile_control_groups(separated.scene).size()==1 && groups(separated).size()==2,"Shared controls do not collapse a separated two-cell source");
    auto bar=make_rig();
    for (size_t i=1;i<bar.model.nodes.size();++i) bar.model.nodes[i].local_transform.position={float(i)*0.2f,0,0};
    check(groups(bar).size()==50,"Long linear sources remain individual");
    auto divergent=make_rig();
    for (size_t i=1;i<divergent.model.nodes.size();++i) {
        const float a=float(i)*4.0f*3.14159265f/180;
        auto &t=divergent.model.nodes[i].local_transform; t.has_basis=true;
        t.basis_x={std::cos(a),std::sin(a),0}; t.basis_y={-std::sin(a),std::cos(a),0};
    }
    check(groups(divergent).size()==50,"Different optical directions never aggregate together");
    auto axes=make_rig();
    for (size_t i=1;i<=50;++i) {
        SceneNode axis; axis.node_id="axis-"+std::to_string(i); axis.parent_id=axes.model.nodes[0].node_id;
        axis.gdtf_geometry_path="Root/Axis"+std::to_string(i); axis.gdtf_geometry_key="instance-0/"+axis.gdtf_geometry_path; axis.is_axis=true;
        axes.model.nodes[i].parent_id=axis.node_id; axes.model.nodes[i].gdtf_geometry_path=axis.gdtf_geometry_path+"/Emitter";
        axes.scene.beam_profiles[i-1].geometry_path=axes.model.nodes[i].gdtf_geometry_path;
        axes.model.nodes.push_back(axis);
    }
    check(groups(axes).size()==50,"Different mechanical Axis lineages remain independent");
    auto optics=make_rig(); optics.scene.beam_profiles[0].beam_angle_deg=40;
    check(groups(optics).size()==2,"Incompatible optical angles stay in separate renderer sources");
    auto uncertain=make_rig(); uncertain.scene.beam_profiles[0].beam_radius_source="fallback";
    const auto uncertain_groups=groups(uncertain);
    check(uncertain_groups.size()==2 && uncertain_groups[0].rejection_reason=="beam_radius_provenance","An unproven aperture is reported without disabling reliable peers");
    check(groups(bar)[0].rejection_reason=="packing_density","Separated apertures report the native compactness rejection");
    auto projector=make_rig(); CompiledGoboSelectionBinding gobo; gobo.fixture_id=1; gobo.beam_render_target_id=1;
    projector.scene.gobo_bindings.push_back(gobo);
    check(compile_control_groups(projector.scene).size()==2 && groups(projector).size()==2,"Exact gobo ownership vetoes only the affected output");
    projector.scene.gobo_bindings[0].beam_render_target_id=9999;
    check(compile_control_groups(projector.scene).size()==1 && groups(projector).size()==1,"An unrelated known gobo route does not veto a whole fixture");
    projector.scene.gobo_bindings.clear(); CompiledWheelTargetBinding wheel; wheel.fixture_id=1; wheel.beam_render_target_id=1;
    projector.scene.wheel_bindings.push_back(wheel);
    check(compile_control_groups(projector.scene).size()==2,"Relevant wheel splits are exact-output scoped");
    projector.scene.wheel_bindings[0].beam_render_target_id=0;
    check(compile_control_groups(projector.scene).size()==50 && groups(projector).size()==50,"Ambiguous wheel ownership remains conservative");
    auto pixels=make_rig();
    for (int i=0;i<50;++i) {
        auto program=pixels.scene.source_programs.back(); program.program_id=200+i; program.sources[0].address=i+10;
        pixels.scene.source_programs.push_back(program); pixels.scene.color_targets[i].inputs[0].source_program_id=program.program_id;
    }
    check(compile_control_groups(pixels.scene).size()==50 && groups(pixels).size()==1,"Independent pixels may share proven compact optical presentation, while controls remain independent");
    DensePresentationState physical;
    std::vector<OutputBinding> bindings; std::vector<TargetBinding> routes;
    for (int i=0;i<50;++i) { bindings.push_back({i+1,0.032f}); routes.push_back({2,5000,uint32_t(i)}); routes.push_back({3,10001+i,uint32_t(i)}); }
    check(physical.install(bindings,routes),"Exact native physical state installs");
    RenderGroupProjection projection;
    check(projection.install(std::vector<uint32_t>(50,0),{RenderPresentationClass::Aggregated}),"One renderer row installs for 50 physical outputs");
    const auto gen=physical.generation(); const float dim[]={0.5f,20,10,10,2}; const float red[]={1,0,0,1}; const float blue[]={0,0,1,1};
    physical.update_target(gen,2,5000,2,dim);
    for (int i=0;i<50;++i) physical.update_target(gen,3,10001+i,4,i<25?red:blue);
    projection.prepare(physical);
    check(physical.bindings().size()==50 && projection.prepared().size()==1,"Physical state remains exact while one renderer row crosses the boundary");
    const auto mixed=projection.prepared()[0].values;
    check(std::abs(mixed[Red]-0.735357f)<0.0001f && std::abs(mixed[Blue]-0.735357f)<0.0001f && std::abs(mixed[BeamIntensity]-16.0f)<0.0001f,"Equal red/blue flux mixes in linear light, with bounded summed physical intensity");
    check(physical.render_values(0)[Red]==1 && physical.render_values(49)[Blue]==1,"Mixing never replaces exact physical pixel colors");
    physical.finish_snapshot(gen);
    const float one_dark[]={0,0,0,0,0};
    physical.update(gen,0,2,2,one_dark); projection.prepare(physical);
    check(physical.dirty_indices().size()==1 && projection.prepared().size()==1 && projection.prepared()[0].values[BeamIntensity]>15.0f,
        "One changed dark member updates one accumulator without erasing active members");
    physical.finish_snapshot(gen);
    const float dark[]={0,0,0,0,0}; const float green[]={0,1,0,0.5};
    physical.update_target(gen,2,5000,2,dark); projection.prepare(physical); physical.finish_snapshot(gen);
    for (int i=0;i<50;++i) physical.update_target(gen,3,10001+i,4,green);
    projection.prepare(physical); physical.finish_snapshot(gen);
    physical.update_target(gen,2,5000,2,dim); projection.prepare(physical);
    check(projection.prepared().size()==1 && projection.prepared()[0].values[Green]>0.999f && projection.prepared()[0].values[Red]<0.001f,"Reactivation restores latest held pixel colors and gain without fresh Color input");
    check(groups(make_rig())[0].origin==fixed_origin,"The nominal centroid is static, independent of dynamic pixels");
    physical.finish_snapshot(gen); const auto old_generation=gen;
    projection.clear(); physical.clear();
    check(projection.row_count()==0 && !physical.update(old_generation,0,2,2,dim),"Scene reload retires accumulators, membership and old physical generation");
    auto load=make_rig(20);
    auto load_groups=groups(load);
    check(load.scene.beam_profiles.size()==1000 && load_groups.size()==20,"Twenty compact sources retain 1000 physical outputs and exactly 20 renderer shafts");
    bindings.clear(); routes.clear(); std::vector<uint32_t> mapping;
    for (uint32_t i=0;i<1000;++i) { bindings.push_back({int32_t(i+1),0.032f}); routes.push_back({2,int32_t(5000+i/50),i}); routes.push_back({3,int32_t(10000+i),i}); mapping.push_back(i/50); }
    check(physical.install(bindings,routes) && projection.install(mapping,std::vector<RenderPresentationClass>(20,RenderPresentationClass::Aggregated)),"Load projection installs");
    for (int f=0;f<20;++f) physical.update_target(physical.generation(),2,5000+f,2,dim);
    projection.prepare(physical); physical.finish_snapshot(physical.generation());
    const auto before=allocations, bytes=projection.buffer_bytes();
    for (int tick=0;tick<100;++tick) {
        const float rgb[]={float(tick%10)/10,0.5f,0.1f,1};
        for (uint32_t i=0;i<1000;++i) physical.update_target(physical.generation(),3,10000+int32_t(i),4,rgb);
        projection.prepare(physical);
        check(projection.prepared().size()==20,"A 1000-member Color tick emits 20 dirty renderer rows");
        physical.finish_snapshot(physical.generation());
    }
    check(allocations==before && projection.buffer_bytes()==bytes,"Warmed incremental accumulation has no allocations or capacity growth");
    std::cout<<"Render emitter groups: geometry counterexamples, exact pixels, linear mixing, held state and 1000 -> 20 rows passed\n";
}
