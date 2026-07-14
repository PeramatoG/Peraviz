#include "runtime/peraviz_visual_runtime.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "archive/zip_archive.h"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
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
    if (!test_color_inheritance_compiles_to_beam_targets()) return 1;
    return 0;
}
