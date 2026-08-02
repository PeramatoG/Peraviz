#include "archive/zip_archive.h"
#include "dmx/fixture_dmx_binding.h"
#include "dmx/gdtf_control_offsets_resolver.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "mvr_scene_loader.h"
#include "runtime_storage.h"
#include "scene_model.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

// Reports one lifetime regression failure.
int fail(const std::string &message) {
    std::cerr << message << "\n";
    return 1;
}

// Reads one generated archive into a binary string.
std::string read_binary(const std::filesystem::path &path) {
    std::ifstream input(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

// Builds a minimal valid GLB containing an empty glTF scene.
std::string minimal_glb() {
    std::string json = R"({"asset":{"version":"2.0"},"scene":0,"scenes":[{}]})";
    while ((json.size() % 4U) != 0U) json.push_back(' ');
    const uint32_t total_length = static_cast<uint32_t>(12U + 8U + json.size());
    std::string bytes;
    auto append_u32 = [&bytes](uint32_t value) {
        for (int shift = 0; shift < 32; shift += 8) bytes.push_back(static_cast<char>((value >> shift) & 0xffU));
    };
    append_u32(0x46546c67U);
    append_u32(2U);
    append_u32(total_length);
    append_u32(static_cast<uint32_t>(json.size()));
    append_u32(0x4e4f534aU);
    bytes += json;
    return bytes;
}

// Writes one media- and model-bearing GDTF archive for scene lifetime tests.
bool write_gdtf(const std::filesystem::path &path, const std::string &suffix) {
    const std::string xml = "<GDTF><FixtureType Name=\"Lease Fixture " + suffix +
        "\"><Models><Model Name=\"BaseModel\" File=\"base\"/><Model Name=\"YokeModel\" File=\"yoke\"/>"
        "</Models><Geometries><Geometry Name=\"Root\" Model=\"BaseModel\"><Axis Name=\"Yoke\" Model=\"YokeModel\">"
        "<Beam Name=\"Beam\" LuminousFlux=\"1000\" BeamAngle=\"20\"/></Axis></Geometry></Geometries>"
        "<Wheels><Wheel Name=\"Gobo Wheel\"><Slot Name=\"Open\"/><Slot Name=\"Star\" MediaFileName=\"star\"/></Wheel></Wheels>"
        "<DMXModes><DMXMode Name=\"Mode @ Main\" Geometry=\"Root\"><DMXChannels><DMXChannel Offset=\"1\" Geometry=\"Beam\">"
        "<LogicalChannel Attribute=\"Dimmer\"><ChannelFunction Attribute=\"Dimmer\" DMXFrom=\"0\" DMXTo=\"255\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/>"
        "</LogicalChannel></DMXChannel><DMXChannel Offset=\"2\" Geometry=\"Beam\"><LogicalChannel Attribute=\"Gobo1\">"
        "<ChannelFunction Attribute=\"Gobo1\" Wheel=\"Gobo Wheel\"><ChannelSet DMXFrom=\"0\" WheelSlotIndex=\"1\"/>"
        "<ChannelSet DMXFrom=\"128\" WheelSlotIndex=\"2\"/></ChannelFunction></LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes>"
        "</FixtureType></GDTF>";
    static const unsigned char png[] = {
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
        0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
        0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4e, 0x44, 0xae, 0x42, 0x60, 0x82};
    peraviz::archive::ZipArchive archive;
    return archive.open_create_or_modify(path) && archive.write_file("description.xml", xml) &&
           archive.write_file("models/gltf/base.glb", minimal_glb()) &&
           archive.write_file("models/gltf/yoke.glb", minimal_glb()) &&
           archive.write_file("wheels/star.png", std::string(reinterpret_cast<const char *>(png), sizeof(png))) && archive.close();
}

// Writes an MVR containing two instances of one embedded GDTF archive.
bool write_mvr(const std::filesystem::path &path, const std::filesystem::path &gdtf_path) {
    const std::string spec = gdtf_path.filename().u8string();
    const std::string xml = "<GeneralSceneDescription><Scene><Layers><Layer uuid=\"layer\"><ChildList>"
        "<Fixture uuid=\"fixture-one\" name=\"One\" Universe=\"1\" Address=\"1\"><GDTFSpec>" + spec + "</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture>"
        "<Fixture uuid=\"fixture-two\" name=\"Two\" Universe=\"1\" Address=\"20\"><GDTFSpec>" + spec + "</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture>"
        "</ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
    peraviz::archive::ZipArchive archive;
    return archive.open_create_or_modify(path) && archive.write_file("GeneralSceneDescription.xml", xml) &&
           archive.write_file(spec, read_binary(gdtf_path)) && archive.close();
}

// Returns all non-empty extracted model paths in one scene.
std::vector<std::filesystem::path> model_paths(const peraviz::SceneModel &scene) {
    std::vector<std::filesystem::path> paths;
    for (const peraviz::SceneNode &node : scene.nodes) {
        if (!node.asset_path.empty()) paths.push_back(std::filesystem::u8path(node.asset_path));
    }
    return paths;
}

// Verifies the scene lease set deduplicates shared directories and releases the final owner.
int test_scene_lease_set_deduplication() {
    std::filesystem::path path;
    peraviz::SceneAssetLeaseSet owner;
    {
        auto first = peraviz::runtime_storage::acquire_session_cache_directory("lease-set @ ä");
        auto second = peraviz::runtime_storage::acquire_session_cache_directory("lease-set @ ä");
        path = first.path();
        std::ofstream(path / "marker") << "owned";
        owner.retain(first);
        owner.retain(second);
        if (owner.size() != 1 || !owner.owns(path / "marker")) return fail("Scene lease set did not deduplicate a shared content directory");
    }
    if (!std::filesystem::exists(path / "marker")) return fail("Scene lease set did not retain the final strong lease");
    owner.clear();
    if (std::filesystem::exists(path)) return fail("Scene lease set did not release its directory deterministically");
    return 0;
}

// Verifies fixture models and gobos remain alive through every active-scene setup boundary.
int test_mvr_gdtf_active_scene_lifetime(const std::filesystem::path &root) {
    const std::filesystem::path source = root / "source with spaces @ ü";
    std::filesystem::create_directories(source);
    const std::filesystem::path first_gdtf = source / "Fixture @ long ü name.gdtf";
    const std::filesystem::path first_mvr = source / "Scene one.mvr";
    if (!write_gdtf(first_gdtf, "one") || !write_mvr(first_mvr, first_gdtf)) return fail("Failed to create the first lifetime fixture archives");

    peraviz::SceneModel active = peraviz::load_mvr(first_mvr.u8string(), false, false);
    const std::vector<std::filesystem::path> first_models = model_paths(active);
    if (active.fixture_patches.size() != 2 || first_models.size() < 4 || active.asset_leases.size() != 2) return fail("The active scene did not retain one MVR cache and one shared GDTF cache");
    std::filesystem::path first_cache;
    for (const auto &path : first_models) {
        if (!std::filesystem::is_regular_file(path) || !active.asset_leases.owns(path)) return fail("A fixture model path was not backed by the active scene owner");
        if (first_cache.empty()) first_cache = path.parent_path().parent_path().parent_path();
    }

    std::vector<peraviz::dmx::FixturePatch> binding_patches;
    for (const auto &patch : active.fixture_patches) binding_patches.push_back({patch.fixture_uuid, patch.mvr_universe, patch.mvr_address, patch.dmx_mode, patch.gdtf_path});
    std::unordered_map<std::string, peraviz::dmx::FixtureControlBinding> lookup;
    { const auto bindings = peraviz::dmx::build_fixture_control_bindings(binding_patches, 0, lookup); if (bindings.bindings.size() != 2) return fail("Fixture compatibility binding setup failed"); }
    peraviz::dmx::clear_fixture_control_offsets_cache();
    for (const auto &path : first_models) if (!std::filesystem::exists(path)) return fail("Legacy binding cleanup released active geometry");

    std::string gobo_path;
    {
        const auto compiled = peraviz::gdtf_runtime::compile_runtime_scene(active, 0);
        for (const auto &asset : compiled.gobo_assets) if (asset.gobo_asset_id > 0) gobo_path = asset.extracted_media_path;
        if (gobo_path.empty() || !std::filesystem::is_regular_file(std::filesystem::u8path(gobo_path))) return fail("Compiled native gobo path was not live");
    }
    for (const auto &path : first_models) if (!std::filesystem::exists(path)) return fail("Temporary compiled scene released active geometry");
    if (!std::filesystem::exists(std::filesystem::u8path(gobo_path))) return fail("Temporary compiled scene released active gobo media");

    const std::filesystem::path second_gdtf = source / "Replacement @ fixture.gdtf";
    const std::filesystem::path second_mvr = source / "Scene replacement.mvr";
    if (!write_gdtf(second_gdtf, "replacement") || !write_mvr(second_mvr, second_gdtf)) return fail("Failed to create replacement fixture archives");
    active = peraviz::load_mvr(second_mvr.u8string(), false, false);
    const auto second_models = model_paths(active);
    if (second_models.empty()) return fail("Replacement scene did not extract fixture models");
    for (const auto &path : second_models) if (!std::filesystem::exists(path)) return fail("Replacement scene path was stale");
    if (std::filesystem::exists(first_cache)) return fail("Replacing the scene did not release the old GDTF cache");
    std::filesystem::path second_cache;
    for (const auto &path : active.asset_leases.paths()) if (path != std::filesystem::u8path(active.cache_path)) second_cache = path;
    active = {};
    if (std::filesystem::exists(second_cache)) return fail("Clearing the scene did not release the replacement GDTF cache");
    return 0;
}

} // namespace

// Runs active-scene extraction ownership regressions in an isolated runtime root.
int main() {
    const std::filesystem::path root = std::filesystem::temp_directory_path() / "peraviz_scene_asset_lifetime_test";
    std::filesystem::remove_all(root);
    peraviz::runtime_storage::set_runtime_root_for_tests(root / "runtime");
    if (const int result = test_scene_lease_set_deduplication(); result != 0) return result;
    if (const int result = test_mvr_gdtf_active_scene_lifetime(root); result != 0) return result;
    peraviz::runtime_storage::cleanup_current_session();
    peraviz::runtime_storage::reset_runtime_root_for_tests();
    std::filesystem::remove_all(root);
    return 0;
}
