#include "archive/zip_archive.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "presentation/control_groups.h"
#include <filesystem>
#include <iostream>
#include <set>

// Exercises parsed attribute identity and explicit links independently of Color-prefixed control names.
static bool test_color_wheel_resource_classification() {
    using peraviz::runtime::ColorPresentationStatus;
    struct Case { const char *attribute; const char *link; bool missing; bool fx_first; };
    const Case cases[] = {
        {"ColorMixReset", "", false, false}, {"ColorCalibrationMode", "", false, false},
        {"ColorNovelControl", "", false, false}, {"Color1", "", true, false},
        {"Color2WheelSpin", "", true, false}, {"Color3WheelIndex", "", true, false},
        {"Color4WheelRandom", "", true, false}, {"Color5WheelAudio", "", true, false},
        {"Color1", "Absent", true, false}, {"Color1", "Absent", true, true},
        {"ColorEffects1", "Absent", true, false}, {"ColorNovelEffect", "Absent", true, false},
    };
    int ordinal = 0;
    for (const auto &entry : cases) {
        const auto path = std::filesystem::temp_directory_path() / ("peraviz_color_ownership_" + std::to_string(ordinal++) + ".gdtf");
        // Keeps exact attribute/link identity in each selected-mode source.
        const auto channel = [](const std::string &attribute, const std::string &link, int offset, const char *geometry = "Root") {
            return "<DMXChannel Offset=\"" + std::to_string(offset) + "\" Geometry=\"" + geometry + "\"><LogicalChannel Attribute=\"" + attribute +
                "\"><ChannelFunction Attribute=\"" + attribute + "\"" + (link.empty() ? "" : " Wheel=\"" + link + "\"") +
                " DMXFrom=\"0\"/></LogicalChannel></DMXChannel>";
        };
        const std::string effect = channel("ColorEffects1", "", 2, "Head");
        const std::string subject = channel(entry.attribute, entry.link, 3);
        const std::string xml = "<GDTF><FixtureType Name=\"Generic\"><Geometries><Geometry Name=\"Root\"><Geometry Name=\"Head\"><Beam Name=\"Output\"/></Geometry></Geometry></Geometries>"
            "<Wheels><Wheel Name=\"Palette\"><Slot Name=\"Open\"/></Wheel></Wheels><DMXModes><DMXMode Name=\"Basic\" Geometry=\"Root\"><DMXChannels>" +
            channel("Color1", "Palette", 1, "Head") + (entry.fx_first ? effect + subject : subject + effect) +
            "</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
        peraviz::archive::ZipArchive archive;
        if (!archive.open_create_or_modify(path) || !archive.write_file("description.xml", xml) || !archive.close()) return false;
        peraviz::SceneModel model;
        model.fixture_patches.push_back({"fixture", 1, 1, "Basic", path.string()});
        peraviz::SceneNode beam;
        beam.is_beam = true; beam.gdtf_geometry_path = "Root/Head/Output"; beam.gdtf_geometry_key = "fixture/Root/Head/Output";
        model.nodes.push_back(beam);
        const auto parsed = peraviz::gdtf_runtime::compile_gdtf_fixture_type(path.string(), "Basic");
        const auto compiled = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
        const auto expected = entry.missing ? ColorPresentationStatus::MissingWheelResource : ColorPresentationStatus::UnsupportedEffectApproximation;
        bool missing_diagnostic = false;
        for (const auto &diagnostic : compiled.diagnostics) if (diagnostic.code == "PVZ-COLOR-WHEEL-RESOURCE-MISSING") missing_diagnostic = true;
        bool exact_source = false;
        for (const auto &program : parsed.channel_programs) if (program.dmx_offsets_1_based == std::vector<int32_t>{3})
            exact_source = program.attribute_name == entry.attribute && program.wheel_reference == entry.link && program.dmx_from == 0 && program.dmx_to == 255;
        const bool ok = exact_source && parsed.channel_programs.size() == 3 && compiled.beam_profiles.size() == 1 &&
            compiled.beam_profiles[0].color_presentation_status == expected && missing_diagnostic == entry.missing &&
            !compiled.beam_profiles[0].approximated_color_source_programs.empty();
        std::error_code error;
        std::filesystem::remove(path, error);
        if (!ok) { std::cerr << "Color wheel ownership/status regression: " << entry.attribute << " link=" << entry.link << '\n'; return false; }
    }
    return true;
}

// Compiles a synthetic selected DMXMode rather than hand-authoring renderer group IDs.
bool test_control_group_compiler_inheritance() {
    const auto path = std::filesystem::temp_directory_path() / "peraviz_control_groups.gdtf";
    std::string geometries;
    for (int i = 0; i < 51; ++i) geometries += "<Beam Name=\"Output" + std::to_string(i) + "\"/>";
    const std::string xml = "<GDTF><FixtureType Name=\"Fixture\"><Geometries><Geometry Name=\"Root\">" + geometries +
        "</Geometry></Geometries><DMXModes><DMXMode Name=\"Global\" Geometry=\"Root\"><DMXChannels>"
        "<DMXChannel Offset=\"1\" Geometry=\"Root\"><LogicalChannel Attribute=\"Dimmer\"><ChannelFunction Attribute=\"Dimmer\" DMXFrom=\"0\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel></DMXChannel>"
        "<DMXChannel Offset=\"2\" Geometry=\"Root\"><LogicalChannel Attribute=\"ColorAdd_R\"><ChannelFunction Attribute=\"ColorAdd_R\" DMXFrom=\"0\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel></DMXChannel>"
        "</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
    peraviz::archive::ZipArchive archive;
    if (!archive.open_create_or_modify(path) || !archive.write_file("description.xml", xml) || !archive.close()) return false;
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"fixture", 1, 1, "Global", path.string()});
    for (int i = 0; i < 51; ++i) {
        peraviz::SceneNode beam;
        beam.is_beam = true;
        beam.gdtf_geometry_path = "Root/Output" + std::to_string(i);
        beam.gdtf_geometry_key = "fixture/" + beam.gdtf_geometry_path;
        beam.has_beam_type = true;
        beam.beam_type = i == 50 ? "None" : "Wash";
        model.nodes.push_back(beam);
    }
    const auto compiled = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    const auto groups = peraviz::presentation::compile_control_groups(compiled);
    std::set<int32_t> color_ids, sources;
    for (const auto &target : compiled.color_targets) {
        color_ids.insert(target.color_target_id);
        for (const auto &input : target.inputs) sources.insert(input.source_program_id);
    }
    const bool ok = compiled.beam_profiles.size() == 51 && color_ids.size() == 51 && sources.size() == 1 &&
        groups.size() == 2 && groups[0].physical_ids.size() == 50 && !compiled.beam_profiles.back().has_projected_beam;
    if (!ok) std::cerr << "Selected-mode inherited topology must group 50 distinct Color targets and preserve Aura\n";
    std::error_code error;
    std::filesystem::remove(path, error);
    return ok && test_color_wheel_resource_classification();
}
