#include "archive/zip_archive.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "presentation/control_groups.h"
#include <filesystem>
#include <iostream>
#include <set>

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
    return ok;
}
