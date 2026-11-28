#include "peraviz_loader.h"
#include "document/mvr_document_godot.h"
#include "runtime/peraviz_visual_runtime_godot.h"

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
// Stage a canonical command and its renderer manifest before any installed state changes.
Dictionary PeravizLoader::stage_document_mode(const Ref<PeravizMvrDocument> &document,
                                              const String &uuid, const String &name, int offset) {
    cancel_document_mode();
    Dictionary result;
    result["ok"] = false;
    const auto reject = [&](const std::string &reason) {
        result["error"] = String::utf8(reason.c_str());
        if (document.is_valid()) document->cancel();
        return result;
    };
    if (document.is_null() || !prepared_ || preparation_.valid())
        return reject("A canonical fixture scene must be installed.");
    auto &source = document->document_;
    std::error_code error;
    if (!std::filesystem::equivalent(source.import_snapshot(), std::filesystem::u8path(last_scene_model_.source_path), error))
        return reject("The document no longer matches the installed scene.");

    const bool history = source.pending_mode();
    const std::string id = history ? source.pending().front().uuid : uuid.utf8().get_data();
    const std::string target = history ? source.pending().front().mode_after.name : name.utf8().get_data();
    const auto *patch = fixture_patch(last_scene_model_, id);
    const auto *fixture = source.fixture(id);
    if (!patch || !fixture || fixture->current_mode.name != patch->dmx_mode)
        return reject("The document fixture does not match the installed mode.");
    if (!history && target == patch->dmx_mode && fixture->current_mode.present) {
        result["ok"] = true;
        result["unchanged"] = true;
        return result;
    }
    const auto &catalog = mode_catalog(patch->gdtf_path);
    const auto supported = [&](const std::string &mode) {
        return std::any_of(catalog.modes.begin(), catalog.modes.end(), [&](const auto &entry) {
            return entry.name == mode && entry.semantic_supported;
        });
    };
    if (!fixture->current_mode.present || !supported(patch->dmx_mode))
        return reject("The current mode is unavailable. Its presentation cannot be restored by Undo.");
    if (!history && !source.prepare_mode(id, target, [&](const auto &, const auto &proposed) -> std::string {
            const auto found = std::find_if(catalog.modes.begin(), catalog.modes.end(), [&](const auto &entry) {
                return entry.name == proposed;
            });
            if (found == catalog.modes.end()) return "The requested mode is absent from the referenced GDTF.";
            return found->semantic_supported ? std::string{} : found->diagnostic;
        }))
        return reject(source.error());

    peraviz::gdtf_runtime::RuntimeRoutingOptions routing;
    routing.policy = peraviz::gdtf_runtime::parse_auto_span_policy(auto_span_policy_);
    const auto &installed = prepared_->compiled;
    if (std::none_of(installed.fixtures.begin(), installed.fixtures.end(), [&](const auto &row) {
            return row.fixture_uuid == id;
        }))
        return reject("The current fixture has no installed native mode. Undo would be unavailable.");
    auto candidate = peraviz::gdtf_runtime::prepare_fixture_mode(last_scene_model_, id, target, catalog,
        model_detail_, offset, routing, *prepared_->fixture_types);
    if (!candidate.error.empty()) return reject(candidate.error);
    const auto compiled_fixture = std::find_if(candidate.compiled.fixtures.begin(), candidate.compiled.fixtures.end(),
        [&](const auto &row) { return row.fixture_uuid == id; });
    if (compiled_fixture == candidate.compiled.fixtures.end())
        return reject("The target fixture did not compile into the native runtime.");
    const auto fixture_id = compiled_fixture->fixture_id;
    auto runtime_plan = std::make_shared<peraviz::runtime::PeravizVisualRuntimeCore>();
    runtime_plan->install_compiled_scene(candidate.compiled);
    if (!runtime_plan->has_fixture_controls(fixture_id))
        return reject("The runtime could not install the selected mode's controls.");
    auto payload = serialize_compiled_scene(candidate.compiled, offset, candidate.controls, candidate.groups, false);
    const Array fixture_results = payload["fixture_compilation_results"];
    for (int64_t i = 0; i < fixture_results.size(); ++i) {
        Dictionary row = fixture_results[i];
        if (String(row["fixture_uuid"]) == String::utf8(id.c_str()))
            row["dmx_mode"] = String::utf8(target.c_str());
    }
    result["ok"] = true;
    result["fixture_uuid"] = String::utf8(id.c_str());
    result["geometry"] = serialize_node_records(candidate.geometry.nodes);
    result["reuse_geometry"] = candidate.reuse_geometry;
    result["payload"] = payload;
    Array warnings;
    for (const auto &warning : candidate.warnings) warnings.push_back(String::utf8(warning.c_str()));
    result["warnings"] = warnings;
    staged_mode_.emplace(StagedMode{document, std::move(candidate), payload, std::move(runtime_plan),
                                    fixture_id, source.revision(), offset, auto_span_policy_});
    return result;
}

// Cancel the command and release its uninstalled resource lease.
void PeravizLoader::cancel_document_mode() {
    if (staged_mode_) staged_mode_->document->cancel();
    staged_mode_.reset();
}

// Publish the validated runtime, document and loader projection under exclusive presentation ownership.
bool PeravizLoader::commit_document_mode(const Ref<PeravizMvrDocument> &document,
                                         const Ref<PeravizVisualRuntime> &runtime) {
    if (!staged_mode_ || staged_mode_->document != document || runtime.is_null() ||
        !runtime->async_available() || staged_mode_->policy != auto_span_policy_ || !document->pending_mode())
        return false;
    auto &stage = *staged_mode_;
    auto &candidate = stage.candidate;
    const auto &command = document->document_.pending().front();
    const auto &id = candidate.patch.fixture_uuid;
    if (document->document_.revision() != stage.document_revision ||
        command.uuid != id || command.mode_after.name != candidate.patch.dmx_mode) return false;
    if (!runtime->replace_mode_plan(stage.runtime_plan, candidate.compiled, stage.fixture_id, stage.payload))
        return false;
    document->document_.commit();
    for (auto &patch : last_scene_model_.fixture_patches)
        if (patch.fixture_uuid == id) patch = candidate.patch;
    auto table = last_scene_model_.runtime_tables.find("fixtures");
    if (table != last_scene_model_.runtime_tables.end()) table->second.set_cell(id, 7, candidate.patch.dmx_mode);
    if (!candidate.reuse_geometry) {
        auto &nodes = last_scene_model_.nodes;
        nodes.erase(std::remove_if(nodes.begin(), nodes.end(), [&](const auto &node) {
            return node.gdtf_fixture_uuid == id;
        }), nodes.end());
        nodes.insert(nodes.end(), std::make_move_iterator(candidate.geometry.nodes.begin()),
                     std::make_move_iterator(candidate.geometry.nodes.end()));
        last_scene_model_.asset_leases.retain(candidate.geometry.cache_lease);
    }
    prepared_->compiled = std::move(candidate.compiled);
    prepared_->controls = std::move(candidate.controls);
    prepared_->groups = std::move(candidate.groups);
    prepared_->universe_offset = stage.universe_offset;
    prepared_->auto_span_policy = peraviz::gdtf_runtime::parse_auto_span_policy(stage.policy);
    staged_mode_.reset();
    return true;
}
} // namespace godot
