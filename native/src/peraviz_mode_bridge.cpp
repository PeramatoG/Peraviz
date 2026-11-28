#include "peraviz_loader.h"

#include "gdtf_runtime/fixture_mode_preparation.h"
#include <algorithm>

namespace godot {
namespace {
// Keep the scene fixture association by UUID, independent of the Inspector's selection label.
const peraviz::SceneModel::FixturePatch *fixture_patch(const peraviz::SceneModel &scene,
                                                        const std::string &id) {
    const auto found = std::find_if(scene.fixture_patches.begin(), scene.fixture_patches.end(),
                                    [&](const auto &patch) { return patch.fixture_uuid == id; });
    return found == scene.fixture_patches.end() ? nullptr : &*found;
}
} // namespace

// Scene extraction paths refer to immutable leased archive versions. Clear this cache on import.
const peraviz::gdtf_runtime::GdtfModeCatalog &PeravizLoader::mode_catalog(const std::string &path) {
    const auto found = mode_catalogs_.find(path);
    if (found != mode_catalogs_.end()) return found->second;
    return mode_catalogs_.emplace(path, peraviz::gdtf_runtime::read_gdtf_mode_catalog(path)).first->second;
}

// Publish exact mode metadata. Parser eligibility is distinct from presentation installation.
Dictionary PeravizLoader::document_mode_catalog(const String &uuid) {
    Dictionary result;
    Array modes;
    const auto *patch = fixture_patch(last_scene_model_, uuid.utf8().get_data());
    if (!patch || preparation_.valid()) {
        result["diagnostic"] = "Fixture is unavailable in the current imported scene.";
        result["modes"] = modes;
        return result;
    }
    result["current_mode"] = String::utf8(patch->dmx_mode.c_str());
    const auto &catalog = mode_catalog(patch->gdtf_path);
    bool current_available = false;
    for (const auto &mode : catalog.modes) {
        current_available |= mode.name == patch->dmx_mode && mode.semantic_supported;
        Dictionary row;
        row["name"] = String::utf8(mode.name.c_str());
        row["description"] = String::utf8(mode.description.c_str());
        row["geometry"] = String::utf8(mode.geometry.c_str());
        row["diagnostic"] = String::utf8(mode.diagnostic.c_str());
        row["semantic_supported"] = mode.semantic_supported;
        row["footprint_known"] = mode.footprint_known;
        Array breaks;
        for (const auto &[number, footprint] : mode.break_footprints) {
            Dictionary entry;
            entry["break"] = number - 1;
            entry["footprint"] = footprint;
            breaks.push_back(entry);
        }
        row["breaks"] = breaks;
        modes.push_back(row);
    }
    result["current_available"] = current_available;
    result["fixture_name"] = String::utf8(catalog.fixture_name.c_str());
    result["diagnostic"] = String::utf8(catalog.diagnostic.c_str());
    result["modes"] = modes;
    return result;
}

// Preview native semantic and geometry feasibility without publishing a document or renderer change.
Dictionary PeravizLoader::preview_document_mode(const String &uuid, const String &mode, int universe_offset) {
    Dictionary result;
    result["ok"] = false;
    const auto *patch = fixture_patch(last_scene_model_, uuid.utf8().get_data());
    if (!patch || preparation_.valid()) {
        result["error"] = "Fixture is unavailable in the current imported scene.";
        return result;
    }
    if (mode == String::utf8(patch->dmx_mode.c_str())) {
        result["ok"] = true;
        result["unchanged"] = true;
        return result;
    }
    peraviz::gdtf_runtime::FixtureTypeCache local_cache;
    peraviz::gdtf_runtime::RuntimeRoutingOptions routing;
    routing.policy = peraviz::gdtf_runtime::parse_auto_span_policy(auto_span_policy_);
    const auto candidate = peraviz::gdtf_runtime::prepare_fixture_mode(
        last_scene_model_, patch->fixture_uuid, mode.utf8().get_data(), mode_catalog(patch->gdtf_path),
        model_detail_, universe_offset, routing, prepared_ ? *prepared_->fixture_types : local_cache);
    result["ok"] = candidate.error.empty();
    result["error"] = String::utf8(candidate.error.c_str());
    result["reuse_geometry"] = candidate.reuse_geometry;
    result["unchanged"] = candidate.unchanged;
    result["geometry_node_count"] = int64_t(candidate.geometry.nodes.size());
    Array warnings;
    for (const auto &warning : candidate.warnings) warnings.push_back(String::utf8(warning.c_str()));
    result["warnings"] = warnings;
    return result;
}
} // namespace godot
