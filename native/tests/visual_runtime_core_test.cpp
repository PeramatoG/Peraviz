#include "runtime/peraviz_visual_runtime.h"
#include "runtime/color_science.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "archive/zip_archive.h"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <algorithm>
#include <vector>

namespace {

// Reports a visual runtime test failure.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}


// Derives the repository root path relative to this source file.
std::filesystem::path repo_root_from_source() {
    return std::filesystem::weakly_canonical(std::filesystem::path(__FILE__)).parent_path().parent_path().parent_path();
}

// Reads an entire text file into memory.
std::string read_file(const std::filesystem::path &path) {
    std::ifstream file(path);
    if (!file.good()) return {};
    return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

// Creates a minimal GDTF archive with the provided XML.
bool write_gdtf_archive(const std::filesystem::path &path, const std::string &description_xml) {
    peraviz::archive::ZipArchive archive;
    if (!archive.open_create_or_modify(path)) return false;
    if (!archive.write_file("description.xml", description_xml)) return false;
    return archive.close();
}

// Creates a compiled Dimmer/Pan/Tilt scene with stable fixture-owned IDs.
peraviz::runtime::CompiledRuntimeScene make_scene() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-1", "RegressionFixture", "Mode 1", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    scene.source_programs.push_back({2, peraviz::runtime::CompiledSemantic::Pan, {{10, 1, 0}, {10, 3, 1}}, 0, 65535, -270.0, 270.0, "Pan", "Pan"});
    scene.source_programs.push_back({3, peraviz::runtime::CompiledSemantic::Tilt, {{10, 2, 0}, {10, 4, 1}}, 0, 65535, -135.0, 135.0, "Tilt", "Tilt"});
    scene.properties.push_back({10001, 1, 101, 1001, peraviz::runtime::CompiledSemantic::Dimmer, {{1, 1.0}}});
    scene.properties.push_back({10002, 1, 101, 1001, peraviz::runtime::CompiledSemantic::Pan, {{2, 1.0}}});
    scene.properties.push_back({10003, 1, 101, 1001, peraviz::runtime::CompiledSemantic::Tilt, {{3, 1.0}}});
    return scene;
}

// Reads the first dimmer value from the emitter intensity section.
float first_intensity_dimmer(const peraviz::runtime::SectionedVisualFrame &frame) {
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= frame.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        if (frame.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterIntensity)) {
            const int32_t float_offset = frame.descriptors[index + 3];
            return float_offset >= 0 && float_offset < static_cast<int32_t>(frame.floats.size()) ? frame.floats[static_cast<size_t>(float_offset)] : -1.0f;
        }
    }
    return -1.0f;
}

// Verifies the production path emits transform and intensity sections from compiled programs.
int test_compiled_scene_e2e() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_scene());
    std::vector<uint8_t> frame(8, 0);
    frame[0] = 255;
    frame[1] = 0x80;
    frame[3] = 0x00;
    frame[2] = 0x40;
    frame[4] = 0x00;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.descriptors.size() < peraviz::runtime::kVisualSectionDescriptorStride * 2) return fail("Expected transform and intensity sections");
    if (visual.integers.size() < 7 || visual.integers[1] != 101 || visual.integers[2] != 101 || visual.integers[5] != 1001) return fail("Expected stable IDs from compiled scene rows");
    if (visual.floats.empty()) return fail("Expected cooked float payloads");
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Unchanged relevant DMX values should not dirty output");
    return 0;
}

// Verifies non-adjacent coarse/fine bytes are assembled as one 16-bit value.
int test_non_adjacent_16_bit_value() {
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(make_scene());
    std::vector<uint8_t> frame(8, 0);
    frame[1] = 0xff;
    frame[3] = 0xff;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.floats.empty() || std::fabs(visual.floats[0] - 270.0f) > 0.01f) return fail("Expected non-adjacent 16-bit Pan maximum physical value");
    return 0;
}

// Verifies the source reader accepts more than two ordered bytes through the compiled model.
int test_more_than_two_source_bytes() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-1", "RegressionFixture", "Mode 1", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 0, 0}, {10, 2, 1}, {10, 4, 2}}, 0, 16777215, 0.0, 1.0, "Dimmer", "Dimmer24"});
    scene.properties.push_back({10001, 1, 101, 1001, peraviz::runtime::CompiledSemantic::Dimmer, {{1, 1.0}}});
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(8, 0xff);
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.descriptors.empty()) return fail("Expected 24-bit source program to emit output");
    return 0;
}

// Verifies one property can name multiple compiled contributors deterministically.
int test_multiple_contributors() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene = make_scene();
    scene.source_programs.clear();
    scene.properties.clear();
    scene.source_programs.push_back({1, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerA"});
    scene.source_programs.push_back({2, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 1, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerB"});
    scene.properties.push_back({10004, 1, 101, 1001, peraviz::runtime::CompiledSemantic::Dimmer, {{1, 1.0}, {2, 3.0}}});
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(8, 0);
    frame[0] = 0;
    frame[1] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (std::fabs(first_intensity_dimmer(visual) - 0.75f) > 0.001f) return fail("Expected weighted contributors to resolve exact dimmer value");

    CompiledRuntimeScene zero_scene = scene;
    zero_scene.properties[0].contributors[1].weight = 0.0;
    PeravizVisualRuntimeCore zero_runtime;
    zero_runtime.install_compiled_scene(zero_scene);
    zero_runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto zero_visual = zero_runtime.consume_latest_visual_frame();
    if (std::fabs(first_intensity_dimmer(zero_visual)) > 0.001f) return fail("Expected zero-weight contributor not to override the property value");
    return 0;
}


// Counts rows in the emitter intensity section.
int intensity_row_count(const peraviz::runtime::SectionedVisualFrame &frame) {
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= frame.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        if (frame.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterIntensity)) {
            return frame.descriptors[index + 1];
        }
    }
    return 0;
}

// Verifies repeated Dimmer properties emit independent target rows without last-target-wins behavior.
int test_independent_dimmer_targets() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture-1", "RegressionFixture", "Mode 1", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({1, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 100.0, "Dimmer", "DimmerA"});
    scene.source_programs.push_back({2, peraviz::runtime::CompiledSemantic::Dimmer, {{10, 1, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerB"});
    scene.properties.push_back({20001, 1, 501, 1501, peraviz::runtime::CompiledSemantic::Dimmer, {{1, 1.0}}});
    scene.properties.push_back({20002, 1, 502, 1502, peraviz::runtime::CompiledSemantic::Dimmer, {{2, 1.0}}});
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(8, 0);
    frame[0] = 128;
    frame[1] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (intensity_row_count(visual) != 2) return fail("Expected one intensity row per Dimmer render target");
    if (visual.integers.size() < 6 || visual.integers[1] == visual.integers[4]) return fail("Expected distinct Dimmer render target IDs");
    if (visual.floats.size() < 10) return fail("Expected two Dimmer float payloads");
    if (std::fabs(visual.floats[0] - (128.0f / 255.0f)) > 0.001f) return fail("Expected physical 0-100 Dimmer to emit normalized 0-1");
    if (std::fabs(visual.floats[5] - 1.0f) > 0.001f) return fail("Expected second Dimmer target maximum normalized value");

    frame[0] = 128;
    frame[1] = 64;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const auto second = runtime.consume_latest_visual_frame();
    if (intensity_row_count(second) != 1) return fail("Expected only the changed Dimmer target to emit a row");
    if (second.integers.size() < 3 || second.integers[1] != 1502) return fail("Expected unchanged Dimmer target to remain clean");
    return 0;
}

// Verifies parser-owned scene compilation and runtime output from real ChannelFunction records.
int test_parser_owned_runtime_scene() {
    const std::filesystem::path repo_root = repo_root_from_source();
    const std::string golden_xml = read_file(repo_root / "native/tests/data/golden_fixture_description.xml");
    if (golden_xml.empty()) return fail("Failed to read golden fixture XML");
    const std::filesystem::path temp_dir = std::filesystem::temp_directory_path() / "peraviz_native_visual_runtime_tests";
    std::error_code ec;
    std::filesystem::create_directories(temp_dir, ec);
    const std::filesystem::path gdtf_path = temp_dir / "golden_fixture.gdtf";
    if (!write_gdtf_archive(gdtf_path, golden_xml)) return fail("Failed to write parser-owned runtime test GDTF");
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"fixture-a", 10, 1, "Standard", gdtf_path.string()});
    model.fixture_patches.push_back({"fixture-b", 10, 101, "Standard", gdtf_path.string()});
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    if (scene.fixtures.size() != 2 || scene.properties.size() < 8) return fail("Expected two compiled fixtures with Dimmer/Pan/Tilt/Zoom properties");
    bool saw_pan = false;
    bool saw_tilt = false;
    bool saw_dimmer = false;
    bool saw_zoom = false;
    for (const auto &program : scene.source_programs) {
        if (program.semantic == peraviz::runtime::CompiledSemantic::Dimmer) {
            saw_dimmer = true;
            if (program.dmx_from != 0 || program.dmx_to != 16777215 || std::fabs(program.physical_from - 0.0) > 0.001 || std::fabs(program.physical_to - 1.0) > 0.001) return fail("Unexpected Dimmer ChannelFunction range");
            if (program.sources.empty() || (program.sources[0].address != 0 && program.sources[0].address != 100)) return fail("Unexpected Dimmer source address");
        }
        if (program.semantic == peraviz::runtime::CompiledSemantic::Pan) {
            saw_pan = true;
            if (program.sources.size() < 2 || ((program.sources[0].address != 3 || program.sources[1].address != 4) && (program.sources[0].address != 103 || program.sources[1].address != 104))) return fail("Unexpected Pan coarse/fine source addresses");
            if (program.dmx_from != 0 || program.dmx_to != 65535) return fail("Unexpected Pan full-resolution DMX range");
            if (std::fabs(program.physical_from + 270.0) > 0.001 || std::fabs(program.physical_to - 270.0) > 0.001) return fail("Unexpected Pan physical range");
        }
        if (program.semantic == peraviz::runtime::CompiledSemantic::Zoom) {
            saw_zoom = true;
            if (program.dmx_from != 0 || program.dmx_to != 255) return fail("Unexpected Zoom DMX range");
            if (std::fabs(program.physical_from - 10.0) > 0.001 || std::fabs(program.physical_to - 40.0) > 0.001) return fail("Unexpected Zoom physical range");
        }
        if (program.semantic == peraviz::runtime::CompiledSemantic::Tilt) {
            saw_tilt = true;
            if (program.sources.size() < 2 || ((program.sources[0].address != 5 || program.sources[1].address != 6) && (program.sources[0].address != 105 || program.sources[1].address != 106))) return fail("Unexpected Tilt coarse/fine source addresses");
            if (program.dmx_from != 0 || program.dmx_to != 65535) return fail("Unexpected Tilt full-resolution DMX range");
            if (std::fabs(program.physical_from + 135.0) > 0.001 || std::fabs(program.physical_to - 135.0) > 0.001) return fail("Unexpected Tilt physical range");
        }
    }
    if (!saw_dimmer || !saw_pan || !saw_tilt || !saw_zoom) return fail("Expected real Dimmer/Pan/Tilt/Zoom ChannelFunction programs");
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(160, 0);
    dmx[0] = 255;
    dmx[3] = 0xff;
    dmx[4] = 0xff;
    dmx[5] = 0x80;
    dmx[6] = 0x00;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    if (visual.descriptors.size() < peraviz::runtime::kVisualSectionDescriptorStride * 3) return fail("Expected Transform, Intensity, and BeamOptics sections");
    bool has_transform = false;
    bool has_intensity = false;
    bool has_optics = false;
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= visual.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        has_transform = has_transform || visual.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::GeometryTransform);
        has_intensity = has_intensity || visual.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterIntensity);
        has_optics = has_optics || visual.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::BeamOptics);
    }
    if (!has_transform || !has_intensity || !has_optics) return fail("Expected transform, intensity, and optics output sections");
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected unchanged relevant DMX to produce no dirty rows");
    return 0;
}

// Verifies full-resolution GDTF DMX value syntax and multi-function selection.
int test_full_resolution_ranges_and_function_selection() {
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF><DMXModes><DMXMode Name="Mode16"><DMXChannels>
  <DMXChannel Offset="1"><LogicalChannel Attribute="Dimmer">
    <ChannelFunction Name="Low" Attribute="Dimmer" DMXFrom="0/1" DMXTo="127/1" PhysicalFrom="0" PhysicalTo="0.5" />
    <ChannelFunction Name="High" Attribute="Dimmer" DMXFrom="128/1" DMXTo="255/1" PhysicalFrom="0.5" PhysicalTo="1" />
  </LogicalChannel></DMXChannel>
  <DMXChannel Offset="2,3" Geometry="PanAxis"><LogicalChannel Attribute="Pan">
    <ChannelFunction Name="PanFine" Attribute="Pan" DMXFrom="1024/2" DMXTo="65535/2" PhysicalFrom="-90" PhysicalTo="90" />
  </LogicalChannel></DMXChannel>
</DMXChannels></DMXMode></DMXModes></GDTF>)XML";
    const std::filesystem::path temp_dir = std::filesystem::temp_directory_path() / "peraviz_native_visual_runtime_tests";
    std::error_code ec;
    std::filesystem::create_directories(temp_dir, ec);
    const std::filesystem::path gdtf_path = temp_dir / "range_fixture.gdtf";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Failed to write range fixture GDTF");
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"range-fixture", 1, 1, "Mode16", gdtf_path.string()});
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    bool saw_pan_range = false;
    bool saw_multi_dimmer = false;
    for (const auto &program : scene.source_programs) {
        if (program.semantic == peraviz::runtime::CompiledSemantic::Pan && program.dmx_from == 1024 && program.dmx_to == 65535) saw_pan_range = true;
    }
    for (const auto &property : scene.properties) {
        if (property.semantic == peraviz::runtime::CompiledSemantic::Dimmer && property.contributors.size() == 2) saw_multi_dimmer = true;
    }
    if (!saw_pan_range) return fail("Expected exact 16-bit Pan DMX range");
    if (!saw_multi_dimmer) return fail("Expected multiple Dimmer ChannelFunctions under one property");
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(8, 0);
    dmx[0] = 192;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto visual = runtime.consume_latest_visual_frame();
    const float dimmer = first_intensity_dimmer(visual);
    if (std::fabs(dimmer - (64.0f / 127.0f)) > 0.001f) return fail("Expected high Dimmer ChannelFunction to emit local normalized intensity");
    return 0;
}

// Verifies scoped parser traversal accepts direct channel wrappers and infers missing DMXTo ranges.
int test_direct_channels_and_inferred_ranges() {
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF><DMXModes><DMXMode Name="DirectMode">
  <VendorWrapper><DMXChannel Offset="1"><LogicalChannel Attribute="Dimmer">
    <ChannelFunction Name="DimmerLow" Attribute="Dimmer" DMXFrom="0/1" PhysicalFrom="0" PhysicalTo="0.25" />
    <ChannelFunction Name="DimmerHigh" Attribute="Dimmer" DMXFrom="128/1" PhysicalFrom="0.5" PhysicalTo="1" />
  </LogicalChannel></DMXChannel></VendorWrapper>
  <DMXChannel Offset="2,3" Geometry="PanAxis"><LogicalChannel Attribute="Pan">
    <ChannelFunction Name="Pan16" Attribute="Pan" DMXFrom="0/2" PhysicalFrom="-100" PhysicalTo="100" />
  </LogicalChannel></DMXChannel>
</DMXMode></DMXModes></GDTF>)XML";
    const std::filesystem::path temp_dir = std::filesystem::temp_directory_path() / "peraviz_native_visual_runtime_tests";
    std::error_code ec;
    std::filesystem::create_directories(temp_dir, ec);
    const std::filesystem::path gdtf_path = temp_dir / "direct_fixture.gdtf";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Failed to write direct-channel fixture GDTF");
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"direct-a", 1, 1, " DirectMode ", gdtf_path.string()});
    model.fixture_patches.push_back({"direct-b", 1, 11, "directmode", gdtf_path.string()});
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, -1);
    if (scene.gdtf_files_opened != 1) return fail("Expected fixture type compilation cache to parse one GDTF for two patches");
    if (scene.dmxchannel_records_found < 2 || scene.channel_functions_found < 3) return fail("Expected robust scoped DMXChannel traversal diagnostics");
    bool saw_low = false;
    bool saw_high = false;
    bool saw_pan = false;
    for (const auto &program : scene.source_programs) {
        if (program.semantic == peraviz::runtime::CompiledSemantic::Dimmer && program.function_name == "DimmerLow") saw_low = program.dmx_from == 0 && program.dmx_to == 127;
        if (program.semantic == peraviz::runtime::CompiledSemantic::Dimmer && program.function_name == "DimmerHigh") saw_high = program.dmx_from == 128 && program.dmx_to == 255;
        if (program.semantic == peraviz::runtime::CompiledSemantic::Pan) saw_pan = program.dmx_from == 0 && program.dmx_to == 65535 && program.sources[0].universe_id == 0;
    }
    if (!saw_low || !saw_high || !saw_pan) return fail("Expected inferred Dimmer ranges and 16-bit Pan range on offset-adjusted universe");
    return 0;
}

// Verifies exact Beam LuminousFlux semantics and projected/emission renderer scales.
int test_beam_luminous_flux_profiles() {
    const std::filesystem::path repo_root = repo_root_from_source();
    const std::string golden_xml = read_file(repo_root / "native/tests/data/golden_fixture_description.xml");
    if (golden_xml.empty()) return fail("Failed to read golden fixture XML for Beam LuminousFlux test");
    const std::filesystem::path temp_dir = std::filesystem::temp_directory_path() / "peraviz_native_visual_runtime_tests";
    std::error_code ec;
    std::filesystem::create_directories(temp_dir, ec);
    const std::filesystem::path gdtf_path = temp_dir / "lumen_fixture.gdtf";
    if (!write_gdtf_archive(gdtf_path, golden_xml)) return fail("Failed to write Beam LuminousFlux test GDTF");
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"fixture-lumen", 1, 1, "Standard", gdtf_path.string()});
    auto add_beam = [&](const std::string &path, bool has_flux, float flux, const std::string &beam_type) {
        peraviz::SceneNode node;
        node.is_beam = true;
        node.gdtf_geometry_path = path;
        node.gdtf_geometry_key = "fixture-lumen/" + path;
        node.has_luminous_flux = has_flux;
        node.luminous_flux = flux;
        node.has_beam_type = true;
        node.beam_type = beam_type;
        model.nodes.push_back(node);
    };
    add_beam("Explicit", true, 320.0f, "Wash");
    add_beam("Missing", false, 0.0f, "Spot");
    add_beam("Zero", true, 0.0f, "Rectangle");
    add_beam("Invalid", true, -10.0f, "PC");
    add_beam("NoneAura", true, 900.0f, "None");
    add_beam("GlowAura", true, 500.0f, "Glow");
    add_beam("Fresnel", true, 20000.0f, "Fresnel");
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    if (scene.beam_profiles.size() != 7) return fail("Expected one Beam profile per exact Beam geometry");
    bool saw_invalid_diagnostic = false;
    for (const auto &diagnostic : scene.diagnostics) {
        if (diagnostic.code == "PVZ-GDTF-BEAM-LUMINOUS-FLUX-INVALID") saw_invalid_diagnostic = true;
    }
    bool saw_explicit = false, saw_missing = false, saw_zero = false, saw_invalid = false, saw_none = false, saw_glow = false, saw_fresnel = false;
    for (const auto &profile : scene.beam_profiles) {
        if (profile.geometry_path == "Explicit") saw_explicit = profile.luminous_flux_source == "explicit" && std::fabs(profile.effective_luminous_flux_lm - 320.0) < 0.001 && std::fabs(profile.projected_lumen_scale - 0.032) < 0.001 && profile.has_projected_beam;
        if (profile.geometry_path == "Missing") saw_missing = profile.luminous_flux_source == "gdtf_default" && std::fabs(profile.effective_luminous_flux_lm - 10000.0) < 0.001 && std::fabs(profile.projected_lumen_scale - 1.0) < 0.001 && profile.has_projected_beam;
        if (profile.geometry_path == "Zero") saw_zero = profile.luminous_flux_source == "explicit" && std::fabs(profile.effective_luminous_flux_lm) < 0.001 && std::fabs(profile.projected_lumen_scale) < 0.001 && profile.has_projected_beam;
        if (profile.geometry_path == "Invalid") saw_invalid = profile.luminous_flux_source == "invalid_safe_value" && std::fabs(profile.effective_luminous_flux_lm) < 0.001 && std::fabs(profile.projected_lumen_scale) < 0.001;
        if (profile.geometry_path == "NoneAura") saw_none = !profile.has_projected_beam && std::fabs(profile.projected_lumen_scale) < 0.001 && std::fabs(profile.emission_lumen_scale - 0.09) < 0.001;
        if (profile.geometry_path == "GlowAura") saw_glow = !profile.has_projected_beam && std::fabs(profile.projected_lumen_scale) < 0.001 && std::fabs(profile.emission_lumen_scale - 0.05) < 0.001;
        if (profile.geometry_path == "Fresnel") saw_fresnel = profile.has_projected_beam && std::fabs(profile.projected_lumen_scale - 2.0) < 0.001;
    }
    if (!saw_invalid_diagnostic) return fail("Expected invalid LuminousFlux diagnostic");
    if (!saw_explicit || !saw_missing || !saw_zero || !saw_invalid || !saw_none || !saw_glow || !saw_fresnel) return fail("Expected Beam LuminousFlux profile semantics");
    return 0;
}

} // namespace

// Runs compiled scene runtime behavior tests.

// Reads the first color section float offset or returns -1 when no color rows exist.
int first_color_float_offset(const peraviz::runtime::SectionedVisualFrame &frame) {
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= frame.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        if (frame.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterColor)) return frame.descriptors[index + 3];
    }
    return -1;
}

// Reads the first color section row count or returns zero when no color rows exist.
int first_color_row_count(const peraviz::runtime::SectionedVisualFrame &frame) {
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= frame.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        if (frame.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterColor)) return frame.descriptors[index + 1];
    }
    return 0;
}

// Verifies corrected native color decomposition separates chromaticity from scalar gain.
bool test_native_color_gain_decomposition() {
    peraviz::runtime::CompiledRuntimeScene scene = make_scene();
    scene.source_programs.push_back({20, peraviz::runtime::CompiledSemantic::ColorSubCyan, {{10, 20, 0}}, 0, 255, 0.0, 1.0, "ColorSub_C", "Cyan"});
    scene.source_programs.push_back({21, peraviz::runtime::CompiledSemantic::ColorSubMagenta, {{10, 21, 0}}, 0, 255, 0.0, 1.0, "ColorSub_M", "Magenta"});
    scene.source_programs.push_back({22, peraviz::runtime::CompiledSemantic::ColorSubYellow, {{10, 22, 0}}, 0, 255, 0.0, 1.0, "ColorSub_Y", "Yellow"});
    peraviz::runtime::CompiledColorTargetProgram cmy;
    cmy.color_target_id = 41001; cmy.fixture_id = 1; cmy.beam_render_target_id = 1001; cmy.geometry_id = 101; cmy.geometry_name = "Head/Beam"; cmy.geometry_key = "fixture-1/Head/Beam"; cmy.additive_source = false;
    cmy.inputs.push_back({20, peraviz::runtime::CompiledSemantic::ColorSubCyan, 0.0, false});
    cmy.inputs.push_back({21, peraviz::runtime::CompiledSemantic::ColorSubMagenta, 0.0, false});
    cmy.inputs.push_back({22, peraviz::runtime::CompiledSemantic::ColorSubYellow, 0.0, false});
    scene.color_targets.push_back(cmy);
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(512, 0);
    frame[20] = 128; frame[21] = 128; frame[22] = 128;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    auto half = runtime.consume_latest_visual_frame();
    int offset = first_color_float_offset(half);
    if (offset < 0) return fail("Expected CMY half transmission color row");
    if (std::fabs(half.floats[offset] - 1.0f) > 0.01f || std::fabs(half.floats[offset + 1] - 1.0f) > 0.01f || std::fabs(half.floats[offset + 2] - 1.0f) > 0.01f) return fail("Expected neutral CMY chromaticity to stay white");
    if (std::fabs(half.floats[offset + 3] - (127.0f / 255.0f)) > 0.01f) return fail("Expected CMY half transmission gain below one");
    frame[20] = 255; frame[21] = 255; frame[22] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    auto closed = runtime.consume_latest_visual_frame();
    offset = first_color_float_offset(closed);
    if (offset < 0) return fail("Expected CMY closure color row");
    if (closed.floats[offset] != 0.0f || closed.floats[offset + 1] != 0.0f || closed.floats[offset + 2] != 0.0f || closed.floats[offset + 3] != 0.0f) return fail("Expected full CMY closure to produce black with zero gain");
    for (int i = 0; i < 4; ++i) if (!std::isfinite(closed.floats[offset + i])) return fail("Expected finite CMY closure payload");
    frame[20] = 128; frame[21] = 128; frame[22] = 128;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    auto reopened = runtime.consume_latest_visual_frame();
    if (first_color_row_count(reopened) != 1) return fail("Expected gain-only neutral chromaticity change to emit one row");
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (first_color_row_count(runtime.consume_latest_visual_frame()) != 0) return fail("Expected unchanged gain and chromaticity to emit no row");
    frame[1] = 100;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (first_color_row_count(runtime.consume_latest_visual_frame()) != 0) return fail("Expected pan-only change to emit no color rows");
    return true;
}

// Verifies native additive RGBW and subtractive CMY color rows remain target-oriented and dirty-only.
bool test_native_color_mixing_rows() {
    peraviz::runtime::CompiledRuntimeScene scene = make_scene();
    scene.source_programs.push_back({10, peraviz::runtime::CompiledSemantic::ColorAddRed, {{10, 5, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_R", "Red"});
    scene.source_programs.push_back({11, peraviz::runtime::CompiledSemantic::ColorAddGreen, {{10, 6, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_G", "Green"});
    scene.source_programs.push_back({12, peraviz::runtime::CompiledSemantic::ColorAddBlue, {{10, 7, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_B", "Blue"});
    scene.source_programs.push_back({13, peraviz::runtime::CompiledSemantic::ColorAddWhite, {{10, 8, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_W", "White"});
    scene.source_programs.push_back({14, peraviz::runtime::CompiledSemantic::ColorSubCyan, {{10, 9, 0}}, 0, 255, 0.0, 1.0, "ColorSub_C", "Cyan"});
    peraviz::runtime::CompiledColorTargetProgram color_target;
    color_target.color_target_id = 40001;
    color_target.fixture_id = 1;
    color_target.beam_render_target_id = 1001;
    color_target.geometry_id = 101;
    color_target.geometry_name = "Head/Beam";
    color_target.geometry_key = "fixture-1/Head/Beam";
    color_target.additive_source = true;
    color_target.inputs.push_back({10, peraviz::runtime::CompiledSemantic::ColorAddRed, 0.0, false});
    color_target.inputs.push_back({11, peraviz::runtime::CompiledSemantic::ColorAddGreen, 0.0, false});
    color_target.inputs.push_back({12, peraviz::runtime::CompiledSemantic::ColorAddBlue, 0.0, false});
    color_target.inputs.push_back({13, peraviz::runtime::CompiledSemantic::ColorAddWhite, 0.0, false});
    color_target.inputs.push_back({14, peraviz::runtime::CompiledSemantic::ColorSubCyan, 0.0, false});
    scene.color_targets.push_back(color_target);
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(512, 0);
    frame[5] = 255;
    frame[6] = 128;
    frame[8] = 64;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    peraviz::runtime::SectionedVisualFrame visual = runtime.consume_latest_visual_frame();
    const int color_offset = first_color_float_offset(visual);
    if (color_offset < 0) return fail("Expected one native EmitterColor row for RGBW target");
    if (visual.floats.size() < static_cast<size_t>(color_offset + 4)) return fail("Expected RGB plus gain color payload");
    if (visual.floats[color_offset] < visual.floats[color_offset + 1] || visual.floats[color_offset + 1] < visual.floats[color_offset + 2]) return fail("Expected red-dominant RGBW color with white contribution");
    if (visual.floats[color_offset + 3] <= 1.0f) return fail("Expected RGBW color gain to preserve additive energy");
    const uint64_t color_inputs_after_first = runtime.stats().color_inputs_evaluated;
    frame[0] = 127;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    peraviz::runtime::SectionedVisualFrame dimmer_only = runtime.consume_latest_visual_frame();
    if (first_color_float_offset(dimmer_only) >= 0) return fail("Expected dimmer-only change to emit no color row");
    if (runtime.stats().color_inputs_evaluated != color_inputs_after_first) return fail("Expected dimmer-only change to evaluate no color inputs");
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    peraviz::runtime::SectionedVisualFrame stable = runtime.consume_latest_visual_frame();
    if (!stable.descriptors.empty()) return fail("Expected unchanged color inputs to skip visual updates");
    frame[9] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    peraviz::runtime::SectionedVisualFrame filtered = runtime.consume_latest_visual_frame();
    const int filtered_offset = first_color_float_offset(filtered);
    if (filtered_offset < 0 || filtered.floats[filtered_offset] > 0.05f) return fail("Expected ColorSub_C fallback to reduce red transmission");
    return true;
}


// Verifies color channels on ancestor geometries compile to descendant Beam target IDs.
bool test_color_inheritance_compiles_to_beam_targets() {
    const std::filesystem::path path = std::filesystem::temp_directory_path() / "peraviz_color_inheritance_test.gdtf";
    const std::string xml = R"XML(<GDTF><FixtureType Name="ColorFixture">
  <Geometries><Geometry Name="Base"><Beam Name="Beam" /></Geometry></Geometries>
  <DMXModes><DMXMode Name="Mode 1" Geometry="Base"><DMXChannels>
    <DMXChannel Offset="1" Geometry="Base"><LogicalChannel Attribute="ColorAdd_R"><ChannelFunction Attribute="ColorAdd_R" DMXFrom="0" DMXTo="255" PhysicalFrom="0" PhysicalTo="1" /></LogicalChannel></DMXChannel>
  </DMXChannels></DMXMode></DMXModes>
</FixtureType></GDTF>)XML";
    if (!write_gdtf_archive(path, xml)) return fail("Expected color inheritance fixture archive to be written");
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"fixture-color", 10, 1, "Mode 1", path.string()});
    peraviz::SceneNode beam;
    beam.node_id = "fixture-color/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Base/Beam";
    beam.gdtf_geometry_key = "fixture-color/Base/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    if (scene.color_targets.size() != 1) return fail("Expected one inherited color target for descendant Beam");
    if (scene.color_targets[0].beam_render_target_id <= 0 || scene.color_targets[0].beam_render_target_id != scene.beam_profiles[0].render_target_id) return fail("Expected color target to use Beam render target ID");
    if (scene.properties.empty() == false) return fail("Expected color inputs to avoid generic component properties");
    return true;
}

// Verifies native CIE conversion and gain decomposition reference values.
bool test_physical_color_science_references() {
    const peraviz::runtime::CieXyz white = peraviz::runtime::cie_xyy_to_xyz({0.3127, 0.3290, 1.0, true});
    if (!white.valid || std::fabs(white.x - 0.9504) > 0.001 || std::fabs(white.y - 1.0) > 0.001 || std::fabs(white.z - 1.0889) > 0.002) return fail("Expected D65 xyY to convert to reference XYZ");
    const peraviz::runtime::LinearRgb rgb = peraviz::runtime::xyz_to_linear_srgb(white);
    if (std::fabs(rgb.r - 1.0) > 0.002 || std::fabs(rgb.g - 1.0) > 0.002 || std::fabs(rgb.b - 1.0) > 0.002) return fail("Expected D65 XYZ to round trip to linear sRGB white");
    double gain = 0.0;
    const peraviz::runtime::LinearRgb normalized = peraviz::runtime::normalize_color_gain({2.0, 1.0, 0.5}, gain);
    if (std::fabs(gain - 2.0) > 0.0001 || std::fabs(normalized.r - 1.0) > 0.0001 || std::fabs(normalized.g - 0.5) > 0.0001 || std::fabs(normalized.b - 0.25) > 0.0001) return fail("Expected color gain to be separated once from chromaticity");
    if (peraviz::runtime::dominant_wavelength_to_xyz(365.0).valid) return fail("Expected non-visible UV wavelength to be rejected");
    std::vector<peraviz::runtime::SpectralSample> samples = {{450.0, 1.0}, {500.0, 0.5}, {550.0, 0.25}};
    if (!peraviz::runtime::spectrum_to_xyz(samples).valid) return fail("Expected ordered finite spectrum to integrate to XYZ");
    return true;
}

// Verifies linked physical Emitter and Filter resources stay native and preserve the renderer payload contract.
bool test_physical_emitter_filter_runtime_contract() {
    peraviz::runtime::CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({10, peraviz::runtime::CompiledSemantic::ColorAddRed, {{10, 1, 0}}, 0, 255, 0.0, 1.0, "ColorAdd_R", "Red", 1, "Beam", 101, 0, ""});
    scene.source_programs.push_back({11, peraviz::runtime::CompiledSemantic::ColorSubCyan, {{10, 2, 0}}, 0, 255, 0.0, 1.0, "ColorSub_C", "Cyan", 1, "Beam", 0, 201, ""});
    peraviz::runtime::CompiledEmitterResource emitter;
    emitter.resource_id = 101;
    emitter.name = "Deep Red";
    emitter.color = {0.70, 0.29, 1.0, true};
    const peraviz::runtime::LinearRgb emitter_rgb = peraviz::runtime::xyz_to_linear_srgb(peraviz::runtime::cie_xyy_to_xyz({0.70, 0.29, 1.0, true}));
    emitter.fallback_linear_r = emitter_rgb.r;
    emitter.fallback_linear_g = emitter_rgb.g;
    emitter.fallback_linear_b = emitter_rgb.b;
    emitter.valid = true;
    scene.emitter_resources.push_back(emitter);
    peraviz::runtime::CompiledFilterResource filter;
    filter.resource_id = 201;
    filter.name = "Half Transmission";
    filter.color = {0.3127, 0.3290, 0.5, true};
    filter.fallback_linear_r = 1.0;
    filter.fallback_linear_g = 1.0;
    filter.fallback_linear_b = 1.0;
    filter.fallback_transmission = 0.5;
    filter.valid = true;
    scene.filter_resources.push_back(filter);
    peraviz::runtime::CompiledColorTargetProgram target;
    target.color_target_id = 1;
    target.fixture_id = 1;
    target.beam_render_target_id = 77;
    target.geometry_id = 1;
    target.additive_source = true;
    target.inputs.push_back({10, peraviz::runtime::CompiledSemantic::ColorAddRed, 0.0, false, 101, 0});
    target.inputs.push_back({11, peraviz::runtime::CompiledSemantic::ColorSubCyan, 0.0, false, 0, 201});
    scene.color_targets.push_back(target);
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> frame(512, 0);
    frame[1] = 255;
    frame[2] = 255;
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    const peraviz::runtime::SectionedVisualFrame visual = runtime.consume_latest_visual_frame();
    const int color_offset = first_color_float_offset(visual);
    if (color_offset < 0) return fail("Expected physical color update to emit one EmitterColor row");
    if (visual.integers.size() != 3 || visual.floats.size() != 4) return fail("Expected physical color to preserve compact EmitterColor payload shape");
    if (visual.floats[color_offset + 3] <= 0.0f || visual.floats[color_offset + 3] >= static_cast<float>(std::max(emitter_rgb.r, std::max(emitter_rgb.g, emitter_rgb.b)))) return fail("Expected linked Filter transmission to reduce physical emitter gain");
    runtime.submit_universe_frame(10, frame.data(), static_cast<int>(frame.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected static physical color to emit no repeated row");
    return true;
}

// Reads the first wheel selection descriptor details.
bool first_wheel_selection_row(const peraviz::runtime::SectionedVisualFrame &frame, int &int_offset, int &float_offset) {
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= frame.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        if (frame.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelSelection)) {
            int_offset = frame.descriptors[index + 2];
            float_offset = frame.descriptors[index + 3];
            return true;
        }
    }
    return false;
}


// Verifies wheel Filter optics store shape and scalar gain without double-counting transmission.
bool test_wheel_filter_transmission_cooking() {
    const std::filesystem::path root = repo_root_from_source();
    const std::filesystem::path gdtf_path = root / "native" / "build" / "color_wheel_filter_transmission.gdtf";
    std::filesystem::create_directories(gdtf_path.parent_path());
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF>
  <FixtureType Name="Wheel Filter Transmission">
    <PhysicalDescriptions>
      <Filters>
        <Filter Name="White50" Color="0.3127,0.3290,0.5" />
        <Filter Name="White10" Color="0.3127,0.3290,0.1" />
        <Filter Name="Red10" Color="0.7000,0.3000,0.1" />
        <Filter Name="Spec035"><Measurement Physical="100" Transmission="0.35"><MeasurementPoint WaveLength="450" Energy="0.1" /><MeasurementPoint WaveLength="620" Energy="1.0" /></Measurement></Filter>
        <Filter Name="Spec035Scaled"><Measurement Physical="100" Transmission="0.35"><MeasurementPoint WaveLength="450" Energy="10" /><MeasurementPoint WaveLength="620" Energy="100" /></Measurement></Filter>
        <Filter Name="CieShapeTransmission" Color="0.1500,0.0600,0.2"><Measurement Physical="100" Transmission="0.35" /></Filter>
        <Filter Name="Closed" Color="0.3127,0.3290,0" />
      </Filters>
    </PhysicalDescriptions>
    <Wheels>
      <Wheel Name="ColorWheel1">
        <Slot Name="Open" Color="0.3127,0.3290,1" />
        <Slot Name="White50" Filter="White50" />
        <Slot Name="White10" Filter="White10" />
        <Slot Name="Red10" Filter="Red10" />
        <Slot Name="Spec035" Filter="Spec035" />
        <Slot Name="Spec035Scaled" Filter="Spec035Scaled" />
        <Slot Name="CieShapeTransmission" Filter="CieShapeTransmission" />
        <Slot Name="Closed" Filter="Closed" />
      </Wheel>
    </Wheels>
    <Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Wash" LuminousFlux="10000" BeamAngle="25" FieldAngle="25" /></Geometry></Geometries>
    <DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
      <DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Color1" Snap="Yes"><ChannelFunction Name="Color Select" Attribute="Color1" Wheel="ColorWheel1" DMXFrom="0" DMXTo="255">
        <ChannelSet Name="Open" DMXFrom="0/1" WheelSlotIndex="1" />
        <ChannelSet Name="White50" DMXFrom="32/1" WheelSlotIndex="2" />
        <ChannelSet Name="White10" DMXFrom="64/1" WheelSlotIndex="3" />
        <ChannelSet Name="Red10" DMXFrom="96/1" WheelSlotIndex="4" />
        <ChannelSet Name="Spec035" DMXFrom="128/1" WheelSlotIndex="5" />
        <ChannelSet Name="Spec035Scaled" DMXFrom="160/1" WheelSlotIndex="6" />
        <ChannelSet Name="CieShapeTransmission" DMXFrom="192/1" WheelSlotIndex="7" />
        <ChannelSet Name="Closed" DMXFrom="224/1" WheelSlotIndex="8" />
      </ChannelFunction></LogicalChannel></DMXChannel>
    </DMXChannels></DMXMode></DMXModes>
  </FixtureType>
</GDTF>)XML";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Expected filter transmission GDTF archive to be written") == 0;
    peraviz::SceneModel scene_model;
    peraviz::SceneModel::FixturePatch patch;
    patch.fixture_uuid = "wheel-filter-fixture";
    patch.gdtf_path = gdtf_path.string();
    patch.dmx_mode = "Mode 1";
    patch.mvr_universe = 1;
    patch.mvr_address = 1;
    scene_model.fixture_patches.push_back(patch);
    peraviz::SceneNode beam;
    beam.node_id = "wheel-filter-fixture/Root/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = "wheel-filter-fixture/Root/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    scene_model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(scene_model, 0);
    if (scene.wheel_palettes.empty() || scene.wheel_palettes[0].slots.size() != 8) return fail("Expected eight cooked wheel palette slots") == 0;
    const auto &slots = scene.wheel_palettes[0].slots;
    auto nearly = [](float a, float b, float tolerance) { return std::fabs(a - b) <= tolerance; };
    if (!nearly(slots[1].gain, 0.5f, 0.04f)) return fail("Expected Filter ColorCIE Y=0.5 to cook to gain 0.5, not 0.25") == 0;
    if (!nearly(slots[2].gain, 0.1f, 0.02f)) return fail("Expected Filter ColorCIE Y=0.1 to cook to gain 0.1, not 0.01") == 0;
    const float red_shape_max = std::max(slots[3].linear_red, std::max(slots[3].linear_green, slots[3].linear_blue));
    if (!(slots[3].gain > 0.0f && nearly(red_shape_max, 1.0f, 0.001f) && slots[3].linear_red >= 0.0f && slots[3].linear_green >= 0.0f && slots[3].linear_blue >= 0.0f)) return fail("Expected saturated Filter ColorCIE to produce bounded non-negative shape and non-zero gain") == 0;
    if (!nearly(slots[4].gain, 0.35f, 0.001f)) return fail("Expected Measurement.Transmission to be applied exactly once") == 0;
    if (!nearly(slots[5].gain, 0.35f, 0.001f)) return fail("Expected scaled spectrum to preserve explicit Measurement.Transmission gain") == 0;
    if (!nearly(slots[4].linear_red, slots[5].linear_red, 0.001f) || !nearly(slots[4].linear_green, slots[5].linear_green, 0.001f) || !nearly(slots[4].linear_blue, slots[5].linear_blue, 0.001f)) return fail("Expected spectrum shape normalization to ignore arbitrary spectral scale") == 0;
    if (!nearly(slots[6].gain, 0.35f, 0.001f)) return fail("Expected measurement without spectrum to use Measurement.Transmission as scalar gain") == 0;
    if (!slots[0].identity || !nearly(slots[0].gain, 1.0f, 0.001f)) return fail("Expected Open slot to preserve identity transmission") == 0;
    if (!nearly(slots[7].gain, 0.0f, 0.001f)) return fail("Expected zero ColorCIE Y slot to cook as closed with zero gain") == 0;
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[0] = 96;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto red_frame = runtime.consume_latest_visual_frame();
    int int_offset = -1, float_offset = -1;
    if (!first_wheel_selection_row(red_frame, int_offset, float_offset)) return fail("Expected Red10 filter to emit a WheelSelection row") == 0;
    if (!(red_frame.floats[float_offset + 3] > red_frame.floats[float_offset + 4] && red_frame.floats[float_offset + 6] > 0.0f)) return fail("Expected upstream white through red filter to remain visible and red-dominant") == 0;
    dmx[0] = 224;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto closed_frame = runtime.consume_latest_visual_frame();
    if (!first_wheel_selection_row(closed_frame, int_offset, float_offset)) return fail("Expected Closed filter to emit a WheelSelection row") == 0;
    if (!nearly(closed_frame.floats[float_offset + 6], 0.0f, 0.001f)) return fail("Expected closed filter final gain to be zero") == 0;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected unchanged Filter slot to emit no repeated work") == 0;
    return true;
}


// Verifies Color(n)WheelIndex compiles as indexed state and uses aggregate fallback instead of full-slot selection.
bool test_indexed_wheel_aggregate_fallback() {
    const std::filesystem::path root = repo_root_from_source();
    const std::filesystem::path gdtf_path = root / "native" / "build" / "color_wheel_index_aggregate.gdtf";
    std::filesystem::create_directories(gdtf_path.parent_path());
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF>
  <FixtureType Name="Wheel Index Aggregate">
    <PhysicalDescriptions />
    <Wheels><Wheel Name="ColorWheel1"><Slot Name="Open" Color="0.3127,0.3290,1" /><Slot Name="Red" Color="0.7000,0.3000,0.1" /><Slot Name="Blue" Color="0.1500,0.0600,0.1" /></Wheel></Wheels>
    <Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Wash" LuminousFlux="10000" BeamAngle="25" FieldAngle="25" /></Geometry></Geometries>
    <DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
      <DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Color1WheelIndex" Snap="No"><ChannelFunction Name="Color Wheel Index" Attribute="Color1WheelIndex" Wheel="ColorWheel1" DMXFrom="0" DMXTo="255" PhysicalFrom="-270" PhysicalTo="90" /></LogicalChannel></DMXChannel>
    </DMXChannels></DMXMode></DMXModes>
  </FixtureType>
</GDTF>)XML";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Expected indexed color-wheel GDTF archive to be written") == 0;
    peraviz::SceneModel scene_model;
    peraviz::SceneModel::FixturePatch patch;
    patch.fixture_uuid = "wheel-index-fixture";
    patch.gdtf_path = gdtf_path.string();
    patch.dmx_mode = "Mode 1";
    patch.mvr_universe = 1;
    patch.mvr_address = 1;
    scene_model.fixture_patches.push_back(patch);
    peraviz::SceneNode beam;
    beam.node_id = "wheel-index-fixture/Root/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = "wheel-index-fixture/Root/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    scene_model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(scene_model, 0);
    if (scene.wheel_bindings.empty()) return fail("Expected indexed wheel binding") == 0;
    if (scene.wheel_bindings[0].mode != peraviz::runtime::CompiledWheelMode::Index) return fail("Expected Color1WheelIndex to classify as Index, not Select") == 0;
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[0] = 0;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    auto frame = runtime.consume_latest_visual_frame();
    int int_offset = -1, float_offset = -1;
    if (!first_wheel_selection_row(frame, int_offset, float_offset)) return fail("Expected indexed wheel to emit initial state") == 0;
    if (frame.integers[int_offset + 3] != static_cast<int32_t>(peraviz::runtime::CompiledWheelMode::Index)) return fail("Expected WheelSelection row mode Index") == 0;
    if (frame.integers[int_offset + 4] != 1 || frame.integers[int_offset + 5] != 2 || std::fabs(frame.floats[float_offset + 1]) > 0.001f) return fail("Expected phase zero to start at Open with Red as adjacent slot") == 0;
    const float open_gain = frame.floats[float_offset + 6];
    dmx[0] = 43;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    frame = runtime.consume_latest_visual_frame();
    if (!first_wheel_selection_row(frame, int_offset, float_offset)) return fail("Expected half-indexed wheel position to emit aggregate fallback") == 0;
    const float half_fraction = frame.floats[float_offset + 1];
    const float half_gain = frame.floats[float_offset + 6];
    if (!(half_fraction > 0.45f && half_fraction < 0.56f)) return fail("Expected half-indexed wheel position to preserve split fraction") == 0;
    if (frame.integers[int_offset + 4] != 1 || frame.integers[int_offset + 5] != 2) return fail("Expected half-indexed Open->Red state to preserve adjacent slots") == 0;
    if (!(half_gain > 0.0f && half_gain < open_gain)) return fail("Expected Open->Red aggregate gain to be visible and below Open") == 0;
    dmx[0] = 85;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    frame = runtime.consume_latest_visual_frame();
    if (!first_wheel_selection_row(frame, int_offset, float_offset)) return fail("Expected full-sector indexed wheel position to emit") == 0;
    if (frame.integers[int_offset + 4] != 2 || frame.integers[int_offset + 5] != 3 || frame.floats[float_offset + 1] > 0.01f) return fail("Expected full sector to become seated Red with Blue adjacent, not an abrupt early switch") == 0;
    return true;
}

// Verifies a test-generated GDTF color wheel parses, binds, evaluates DMX, and emits Red then Blue rows.
bool test_gdtf_color_wheel_vertical_slice() {
    const std::filesystem::path root = repo_root_from_source();
    const std::filesystem::path gdtf_path = root / "native" / "build" / "color_wheel_vertical_slice.gdtf";
    std::filesystem::create_directories(gdtf_path.parent_path());
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF>
  <FixtureType Name="Wheel Slice">
    <PhysicalDescriptions />
    <Wheels>
      <Wheel Name="ColorWheel1">
        <Slot Name="Open" Color="0.3127,0.3290,1" />
        <Slot Name="Red" Color="0.7000,0.3000,1" />
        <Slot Name="Blue" Color="0.1500,0.0600,1" />
      </Wheel>
    </Wheels>
    <Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Wash" LuminousFlux="10000" BeamAngle="25" FieldAngle="25" /></Geometry></Geometries>
    <DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
      <DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Color1" Snap="Yes"><ChannelFunction Name="Color Select" Attribute="Color1" Wheel="ColorWheel1" DMXFrom="0" DMXTo="255">
        <ChannelSet Name="Open" DMXFrom="0/1" WheelSlotIndex="1" />
        <ChannelSet Name="Red" DMXFrom="85/1" WheelSlotIndex="2" />
        <ChannelSet Name="Blue" DMXFrom="170/1" WheelSlotIndex="3" />
      </ChannelFunction></LogicalChannel></DMXChannel>
    </DMXChannels></DMXMode></DMXModes>
  </FixtureType>
</GDTF>)XML";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Expected synthetic color-wheel GDTF archive to be written") == 0;
    const auto fixture = peraviz::gdtf_runtime::compile_gdtf_fixture_type(gdtf_path.string(), "Mode 1");
    if (fixture.wheels.size() != 1 || fixture.wheels[0].slots.size() != 3) return fail("Expected parser to preserve one wheel with three ordered slots") == 0;
    peraviz::SceneModel scene_model;
    peraviz::SceneModel::FixturePatch patch;
    patch.fixture_uuid = "wheel-fixture";
    patch.gdtf_path = gdtf_path.string();
    patch.dmx_mode = "Mode 1";
    patch.mvr_universe = 1;
    patch.mvr_address = 1;
    scene_model.fixture_patches.push_back(patch);
    peraviz::SceneNode beam;
    beam.node_id = "wheel-fixture/Root/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = "wheel-fixture/Root/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    scene_model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(scene_model, 0);
    if (scene.wheel_palettes.empty() || scene.wheel_bindings.empty()) return fail("Expected compiled scene to contain a wheel palette and exact Beam binding") == 0;
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    bool schema_has_wheel = false;
    for (const auto &section : runtime.schema().sections) schema_has_wheel = schema_has_wheel || section.section_type == static_cast<int32_t>(peraviz::runtime::VisualSectionType::WheelSelection);
    if (!schema_has_wheel) return fail("Expected installed runtime schema to enable WheelSelection") == 0;
    if (scene.wheel_bindings[0].channel_sets.size() != 3) return fail("Expected three effective ChannelSet ranges") == 0;
    if (scene.wheel_bindings[0].channel_sets[0].dmx_from != 0 || scene.wheel_bindings[0].channel_sets[0].dmx_to != 84) return fail("Expected Open effective range 0..84") == 0;
    if (scene.wheel_bindings[0].channel_sets[1].dmx_from != 85 || scene.wheel_bindings[0].channel_sets[1].dmx_to != 169) return fail("Expected Red effective range 85..169") == 0;
    if (scene.wheel_bindings[0].channel_sets[2].dmx_from != 170 || scene.wheel_bindings[0].channel_sets[2].dmx_to != 255) return fail("Expected Blue effective range 170..255") == 0;
    std::vector<uint8_t> dmx(512, 0);
    auto expect_slot = [&](uint8_t value, int expected_slot) -> bool {
        dmx[0] = value;
        runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
        const auto row = runtime.consume_latest_visual_frame();
        int int_offset = -1, float_offset = -1;
        if (!first_wheel_selection_row(row, int_offset, float_offset)) return fail("Expected boundary DMX value to emit WheelSelection") == 0;
        if (row.integers[int_offset + 4] != expected_slot || row.integers[int_offset + 5] != expected_slot) return fail("Expected boundary DMX value to select requested slot") == 0;
        return true;
    };
    if (!expect_slot(0, 1)) return false;
    if (!expect_slot(85, 2)) return false;
    if (!expect_slot(170, 3)) return false;
    if (!expect_slot(84, 1)) return false;
    if (!expect_slot(169, 2)) return false;
    if (!expect_slot(255, 3)) return false;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected unchanged seated wheel slot to emit no repeated row") == 0;
    dmx[0] = 85;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto red = runtime.consume_latest_visual_frame();
    int int_offset = -1, float_offset = -1;
    if (!first_wheel_selection_row(red, int_offset, float_offset)) return fail("Expected Red DMX value to emit one WheelSelection row") == 0;
    if (!(red.floats[float_offset + 3] > red.floats[float_offset + 5])) return fail("Expected Red aggregate sRGB to be red-dominant") == 0;
    dmx[0] = 170;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto blue = runtime.consume_latest_visual_frame();
    if (!first_wheel_selection_row(blue, int_offset, float_offset)) return fail("Expected Blue DMX value to emit one WheelSelection row") == 0;
    if (!(blue.floats[float_offset + 5] > blue.floats[float_offset + 3])) return fail("Expected Blue aggregate sRGB to be blue-dominant") == 0;
    return true;
}


// Verifies multiple wheel bindings compose into one authoritative final Beam color row.
bool test_ordered_multi_wheel_final_color_rows() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({40, CompiledSemantic::Unknown, {{10, 40, 0}}, 0, 255, 0.0, 1.0, "Color1", "Wheel1"});
    scene.source_programs.push_back({41, CompiledSemantic::Unknown, {{10, 41, 0}}, 0, 255, 0.0, 1.0, "Color2", "Wheel2"});
    CompiledWheelPalette wheel1;
    wheel1.wheel_renderer_id = 401;
    wheel1.fixture_id = 1;
    wheel1.slots.push_back({1, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, true, "", "test"});
    wheel1.slots.push_back({2, 1.0f, 0.48f, 0.48f, 1.0f, 0.20f, 0.20f, 1.0f, false, "", "test"});
    CompiledWheelPalette wheel2;
    wheel2.wheel_renderer_id = 402;
    wheel2.fixture_id = 1;
    wheel2.slots.push_back({1, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, true, "", "test"});
    wheel2.slots.push_back({2, 0.48f, 0.48f, 1.0f, 0.20f, 0.20f, 1.0f, 1.0f, false, "", "test"});
    scene.wheel_palettes.push_back(wheel1);
    scene.wheel_palettes.push_back(wheel2);
    scene.wheel_bindings.push_back({501, 1, 77, 401, 40, CompiledWheelMode::Select, true, 270.0f, {{0, 127, 1, "Open"}, {128, 255, 2, "Red"}}});
    scene.wheel_bindings.push_back({502, 1, 77, 402, 41, CompiledWheelMode::Select, true, 270.0f, {{0, 127, 1, "Open"}, {128, 255, 2, "Blue"}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[40] = 255;
    dmx[41] = 0;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    auto red_open = runtime.consume_latest_visual_frame();
    int offset = first_color_float_offset(red_open);
    if (first_color_row_count(red_open) != 1 || offset < 0) return fail("Expected red/open wheels to emit one final color row") == 0;
    if (!(red_open.floats[offset] > red_open.floats[offset + 2])) return fail("Expected red/open wheels to produce red-dominant final color") == 0;
    dmx[41] = 255;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    auto red_blue = runtime.consume_latest_visual_frame();
    offset = first_color_float_offset(red_blue);
    if (first_color_row_count(red_blue) != 1 || offset < 0) return fail("Expected red/blue wheels to emit exactly one final color row") == 0;
    if (!(red_blue.floats[offset] > 0.0f && red_blue.floats[offset + 2] > 0.0f)) return fail("Expected red/blue composed color to preserve both transmissions") == 0;
    dmx[40] = 0;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    auto open_blue = runtime.consume_latest_visual_frame();
    offset = first_color_float_offset(open_blue);
    if (first_color_row_count(open_blue) != 1 || offset < 0) return fail("Expected returning wheel 1 to Open to emit one final color row") == 0;
    if (!(open_blue.floats[offset + 2] > open_blue.floats[offset])) return fail("Expected open/blue wheels to preserve blue wheel layer") == 0;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected unchanged multi-wheel state to emit no rows") == 0;
    return true;
}


// Verifies seated Color wheel slots resolve by exact one-based WheelSlotIndex, not declaration assumptions or filter order.
bool test_exact_color_wheel_slot_resolution() {
    const std::filesystem::path root = repo_root_from_source();
    const std::filesystem::path gdtf_path = root / "native" / "build" / "exact_color_wheel_slot_resolution.gdtf";
    std::filesystem::create_directories(gdtf_path.parent_path());
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF>
  <FixtureType Name="Exact Slot Resolution">
    <PhysicalDescriptions>
      <Filters>
        <Filter Name="BlueFilter" Color="0.1500,0.0600,0.8" />
        <Filter Name="AmberFilter" Color="0.5800,0.4000,0.8" />
        <Filter Name="GreenFilter" Color="0.1700,0.7000,0.8" />
      </Filters>
    </PhysicalDescriptions>
    <Wheels><Wheel Name="ColorWheelExact">
      <Slot Name="GreenFirst" Filter="GreenFilter" />
      <Slot Name="OpenSecond" />
      <Slot Name="AmberThird" Filter="AmberFilter" />
      <Slot Name="BlueFourth" Filter="BlueFilter" />
    </Wheel></Wheels>
    <Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Wash" LuminousFlux="10000" BeamAngle="25" FieldAngle="25" /></Geometry></Geometries>
    <DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
      <DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Color1" Snap="Yes"><ChannelFunction Name="Color Select" Attribute="Color1" Wheel="ColorWheelExact" DMXFrom="0" DMXTo="255">
        <ChannelSet Name="OpenRange" DMXFrom="0/1" WheelSlotIndex="2" />
        <ChannelSet Name="BlueRange" DMXFrom="64/1" WheelSlotIndex="4" />
        <ChannelSet Name="GreenRange" DMXFrom="128/1" WheelSlotIndex="1" />
        <ChannelSet Name="AmberRange" DMXFrom="192/1" WheelSlotIndex="3" />
        <ChannelSet Name="BlueRepeated" DMXFrom="224/1" WheelSlotIndex="4" />
      </ChannelFunction></LogicalChannel></DMXChannel>
    </DMXChannels></DMXMode></DMXModes>
  </FixtureType>
</GDTF>)XML";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Expected exact slot GDTF archive to be written") == 0;
    peraviz::SceneModel scene_model;
    peraviz::SceneModel::FixturePatch patch;
    patch.fixture_uuid = "exact-slot-fixture";
    patch.gdtf_path = gdtf_path.string();
    patch.dmx_mode = "Mode 1";
    patch.mvr_universe = 1;
    patch.mvr_address = 1;
    scene_model.fixture_patches.push_back(patch);
    peraviz::SceneNode beam;
    beam.node_id = "exact-slot-fixture/Root/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = "exact-slot-fixture/Root/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    scene_model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(scene_model, 0);
    if (scene.wheel_palettes.size() != 1 || scene.wheel_palettes[0].slots.size() != 4) return fail("Expected four declaration-order palette slots") == 0;
    const auto &slots = scene.wheel_palettes[0].slots;
    if (slots[0].slot_index != 1 || slots[0].name != "GreenFirst" || slots[0].provenance.find("GreenFilter") == std::string::npos) return fail("Expected slot 1 to preserve GreenFirst filter provenance") == 0;
    if (slots[1].slot_index != 2 || slots[1].name != "OpenSecond" || !slots[1].identity) return fail("Expected slot 2 to remain the identity OpenSecond slot") == 0;
    if (slots[2].slot_index != 3 || slots[2].name != "AmberThird" || slots[2].provenance.find("AmberFilter") == std::string::npos) return fail("Expected slot 3 to preserve AmberThird filter provenance") == 0;
    if (slots[3].slot_index != 4 || slots[3].name != "BlueFourth" || slots[3].provenance.find("BlueFilter") == std::string::npos) return fail("Expected slot 4 to preserve BlueFourth filter provenance") == 0;
    if (scene.wheel_bindings.empty() || scene.wheel_bindings[0].channel_sets.size() != 5) return fail("Expected five inferred ChannelSet ranges") == 0;
    const auto &sets = scene.wheel_bindings[0].channel_sets;
    if (sets[0].dmx_from != 0 || sets[0].dmx_to != 63 || sets[0].wheel_slot_index != 2) return fail("Expected 0..63 to resolve WheelSlotIndex 2") == 0;
    if (sets[1].dmx_from != 64 || sets[1].dmx_to != 127 || sets[1].wheel_slot_index != 4) return fail("Expected 64..127 to resolve WheelSlotIndex 4") == 0;
    if (sets[2].dmx_from != 128 || sets[2].dmx_to != 191 || sets[2].wheel_slot_index != 1) return fail("Expected 128..191 to resolve WheelSlotIndex 1") == 0;
    if (sets[3].dmx_from != 192 || sets[3].dmx_to != 223 || sets[3].wheel_slot_index != 3) return fail("Expected 192..223 to resolve WheelSlotIndex 3") == 0;
    if (sets[4].dmx_from != 224 || sets[4].dmx_to != 255 || sets[4].wheel_slot_index != 4) return fail("Expected repeated 224..255 to resolve WheelSlotIndex 4") == 0;
    auto expect = [&](uint8_t value, int expected_slot, char dominance) -> bool {
        peraviz::runtime::PeravizVisualRuntimeCore runtime;
        runtime.install_compiled_scene(scene);
        std::vector<uint8_t> dmx(512, 0);
        dmx[0] = value;
        runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
        const auto row = runtime.consume_latest_visual_frame();
        int int_offset = -1, float_offset = -1;
        if (!first_wheel_selection_row(row, int_offset, float_offset)) return fail("Expected exact slot DMX value to emit WheelSelection") == 0;
        if (row.integers[int_offset + 4] != expected_slot || row.integers[int_offset + 5] != expected_slot) return fail("Expected WheelSelection to echo exact WheelSlotIndex") == 0;
        const int color_offset = first_color_float_offset(row);
        if (first_color_row_count(row) != 1 || color_offset < 0) return fail("Expected exact slot DMX value to emit one final color row") == 0;
        const float red = row.floats[color_offset];
        const float green = row.floats[color_offset + 1];
        const float blue = row.floats[color_offset + 2];
        if (dominance == 'w' && !(red > 0.99f && green > 0.99f && blue > 0.99f)) return fail("Expected identity white slot output") == 0;
        if (dominance == 'g' && !(green > red && green > blue)) return fail("Expected green-dominant slot output") == 0;
        if (dominance == 'a' && !(red > blue && green > blue)) return fail("Expected amber slot output") == 0;
        if (dominance == 'b' && !(blue > red && blue > green)) return fail("Expected blue-dominant slot output") == 0;
        return true;
    };
    if (!expect(0, 2, 'w')) return false;
    if (!expect(63, 2, 'w')) return false;
    if (!expect(64, 4, 'b')) return false;
    if (!expect(127, 4, 'b')) return false;
    if (!expect(128, 1, 'g')) return false;
    if (!expect(191, 1, 'g')) return false;
    if (!expect(192, 3, 'a')) return false;
    if (!expect(223, 3, 'a')) return false;
    if (!expect(224, 4, 'b')) return false;
    if (!expect(255, 4, 'b')) return false;
    return true;
}

// Verifies malformed slots keep their one-based index and later slots do not shift.
bool test_malformed_wheel_slot_preserves_indices() {
    const std::filesystem::path root = repo_root_from_source();
    const std::filesystem::path gdtf_path = root / "native" / "build" / "malformed_wheel_slot_indices.gdtf";
    std::filesystem::create_directories(gdtf_path.parent_path());
    const std::string xml = R"XML(<?xml version="1.0" encoding="UTF-8"?>
<GDTF><FixtureType Name="Malformed Slot Index"><Wheels><Wheel Name="ColorWheelBad">
  <Slot Name="Green" Color="0.1700,0.7000,1" />
  <Slot Name="Malformed" Color="not-a-color" />
  <Slot Name="Blue" Color="0.1500,0.0600,1" />
</Wheel></Wheels><Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Wash" LuminousFlux="10000" BeamAngle="25" FieldAngle="25" /></Geometry></Geometries><DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
<DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Color1"><ChannelFunction Name="Color Select" Attribute="Color1" Wheel="ColorWheelBad" DMXFrom="0" DMXTo="255">
  <ChannelSet Name="Green" DMXFrom="0/1" WheelSlotIndex="1" />
  <ChannelSet Name="Malformed" DMXFrom="85/1" WheelSlotIndex="2" />
  <ChannelSet Name="Blue" DMXFrom="170/1" WheelSlotIndex="3" />
</ChannelFunction></LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>)XML";
    if (!write_gdtf_archive(gdtf_path, xml)) return fail("Expected malformed slot GDTF archive to be written") == 0;
    peraviz::SceneModel scene_model;
    peraviz::SceneModel::FixturePatch patch;
    patch.fixture_uuid = "malformed-slot-fixture";
    patch.gdtf_path = gdtf_path.string();
    patch.dmx_mode = "Mode 1";
    patch.mvr_universe = 1;
    patch.mvr_address = 1;
    scene_model.fixture_patches.push_back(patch);
    peraviz::SceneNode beam;
    beam.node_id = "malformed-slot-fixture/Root/Beam";
    beam.name = "Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = "malformed-slot-fixture/Root/Beam";
    beam.is_fixture = true;
    beam.is_beam = true;
    scene_model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(scene_model, 0);
    if (scene.wheel_palettes.empty() || scene.wheel_palettes[0].slots.size() != 3) return fail("Expected malformed slot to remain in palette") == 0;
    if (scene.wheel_palettes[0].slots[1].slot_index != 2 || scene.wheel_palettes[0].slots[2].slot_index != 3) return fail("Expected malformed middle slot not to shift later slot indices") == 0;
    bool saw_malformed = false;
    for (const auto &diagnostic : scene.diagnostics) if (diagnostic.code == "PVZ-GDTF-WHEEL-SLOT-COLOR-INVALID") saw_malformed = true;
    if (!saw_malformed) return fail("Expected malformed ColorCIE diagnostic") == 0;
    peraviz::runtime::PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[0] = 170;
    runtime.submit_universe_frame(1, dmx.data(), static_cast<int>(dmx.size()));
    const auto row = runtime.consume_latest_visual_frame();
    int int_offset = -1, float_offset = -1;
    if (!first_wheel_selection_row(row, int_offset, float_offset)) return fail("Expected WheelSlotIndex 3 to resolve after malformed slot") == 0;
    if (row.integers[int_offset + 4] != 3 || row.integers[int_offset + 5] != 3) return fail("Expected runtime to emit original slot index 3") == 0;
    return true;
}


// Verifies discrete wheel selection does not retain a stale slot outside the active ChannelFunction range.
bool test_select_wheel_inactive_function_range() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({60, CompiledSemantic::Unknown, {{10, 60, 0}}, 32, 160, 0.0, 1.0, "Color1", "PartialRangeWheel"});
    CompiledWheelPalette palette;
    palette.wheel_renderer_id = 601;
    palette.fixture_id = 1;
    palette.slots.push_back({1, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, true, "", "test"});
    palette.slots.push_back({2, 1.0f, 0.48f, 0.48f, 1.0f, 0.20f, 0.20f, 1.0f, false, "", "test"});
    scene.wheel_palettes.push_back(palette);
    scene.wheel_bindings.push_back({6010, 1, 77, 601, 60, CompiledWheelMode::Select, true, 270.0f, {{32, 96, 1, "Open"}, {97, 160, 2, "Red"}}});
    PeravizVisualRuntimeCore runtime;
    runtime.install_compiled_scene(scene);
    std::vector<uint8_t> dmx(512, 0);
    dmx[60] = 16;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    if (!runtime.consume_latest_visual_frame().descriptors.empty()) return fail("Expected inactive low raw DMX value to emit no wheel row") == 0;
    dmx[60] = 120;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    auto active = runtime.consume_latest_visual_frame();
    int int_offset = -1, float_offset = -1;
    if (!first_wheel_selection_row(active, int_offset, float_offset)) return fail("Expected active raw DMX value to emit WheelSelection") == 0;
    if (active.integers[int_offset + 4] != 2) return fail("Expected active raw DMX value to resolve slot 2") == 0;
    dmx[60] = 200;
    runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
    const auto inactive = runtime.consume_latest_visual_frame();
    if (first_wheel_selection_row(inactive, int_offset, float_offset)) return fail("Expected inactive high raw DMX value to emit no stale wheel row") == 0;
    if (first_color_row_count(inactive) != 1) return fail("Expected inactive high raw DMX value to clear stale optical layer through one final color row") == 0;
    return true;
}


// Verifies Select and Index control ranges for one physical wheel replace one another instead of composing together.
bool test_one_physical_wheel_select_index_exclusive() {
    using namespace peraviz::runtime;
    CompiledRuntimeScene scene;
    scene.fixtures.push_back({1, "fixture", "type", "mode", 10, 1, 10000.0, 25.0, 1.0, 20.0});
    scene.source_programs.push_back({70, CompiledSemantic::Unknown, {{10, 70, 0}}, 0, 127, 0.0, 1.0, "Color1", "Color Select"});
    scene.source_programs.push_back({71, CompiledSemantic::Unknown, {{10, 70, 0}}, 128, 255, 0.0, 360.0, "Color1WheelIndex", "Color Index"});
    CompiledWheelPalette palette;
    palette.wheel_renderer_id = 701;
    palette.fixture_id = 1;
    palette.slots.push_back({1, 1.0f, 0.48f, 0.48f, 1.0f, 0.20f, 0.20f, 1.0f, false, "", "red"});
    palette.slots.push_back({2, 0.48f, 0.48f, 1.0f, 0.20f, 0.20f, 1.0f, 1.0f, false, "", "blue"});
    palette.slots.push_back({3, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, true, "", "open"});
    scene.wheel_palettes.push_back(palette);
    scene.wheel_bindings.push_back({7010, 1, 77, 701, 70, CompiledWheelMode::Select, true, 0.0f, {{0, 63, 1, "Red"}, {64, 127, 2, "Blue"}}});
    scene.wheel_bindings.push_back({7011, 1, 77, 701, 71, CompiledWheelMode::Index, false, 0.0f, {}});
    auto evaluate = [&](PeravizVisualRuntimeCore &runtime, uint8_t value, SectionedVisualFrame &out) -> bool {
        std::vector<uint8_t> dmx(512, 0);
        dmx[70] = value;
        runtime.submit_universe_frame(10, dmx.data(), static_cast<int>(dmx.size()));
        out = runtime.consume_latest_visual_frame();
        return true;
    };
    PeravizVisualRuntimeCore direct_runtime;
    direct_runtime.install_compiled_scene(scene);
    SectionedVisualFrame direct_blue;
    evaluate(direct_runtime, 64, direct_blue);
    int direct_int_offset = -1, direct_float_offset = -1;
    if (!first_wheel_selection_row(direct_blue, direct_int_offset, direct_float_offset)) return fail("Expected direct Select blue to emit WheelSelection") == 0;
    if (direct_blue.integers[direct_int_offset + 3] != static_cast<int32_t>(CompiledWheelMode::Select) || direct_blue.integers[direct_int_offset + 4] != 2) return fail("Expected direct path to select seated blue slot") == 0;
    const int direct_color_offset = first_color_float_offset(direct_blue);
    if (direct_color_offset < 0) return fail("Expected direct Select blue to emit final color") == 0;

    PeravizVisualRuntimeCore transition_runtime;
    transition_runtime.install_compiled_scene(scene);
    SectionedVisualFrame red_frame;
    evaluate(transition_runtime, 0, red_frame);
    int red_int_offset = -1, red_float_offset = -1;
    if (!first_wheel_selection_row(red_frame, red_int_offset, red_float_offset) || red_frame.integers[red_int_offset + 4] != 1) return fail("Expected Select red before Index transition") == 0;
    SectionedVisualFrame index_frame;
    evaluate(transition_runtime, 200, index_frame);
    int index_int_offset = -1, index_float_offset = -1;
    if (!first_wheel_selection_row(index_frame, index_int_offset, index_float_offset)) return fail("Expected Index transition to emit physical wheel metadata") == 0;
    if (index_frame.integers[index_int_offset + 3] != static_cast<int32_t>(CompiledWheelMode::Index)) return fail("Expected active physical wheel mode to become Index") == 0;
    const int index_color_offset = first_color_float_offset(index_frame);
    if (index_color_offset < 0) return fail("Expected Index transition to emit final color") == 0;
    if (!(index_frame.floats[index_color_offset] > 0.0f && index_frame.floats[index_color_offset + 2] > 0.0f)) return fail("Expected Index result to stand alone without multiplying stale Select red to black") == 0;
    SectionedVisualFrame path_blue;
    evaluate(transition_runtime, 64, path_blue);
    int path_int_offset = -1, path_float_offset = -1;
    if (!first_wheel_selection_row(path_blue, path_int_offset, path_float_offset)) return fail("Expected Index-to-Select transition to emit metadata") == 0;
    if (path_blue.integers[path_int_offset + 3] != static_cast<int32_t>(CompiledWheelMode::Select) || path_blue.integers[path_int_offset + 4] != 2) return fail("Expected active physical wheel mode to return to seated blue") == 0;
    const int path_color_offset = first_color_float_offset(path_blue);
    if (path_color_offset < 0) return fail("Expected path Select blue to emit final color") == 0;
    for (int component = 0; component < 4; ++component) {
        if (std::fabs(direct_blue.floats[direct_color_offset + component] - path_blue.floats[path_color_offset + component]) > 0.0001f) return fail("Expected direct and transition paths to produce identical final color") == 0;
    }
    if (!(path_blue.integers[path_int_offset + 7] > direct_blue.integers[direct_int_offset + 7])) return fail("Expected physical wheel revision to advance across control-mode transitions") == 0;
    return true;
}

int main() {
    if (test_compiled_scene_e2e() != 0) return 1;
    if (test_non_adjacent_16_bit_value() != 0) return 1;
    if (test_more_than_two_source_bytes() != 0) return 1;
    if (test_multiple_contributors() != 0) return 1;
    if (test_independent_dimmer_targets() != 0) return 1;
    if (test_parser_owned_runtime_scene() != 0) return 1;
    if (test_beam_luminous_flux_profiles() != 0) return 1;
    if (test_full_resolution_ranges_and_function_selection() != 0) return 1;
    if (test_direct_channels_and_inferred_ranges() != 0) return 1;
    if (!test_native_color_mixing_rows()) return 1;
    if (!test_native_color_gain_decomposition()) return 1;
    if (!test_color_inheritance_compiles_to_beam_targets()) return 1;
    if (!test_physical_color_science_references()) return 1;
    if (!test_physical_emitter_filter_runtime_contract()) return 1;
    if (!test_wheel_filter_transmission_cooking()) return 1;
    if (!test_indexed_wheel_aggregate_fallback()) return 1;
    if (!test_ordered_multi_wheel_final_color_rows()) return 1;
    if (!test_exact_color_wheel_slot_resolution()) return 1;
    if (!test_malformed_wheel_slot_preserves_indices()) return 1;
    if (!test_select_wheel_inactive_function_range()) return 1;
    if (!test_one_physical_wheel_select_index_exclusive()) return 1;
    if (!test_gdtf_color_wheel_vertical_slice()) return 1;
    return 0;
}
