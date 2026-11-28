#include "gdtf_runtime/fixture_mode_preparation.h"

#include "gdtf_runtime/resolved_dmx_addresses.h"
#include "matrixutils.h"
#include "scene_setup_options.h"
#include <algorithm>
#include <set>

namespace peraviz::gdtf_runtime {
namespace {
// Resolve the exact authored mode identity after the catalog has counted duplicates.
const GdtfModeInfo *find_mode(const GdtfModeCatalog &catalog, const std::string &name) {
    const auto mode = std::find_if(catalog.modes.begin(), catalog.modes.end(),
                                  [&](const auto &item) { return item.name == name; });
    return mode == catalog.modes.end() ? nullptr : &*mode;
}

// Render/semantic diagnostics can name either the canonical UUID or an extended source identity.
bool for_fixture(const runtime::CompiledRuntimeDiagnostic &diagnostic, const std::string &uuid) {
    return diagnostic.subject == uuid || diagnostic.subject.rfind(uuid + " ", 0) == 0;
}

// Map a footprint start into absolute MVR slot coordinates for co-patch diagnostics.
int64_t first_slot(const SceneModel::FixturePatchAddress &address) {
    return (int64_t(address.universe) - 1) * 512 + address.address - 1;
}
} // namespace

// Prepare fixture-local geometry and real runtime programs while the installed scene stays untouched.
FixtureModePreparation prepare_fixture_mode(
    const SceneModel &scene, const std::string &uuid, const std::string &name,
    const GdtfModeCatalog &catalog, GdtfModelDetail detail, int universe_offset,
    const RuntimeRoutingOptions &routing, FixtureTypeCache &cache) {
    FixtureModePreparation out;
    const auto fixture = std::find_if(scene.fixture_patches.begin(), scene.fixture_patches.end(),
                                     [&](const auto &patch) { return patch.fixture_uuid == uuid; });
    if (fixture == scene.fixture_patches.end()) {
        out.error = "Fixture UUID is absent from the imported scene.";
        return out;
    }
    out.patch = *fixture;
    if (name == fixture->dmx_mode) {
        out.unchanged = true;
        return out;
    }
    const auto *target = find_mode(catalog, name);
    if (!target || !target->semantic_supported) {
        out.error = target ? target->diagnostic : "The exact mode name is absent from the referenced GDTF.";
        return out;
    }
    if (!fixture->dmx_import_error.empty()) {
        out.error = fixture->dmx_import_error;
        return out;
    }
    bool overflow = false;
    for (const auto &[number, footprint] : target->break_footprints) {
        const auto address = source_patch(*fixture, number);
        if (address.universe < 1 || address.address < 1 || address.address > 512) {
            if (out.error.empty()) out.error = "Missing authored MVR break assignments:";
            out.error += " " + std::to_string(number - 1);
            continue;
        }
        overflow |= int64_t(address.address) + footprint - 1 > 512;
    }
    if (!out.error.empty()) return out;

    const auto root = std::find_if(scene.nodes.begin(), scene.nodes.end(),
                                   [&](const auto &node) { return node.node_id == uuid && node.is_fixture; });
    if (root == scene.nodes.end()) {
        out.error = "Canonical fixture has no scene root.";
        return out;
    }
    const auto *current = find_mode(catalog, fixture->dmx_mode);
    const auto generated = [&](const auto &node) { return node.gdtf_fixture_uuid == uuid; };
    out.reuse_geometry = current && current->semantic_supported && current->geometry == target->geometry &&
                         std::any_of(scene.nodes.begin(), scene.nodes.end(), generated);
    SceneModel candidate;
    candidate.fixture_patches = scene.fixture_patches;
    const auto index = std::distance(scene.fixture_patches.begin(), fixture);
    out.patch.dmx_mode = name;
    candidate.fixture_patches[index] = out.patch;
    candidate.nodes = scene.nodes;
    if (!out.reuse_geometry) {
        int extracted = 0;
        const GdtfBuildRequest request{fixture->gdtf_path, name, uuid, root->name, detail};
        out.geometry = build_fixture_geometry_nodes(request, uuid, MatrixUtils::Identity(), extracted);
        if (!out.geometry.error.empty() || out.geometry.nodes.empty()) {
            out.error = "Target geometry could not be built (" + out.geometry.error + ").";
            return out;
        }
        candidate.nodes.erase(std::remove_if(candidate.nodes.begin(), candidate.nodes.end(), generated),
                              candidate.nodes.end());
        candidate.nodes.insert(candidate.nodes.end(), out.geometry.nodes.begin(), out.geometry.nodes.end());
    }

    out.compiled = compile_runtime_scene(candidate, universe_offset, routing, &cache);
    for (const auto &diagnostic : out.compiled.diagnostics) {
        if (diagnostic.code == "PVZ-RUNTIME-ID-COLLISION") {
            out.error = diagnostic.message;
            return out;
        }
        if (!for_fixture(diagnostic, uuid)) continue;
        if (diagnostic.severity == "error" || diagnostic.code == "PVZ-DMX-STRICT-OMITTED-SUMMARY") {
            out.error = diagnostic.message;
            return out;
        }
        if (diagnostic.severity == "warning") out.warnings.push_back(diagnostic.message);
    }
    const auto compiled_fixture = std::find_if(out.compiled.fixtures.begin(), out.compiled.fixtures.end(),
        [&](const auto &item) { return item.fixture_uuid == uuid; });
    if (compiled_fixture == out.compiled.fixtures.end()) {
        out.error = "The target mode could not be bound to the existing DMX patch.";
        return out;
    }
    const auto &type = cached_fixture_type(out.patch, cache);
    const auto id = compiled_fixture->fixture_id;
    std::set<int32_t> active_sources;
    for (const auto &property : out.compiled.properties)
        if (property.fixture_id == id)
            for (const auto &input : property.contributors) active_sources.insert(input.source_program_id);
    for (const auto &color : out.compiled.color_targets)
        if (color.fixture_id == id)
            for (const auto &input : color.inputs) active_sources.insert(input.source_program_id);
    const auto collect = [&](const auto &bindings) {
        for (const auto &binding : bindings)
            if (binding.fixture_id == id) active_sources.insert(binding.source_program_id);
    };
    collect(out.compiled.wheel_bindings);
    collect(out.compiled.gobo_bindings);
    collect(out.compiled.gobo_motion_bindings);
    collect(out.compiled.shutter_bindings);
    if (active_sources.empty()) {
        out.error = "The target mode has no complete native controls under the existing patch.";
        return out;
    }
    std::set<int32_t> compiled_programs;
    for (const auto &program : out.compiled.source_programs)
        if (active_sources.count(program.program_id)) compiled_programs.insert(program.parser_program_id);
    std::set<std::string> unsupported;
    for (const auto &program : type.channel_programs)
        if (!compiled_programs.count(program.id)) unsupported.insert(program.attribute_name);
    for (const auto &attribute : unsupported)
        out.warnings.push_back("No compiled visualization for " + attribute + ".");
    if (overflow) out.warnings.push_back("The new footprint crosses slot 512 under the current Auto Span policy.");

    bool overlaps = false;
    for (const auto &other : scene.fixture_patches) {
        if (other.fixture_uuid == uuid || other.gdtf_path.empty() || other.dmx_mode.empty()) continue;
        const auto &other_type = cached_fixture_type(other, cache);
        for (const auto &program : other_type.channel_programs) {
            const auto other_address = source_patch(other, program.dmx_break);
            if (other_address.universe < 1 || other_address.address < 1) continue;
            for (const auto &[number, footprint] : target->break_footprints) {
                const auto start = first_slot(source_patch(*fixture, number));
                for (const int offset : program.dmx_offsets_1_based) {
                    const auto slot = first_slot(other_address) + offset - 1;
                    overlaps |= slot >= start && slot < start + footprint;
                }
            }
        }
        if (overlaps) break;
    }
    if (overlaps) out.warnings.push_back("Potential overlap with another fixture's authored DMX patch.");

    const bool indexed = SceneSetupOptions::read().indexed_classification;
    out.controls = presentation::analyze_control_groups(out.compiled, indexed);
    out.groups = presentation::compile_render_emitter_groups(out.compiled, candidate, out.controls.groups, indexed);
    return out;
}

} // namespace peraviz::gdtf_runtime
