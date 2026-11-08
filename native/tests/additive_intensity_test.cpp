#include "presentation/direct_presentation_pipeline.h"
#include "runtime/additive_intensity_authority.h"
#include "runtime/compiled_runtime_scene_codec.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "archive/zip_archive.h"
#include "scene_model.h"
#include <filesystem>
#include <array>
#include <cmath>
#include <iostream>

namespace {
using namespace peraviz::runtime;
using namespace peraviz::presentation;
// Exercises emitter-local authority through the native evaluator and final material-value boundary.
bool check_authority(bool explicit_dimmer, bool parent_dimmer, bool rgbw, bool subtractive = false) {
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1,"strip","synthetic","RGB",0,1});
    for (int pixel=0;pixel<2;++pixel) {
        CompiledColorTargetProgram color;
        color.color_target_id=100+pixel; color.fixture_id=1; color.beam_render_target_id=100+pixel;
        color.geometry_name="Root/Pixel"+std::to_string(pixel)+"/Lens"; color.additive_source=!subtractive;
        for (int c=0;c<(rgbw?4:3);++c) {
            const auto semantic=subtractive?CompiledSemantic::ColorSubCyan:
                std::array<CompiledSemantic,4>{CompiledSemantic::ColorAddRed,CompiledSemantic::ColorAddGreen,CompiledSemantic::ColorAddBlue,CompiledSemantic::ColorAddWhite}[c];
            int id=pixel*4+c+1;
            scene.source_programs.push_back({id,semantic,{{0,pixel*4+c,0}},0,255,0,1});
            color.inputs.push_back({id,semantic,0,true});
        }
        scene.color_targets.push_back(color);
    }
    // Pixel 1 always has its own independent dimmer. It must never suppress Pixel 0.
    for (int pixel=0;pixel<2;++pixel) {
        if (!pixel && !explicit_dimmer) continue;
        scene.source_programs.push_back({20+pixel,CompiledSemantic::Dimmer,{{0,10+pixel,0}},0,255,0,1});
        CompiledComponentProperty property{20+pixel,1,200+pixel,200+pixel,CompiledSemantic::Dimmer,{{20+pixel,1}}};
        property.geometry_name="Root/Pixel"+std::to_string(pixel)+(parent_dimmer?"":"/Lens");
        scene.properties.push_back(property);
    }
    PeravizVisualRuntimeCore runtime;
    classify_additive_intensity(scene);
    const auto encoded=encode_compiled_runtime_scene(scene);
    const auto decoded=decode_compiled_runtime_scene(encoded.integers,encoded.floats);
    if (!decoded.valid || decoded.scene.color_targets[0].implicit_intensity != (!explicit_dimmer && !subtractive) ||
            decoded.scene.color_targets[1].implicit_intensity) return false;
    // Old setup payloads cannot prove hierarchy ownership and remain conservatively unlit.
    auto legacy=scene; legacy.contract_version=9;
    const auto legacy_encoded=encode_compiled_runtime_scene(legacy);
    const auto legacy_decoded=decode_compiled_runtime_scene(legacy_encoded.integers,legacy_encoded.floats);
    if (!legacy_decoded.valid || legacy_decoded.scene.color_targets[0].implicit_intensity) return false;
    runtime.install_compiled_scene(decoded.scene);
    DensePresentationState physical;
    std::vector<TargetBinding> routes{{2,100,0},{3,100,0},{2,101,1},{3,101,1},{2,201,1}};
    if (explicit_dimmer) routes.push_back({2,200,0});
    if (!physical.install({{100,1},{101,1}},routes)) return false;
    RenderGroupProjection projection; projection.install({0,1},{RenderPresentationClass::Individual,RenderPresentationClass::Individual});
    DirectPresentationPipeline pipeline;
    std::array<uint8_t,512> dmx{};
    for (int step=0;step<9;++step) {
        dmx.fill(0);
        if (step>=1 && step<=3) dmx[step-1]=255;
        if (step>=4) for (int c=0;c<3;++c) dmx[c]=255;
        if (rgbw && step==4) { dmx[0]=dmx[1]=dmx[2]=0; dmx[3]=255; }
        if (step==5) dmx[10]=255;
        if (step==6) dmx[10]=128;
        if (step==7) dmx.fill(0);
        if (step==8) { dmx.fill(0); dmx[0]=128; dmx[10]=255; }
        dmx[4]=255; // Keep the independent emitter red even while its own Dimmer is closed.
        if (step==8) dmx[11]=128;
        runtime.submit_universe_frame(0,dmx.data(),dmx.size());
        if (!pipeline.consume(runtime,physical,projection,physical.generation(),runtime.schema().schema_generation,true)) return false;
        auto v=physical.render_values(0);
        const float expected=subtractive?0:((step==0 || step==7)?0:(explicit_dimmer?4.0f*dmx[10]/255:4.0f));
        const float composed_expected = step==8 ? expected*128.0f/255.0f : expected;
        if (std::abs(v[MaterialEnergy]-composed_expected)>0.0001f || std::abs(physical.render_values(1)[MaterialEnergy]-(step==8?4.0f*128.0f/255.0f:0.0f))>0.0001f) {
            std::cerr << "Additive authority failed step=" << step << " explicit=" << explicit_dimmer << " parent=" << parent_dimmer << " energy=" << v[MaterialEnergy] << " expected=" << expected << '\n'; return false;
        }
        if (expected>0 && step>=1 && step<=3 && v[Red+step-1]<=0) return false;
        physical.finish_snapshot(physical.generation());
        runtime.submit_universe_frame(0,dmx.data(),dmx.size());
        pipeline.consume(runtime,physical,projection,physical.generation(),runtime.schema().schema_generation,true);
        if (!physical.dirty_indices().empty() || !projection.prepared().empty()) return false;
        physical.invalidate_renderer(); projection.invalidate();
        pipeline.consume(runtime,physical,projection,physical.generation(),runtime.schema().schema_generation,true);
        if (physical.render_values(0)!=v) return false;
        physical.finish_snapshot(physical.generation());
    }
    runtime.clear();
    runtime.install_compiled_scene(decoded.scene);
    if (!physical.install({{100,1},{101,1}},routes) ||
            !projection.install({0,1},{RenderPresentationClass::Individual,RenderPresentationClass::Individual})) return false;
    runtime.submit_universe_frame(0,dmx.data(),dmx.size());
    if (!pipeline.consume(runtime,physical,projection,physical.generation(),runtime.schema().schema_generation,true)) return false;
    return std::abs(physical.render_values(0)[MaterialEnergy]-(subtractive?0.0f:4.0f*128.0f/255.0f))<0.0001f;
}
}
// Verifies diagnostics remain fixture-local after a supported color-only fixture was compiled.
bool test_control_diagnostics() {
    const auto path = std::filesystem::temp_directory_path() / "peraviz_additive_diagnostics.gdtf";
    peraviz::archive::ZipArchive archive;
    const std::string xml = R"(<GDTF><FixtureType Name="Diagnostics"><Geometries><Geometry Name="Root"><Beam Name="Lens" BeamType="Glow"/></Geometry></Geometries><DMXModes><DMXMode Name="Color" Geometry="Root"><DMXChannels><DMXChannel Offset="1" Geometry="Lens"><LogicalChannel Attribute="ColorAdd_R"><ChannelFunction Attribute="ColorAdd_R" DMXFrom="0" PhysicalFrom="0" PhysicalTo="1"/></LogicalChannel></DMXChannel></DMXChannels></DMXMode><DMXMode Name="Unsupported" Geometry="Root"><DMXChannels><DMXChannel Offset="1" Geometry="Lens"><LogicalChannel Attribute="Fog1"><ChannelFunction Attribute="Fog1" DMXFrom="0"/></LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>)";
    if (!archive.open_create_or_modify(path) || !archive.write_file("description.xml",xml) || !archive.close()) return false;
    peraviz::SceneModel model;
    for (const std::string id : {"color", "unsupported"}) {
        model.fixture_patches.push_back({id,1,1,id=="color"?"Color":"Unsupported",path.string()});
        peraviz::SceneNode beam;
        beam.node_id=id+"/Lens"; beam.name="Lens"; beam.is_fixture=true; beam.is_beam=true;
        beam.gdtf_geometry_path="Root/Lens"; beam.gdtf_geometry_key=id+"/Root/Lens";
        model.nodes.push_back(beam);
    }
    const auto scene=peraviz::gdtf_runtime::compile_runtime_scene(model,0);
    std::filesystem::remove(path);
    int missing=0;
    for (const auto &d:scene.diagnostics) if (d.code=="PVZ-GDTF-NO-SUPPORTED-PROPERTIES") {
        if (d.subject.find("unsupported ")!=0) return false;
        ++missing;
    }
    if (missing!=1 || scene.color_targets.size()!=1) return false;
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene({});
    bool no_controls=false;
    for (const auto &d:runtime.diagnostics()) no_controls=no_controls || d.code=="PVZ-RUNTIME-NO-PROPERTIES";
    auto broken=scene;
    broken.source_programs.clear(); broken.diagnostics.clear();
    runtime.install_compiled_scene(broken);
    bool invalid_color=false, failed_install=false;
    for (const auto &d:runtime.diagnostics()) {
        invalid_color=invalid_color || d.code=="PVZ-RUNTIME-INVALID-COLOR-TARGET";
        failed_install=failed_install || d.code=="PVZ-RUNTIME-NO-PROPERTIES";
    }
    return no_controls && invalid_color && failed_install;
}
// Covers RGB/RGBW, exact/ancestor explicit dimmers, unrelated dimmers and excluded CMY semantics.
bool test_additive_intensity() {
    for (bool rgbw:{false,true}) {
        if (!check_authority(false,false,rgbw) || !check_authority(true,false,rgbw) || !check_authority(true,true,rgbw)) return false;
    }
    return check_authority(false,false,false,true) && test_control_diagnostics();
}
