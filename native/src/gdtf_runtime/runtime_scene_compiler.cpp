#include "gdtf_runtime/runtime_scene_compiler.h"

#include "dmx/fixture_dmx_binding.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <unordered_map>

namespace peraviz::gdtf_runtime {
namespace {

// Converts a SceneModel fixture patch into the DMX compiler input patch.
dmx::FixturePatch to_dmx_patch(const SceneModel::FixturePatch &patch) {
    dmx::FixturePatch out;
    out.fixture_uuid = patch.fixture_uuid;
    out.mvr_universe = patch.mvr_universe;
    out.mvr_address = patch.mvr_address;
    out.dmx_mode = patch.dmx_mode;
    out.gdtf_path = patch.gdtf_path;
    return out;
}

// Creates deterministic nonzero IDs from fixture UUID and semantic labels.
int32_t stable_id(const std::string &fixture_uuid, const char *label) {
    const std::size_t hash = std::hash<std::string>{}(fixture_uuid + ":" + label);
    return static_cast<int32_t>((hash % 2000000000U) + 1U);
}

// Appends valid channel bytes in coarse-to-fine order.
std::vector<runtime::CompiledDmxByteSource> make_sources(int universe_id, const dmx::FixtureAttributeChannel &channel) {
    std::vector<runtime::CompiledDmxByteSource> sources;
    if (channel.coarse_dmx_channel_index_0 >= 0) sources.push_back({universe_id, channel.coarse_dmx_channel_index_0, 0});
    if (channel.fine_dmx_channel_index_0 >= 0) sources.push_back({universe_id, channel.fine_dmx_channel_index_0, 1});
    if (channel.ultra_fine_dmx_channel_index_0 >= 0) sources.push_back({universe_id, channel.ultra_fine_dmx_channel_index_0, 2});
    return sources;
}

// Returns the maximum raw value for the compiled source byte width.
uint32_t max_for_sources(std::size_t source_count) {
    uint32_t max_value = 0;
    for (std::size_t index = 0; index < source_count && index < 4; ++index) {
        max_value = (max_value << 8U) | 0xffU;
    }
    return max_value;
}

// Adds one supported Dimmer/Pan/Tilt property when the attribute has at least one byte.
void add_property(runtime::CompiledRuntimeScene &scene,
                  int32_t &next_program_id,
                  const dmx::FixtureControlBinding &binding,
                  const char *label,
                  runtime::CompiledSemantic semantic,
                  const dmx::FixtureAttributeChannel &channel,
                  double physical_from,
                  double physical_to) {
    std::vector<runtime::CompiledDmxByteSource> sources = make_sources(binding.artnet_universe_id, channel);
    if (sources.empty()) {
        return;
    }
    if (sources.size() > 4) {
        scene.diagnostics.push_back({"PVZ-GDTF-UNSUPPORTED-BIT-DEPTH", "warning", "Runtime compiler supports up to 32-bit source values.", binding.fixture_uuid});
        sources.resize(4);
    }
    const int32_t program_id = next_program_id++;
    scene.source_programs.push_back({program_id, semantic, sources, 0, max_for_sources(sources.size()), physical_from, physical_to, label, label});
    const int32_t component_id = semantic == runtime::CompiledSemantic::Pan ? stable_id(binding.fixture_uuid, "pan") :
                                 semantic == runtime::CompiledSemantic::Tilt ? stable_id(binding.fixture_uuid, "tilt") :
                                 stable_id(binding.fixture_uuid, "dimmer-component");
    const int32_t render_target_id = semantic == runtime::CompiledSemantic::Dimmer ? stable_id(binding.fixture_uuid, "dimmer-target") : component_id;
    scene.properties.push_back({stable_id(binding.fixture_uuid, "fixture"), component_id, render_target_id, semantic, {{program_id, 1.0, runtime::CompiledContributorOperation::WeightedAdd}}});
}

} // namespace

// Compiles scene fixture patches and parser-owned GDTF control offsets into visual runtime programs.
runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset) {
    runtime::CompiledRuntimeScene out;
    std::vector<dmx::FixturePatch> patches;
    patches.reserve(scene.fixture_patches.size());
    for (const SceneModel::FixturePatch &patch : scene.fixture_patches) {
        patches.push_back(to_dmx_patch(patch));
    }
    std::unordered_map<std::string, dmx::FixtureControlBinding> lookup;
    const dmx::FixtureBindingBuildResult bindings = dmx::build_fixture_control_bindings(patches, universe_offset, lookup);
    for (const dmx::FixtureUnboundReason &unbound : bindings.unbound) {
        out.diagnostics.push_back({"PVZ-GDTF-FIXTURE-SKIPPED", "warning", unbound.reason, unbound.fixture_uuid});
    }
    int32_t next_program_id = 1;
    for (const dmx::FixtureControlBinding &binding : bindings.bindings) {
        const int32_t fixture_id = stable_id(binding.fixture_uuid, "fixture");
        out.fixtures.push_back({fixture_id, binding.fixture_uuid, "", "", binding.artnet_universe_id, 1, 10000.0, 25.0, 1.0, 20.0});
        const std::size_t property_start = out.properties.size();
        add_property(out, next_program_id, binding, "Dimmer", runtime::CompiledSemantic::Dimmer, binding.dimmer, 0.0, 1.0);
        add_property(out, next_program_id, binding, "Pan", runtime::CompiledSemantic::Pan, binding.pan, -270.0, 270.0);
        add_property(out, next_program_id, binding, "Tilt", runtime::CompiledSemantic::Tilt, binding.tilt, -135.0, 135.0);
        if (out.properties.size() == property_start) {
            out.diagnostics.push_back({"PVZ-GDTF-NO-SUPPORTED-PROPERTIES", "warning", "Fixture has no supported Dimmer/Pan/Tilt runtime properties.", binding.fixture_uuid});
        }
    }
    return out;
}

} // namespace peraviz::gdtf_runtime
