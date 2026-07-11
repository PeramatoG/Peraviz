#include "archive/zip_archive.h"
#include "dmx/gdtf_archive_resource_reader.h"
#include "dmx/gdtf_color_cie.h"
#include "dmx/gdtf_dmx_inspector.h"
#include "dmx/gdtf_wheel_catalog.h"

#include <filesystem>
#include <iostream>
#include <string>

#include <tinyxml2.h>

namespace {

// Prints a failure and returns a failing status code.
int fail(const std::string &message) {
    std::cerr << message << std::endl;
    return 1;
}

// Checks the Wheel, Filter, and graphic-wheel catalog parser.
int test_catalog() {
    const char *xml = R"(<FixtureType><Wheels>
        <Wheel Name="Góbó Wheel" Type="Gobo"><WheelSlot Name="Open" Color="0.31,0.33,1"/><WheelSlot Name="Star" MediaFileName="star" Filter="Warm"/></Wheel>
        <Wheel Name="Graphic Wheel" Type="GraphicWheel"><WheelSlot Name="Graphic A" MediaFileName="graphic.png" GraphicWheel="Graphic Wheel"/></Wheel>
        </Wheels><Filters><Filter Name="Warm" Color="0.45,0.41,1"/></Filters></FixtureType>)";
    tinyxml2::XMLDocument doc;
    if (doc.Parse(xml) != tinyxml2::XML_SUCCESS) {
        return fail("catalog XML did not parse");
    }
    const auto catalog = peraviz::dmx::build_gdtf_wheel_catalog(doc.RootElement());
    if (catalog.wheels.size() != 2U || catalog.filters.size() != 1U) {
        return fail("catalog did not preserve wheel/filter counts");
    }
    if (catalog.wheels[0].slots[1].slot_index != 2 || catalog.wheels[1].is_graphic_wheel == false) {
        return fail("catalog did not preserve one-based slots or graphic-wheel classification");
    }
    if (!catalog.wheels[0].slots[0].color.valid || catalog.filters[0].color.value_origin != "Filter.Color") {
        return fail("catalog did not parse slot and filter colors");
    }
    return 0;
}

// Checks CIE xyY parsing, validation, and approximate sRGB conversion.
int test_color() {
    const auto color = peraviz::dmx::parse_gdtf_color_cie("0.3127,0.3290,1", "test");
    const auto preview = peraviz::dmx::convert_cie_xyy_to_srgb_preview(color);
    if (!color.valid || preview.red <= 0.0 || preview.green <= 0.0 || preview.blue <= 0.0) {
        return fail("valid CIE color did not convert to sRGB preview");
    }
    const auto invalid = peraviz::dmx::parse_gdtf_color_cie("0.1,0,1", "test");
    if (invalid.valid || invalid.diagnostics.empty()) {
        return fail("invalid CIE color did not report diagnostics");
    }
    return 0;
}

// Checks safe lazy resource lookup without extracting an archive.
int test_resource_reader() {
    const std::filesystem::path path = std::filesystem::temp_directory_path() / "peraviz_08e3_resource_test.gdtf";
    std::filesystem::remove(path);
    peraviz::archive::ZipArchive archive;
    if (!archive.open_create_or_modify(path)) {
        return fail("could not create test archive");
    }
    archive.write_file("wheels/Star.PNG", std::vector<std::uint8_t>{0x89, 'P', 'N', 'G'});
    archive.write_file("wheels/graphic.png", std::vector<std::uint8_t>{0x89, 'P', 'N', 'G'});
    if (!archive.close()) {
        return fail("could not close test archive");
    }
    const auto resource = peraviz::dmx::read_gdtf_wheel_resource(path, "star");
    if (!resource.loaded || resource.archive_entry_path != "wheels/Star.PNG") {
        return fail("resource reader did not resolve unambiguous wheel resource");
    }
    const auto unsafe = peraviz::dmx::read_gdtf_wheel_resource(path, "../evil.png");
    if (unsafe.loaded || unsafe.diagnostics.empty()) {
        return fail("resource reader accepted unsafe path");
    }
    std::filesystem::remove(path);
    return 0;
}

// Checks deterministic DMX to Function, Set, WheelSlot, Filter, and byte mapping.
int test_dmx_inspector() {
    tinyxml2::XMLDocument doc;
    doc.Parse("<FixtureType><Wheel Name='Gobo'><WheelSlot Name='Open'/><WheelSlot Name='Star' Filter='Warm' MediaFileName='star.png'/></Wheel><Filter Name='Warm' Color='0.4,0.4,1'/></FixtureType>");
    const auto catalog = peraviz::dmx::build_gdtf_wheel_catalog(doc.RootElement());
    peraviz::dmx::GdtfInspectorDmxChannel channel;
    channel.stable_id = "dmx:1";
    channel.byte_count = 2;
    peraviz::dmx::GdtfInspectorLogicalChannel logical;
    logical.stable_id = "logical:1";
    logical.attribute = "Gobo1";
    peraviz::dmx::GdtfInspectorChannelFunction function;
    function.stable_id = "function:1";
    function.name = "Gobo Select";
    function.wheel_name = "Gobo";
    function.dmx_from = 0;
    function.dmx_to = 65535;
    function.physical_from = 10.0;
    function.physical_to = 0.0;
    function.has_physical_range = true;
    function.channel_sets.push_back({"set:open", "Open", 0, 32767, 1});
    function.channel_sets.push_back({"set:star", "Star", 32768, 65535, 2});
    logical.functions.push_back(function);
    channel.logical_channels.push_back(logical);
    const auto result = peraviz::dmx::inspect_gdtf_dmx_value(channel, 40000, catalog);
    if (result.bytes.size() != 2U || result.bytes[0] != 0x9CU || result.bytes[1] != 0x40U) {
        return fail("DMX inspector produced incorrect 16-bit bytes");
    }
    if (result.mappings.empty() || !result.mappings[0].wheel_slot || result.mappings[0].wheel_slot->slot_index != 2) {
        return fail("DMX inspector did not resolve active wheel slot");
    }
    if (!result.mappings[0].filter || !result.mappings[0].physical_reliable || result.mappings[0].physical_value >= 10.0) {
        return fail("DMX inspector did not resolve filter or decreasing physical value");
    }
    return 0;
}

} // namespace

// Runs focused Checkpoint 08E3 core tests.
int main() {
    if (const int rc = test_catalog(); rc != 0) return rc;
    if (const int rc = test_color(); rc != 0) return rc;
    if (const int rc = test_resource_reader(); rc != 0) return rc;
    if (const int rc = test_dmx_inspector(); rc != 0) return rc;
    return 0;
}
