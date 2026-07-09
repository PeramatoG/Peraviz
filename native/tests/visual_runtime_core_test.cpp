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
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    scene.source_programs.push_back({2, CompiledSemantic::Pan, {{10, 1, 0}, {10, 3, 1}}, 0, 65535, -270.0, 270.0, "Pan", "Pan"});
    scene.source_programs.push_back({3, CompiledSemantic::Tilt, {{10, 2, 0}, {10, 4, 1}}, 0, 65535, -135.0, 135.0, "Tilt", "Tilt"});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Dimmer, {{1, 1.0}}});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Pan, {{2, 1.0}}});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Tilt, {{3, 1.0}}});
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
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}, {10, 2, 1}, {10, 4, 2}}, 0, 16777215, 0.0, 1.0, "Dimmer", "Dimmer24"});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Dimmer, {{1, 1.0}}});
    PeravizVisualRuntimeCore runtime;
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
    scene.source_programs.push_back({1, CompiledSemantic::Dimmer, {{10, 0, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerA"});
    scene.source_programs.push_back({2, CompiledSemantic::Dimmer, {{10, 1, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "DimmerB"});
    scene.properties.push_back({1, 101, 1001, CompiledSemantic::Dimmer, {{1, 1.0}, {2, 3.0}}});
    PeravizVisualRuntimeCore runtime;
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
    if (scene.fixtures.size() != 2 || scene.properties.size() < 6) return fail("Expected two compiled fixtures with Dimmer/Pan/Tilt properties");
    bool saw_pan = false;
    bool saw_tilt = false;
    bool saw_dimmer = false;
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
        if (program.semantic == peraviz::runtime::CompiledSemantic::Tilt) {
            saw_tilt = true;
            if (program.sources.size() < 2 || ((program.sources[0].address != 5 || program.sources[1].address != 6) && (program.sources[0].address != 105 || program.sources[1].address != 106))) return fail("Unexpected Tilt coarse/fine source addresses");
            if (program.dmx_from != 0 || program.dmx_to != 65535) return fail("Unexpected Tilt full-resolution DMX range");
            if (std::fabs(program.physical_from + 135.0) > 0.001 || std::fabs(program.physical_to - 135.0) > 0.001) return fail("Unexpected Tilt physical range");
        }
    }
    if (!saw_dimmer || !saw_pan || !saw_tilt) return fail("Expected real Dimmer/Pan/Tilt ChannelFunction programs");
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
    if (visual.descriptors.size() != peraviz::runtime::kVisualSectionDescriptorStride * 2) return fail("Expected only Transform and Intensity sections");
    bool has_transform = false;
    bool has_intensity = false;
    for (size_t index = 0; index + peraviz::runtime::kVisualSectionDescriptorStride <= visual.descriptors.size(); index += peraviz::runtime::kVisualSectionDescriptorStride) {
        has_transform = has_transform || visual.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::GeometryTransform);
        has_intensity = has_intensity || visual.descriptors[index] == static_cast<int32_t>(peraviz::runtime::VisualSectionType::EmitterIntensity);
    }
    if (!has_transform || !has_intensity) return fail("Expected transform and intensity output sections");
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
    if (std::fabs(dimmer - 0.751969f) > 0.001f) return fail("Expected high Dimmer ChannelFunction to be selected exactly");
    return 0;
}

} // namespace

// Runs compiled scene runtime behavior tests.
int main() {
    if (test_compiled_scene_e2e() != 0) return 1;
    if (test_non_adjacent_16_bit_value() != 0) return 1;
    if (test_more_than_two_source_bytes() != 0) return 1;
    if (test_multiple_contributors() != 0) return 1;
    if (test_parser_owned_runtime_scene() != 0) return 1;
    if (test_full_resolution_ranges_and_function_selection() != 0) return 1;
    return 0;
}
