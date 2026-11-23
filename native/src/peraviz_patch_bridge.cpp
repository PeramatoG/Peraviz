#include "dmx/addressing_fields.h"
#include "gdtf_runtime/resolved_dmx_addresses.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "peraviz_loader.h"
#include "runtime/compiled_runtime_scene_codec.h"
#include "runtime/peraviz_visual_runtime_godot.h"
#include <algorithm>
#include <godot_cpp/classes/ref.hpp>
#include <set>
namespace godot {
namespace {
// Publish bounded parser-derived break footprints; unknown types never receive invented widths.
std::map<int, int> widths(const peraviz::gdtf_runtime::CompiledGdtfFixtureType &type) {
    std::map<int, int> result;
    for (const auto &program : type.channel_programs)
        for (int offset : program.dmx_offsets_1_based)
            result[program.dmx_break - 1] = std::max(result[program.dmx_break - 1], offset);
    return result;
}
// Ensure a patch transaction changes byte routing only, preserving all installed presentation identities.
bool same_topology(const peraviz::runtime::CompiledRuntimeScene &before,
                   peraviz::runtime::CompiledRuntimeScene after) {
    if (before.fixtures.size() != after.fixtures.size() ||
        before.source_programs.size() != after.source_programs.size())
        return false;
    for (size_t i = 0; i < before.fixtures.size(); ++i) {
        if (before.fixtures[i].fixture_id != after.fixtures[i].fixture_id)
            return false;
        after.fixtures[i].universe_id = before.fixtures[i].universe_id;
        after.fixtures[i].start_address = before.fixtures[i].start_address;
    }
    for (size_t i = 0; i < before.source_programs.size(); ++i) {
        if (before.source_programs[i].program_id != after.source_programs[i].program_id)
            return false;
        after.source_programs[i].sources = before.source_programs[i].sources;
    }
    const auto a = peraviz::runtime::encode_compiled_runtime_scene(before),
               b = peraviz::runtime::encode_compiled_runtime_scene(after);
    return a.integers == b.integers && a.floats == b.floats;
}
} // namespace
// Read cached selected-mode capabilities, separately from authoritative document values and Auto Span.
Dictionary PeravizLoader::document_patch_info(const String &uuid) {
    Dictionary out;
    out["editable"] = false;
    out["reason"] = "Selected GDTF mode is unavailable";
    const std::string id = uuid.utf8().get_data();
    auto found =
        std::find_if(last_scene_model_.fixture_patches.begin(), last_scene_model_.fixture_patches.end(),
                     [&](const auto &p) { return p.fixture_uuid == id; });
    if (found == last_scene_model_.fixture_patches.end() || !prepared_ || found->gdtf_path.empty() ||
        found->dmx_mode.empty())
        return out;
    const auto &type = peraviz::gdtf_runtime::cached_fixture_type(*found, *prepared_->fixture_types);
    if (!type.dmx_patch_supported || type.channel_programs.empty() || type.dmx_mode_name.empty()) {
        out["reason"] = "Selected GDTF mode has unsupported source routing";
        return out;
    }
    Array breaks;
    for (const auto &[number, width] : widths(type)) {
        Dictionary row;
        row["break"] = number;
        row["footprint"] = width;
        breaks.push_back(row);
    }
    out["breaks"] = breaks;
    const bool installed =
        std::any_of(prepared_->compiled.fixtures.begin(), prepared_->compiled.fixtures.end(),
                    [&](const auto &fixture) { return fixture.fixture_uuid == id; });
    if (!installed) {
        out["reason"] = "No installed native fixture plan (unpatched/incomplete or unsupported mode). "
                        "Patch-only editing preserves existing renderer topology; complete required source "
                        "assignments externally and reopen.";
        return out;
    }

    out["editable"] = true;
    out["reason"] = "";
    return out;
}
// Compile a proposed authored patch using cached GDTF types, without importing geometry or publishing
// metadata.
Dictionary PeravizLoader::stage_document_patch(const String &uuid, const Array &entries,
                                               int universe_offset) {
    staged_patch_.reset();
    Dictionary out;
    out["ok"] = false;
    const std::string id = uuid.utf8().get_data();
    const auto fail = [&](const std::string &message) {
        out["error"] = String::utf8(("Fixture " + id + ": " + message).c_str());
        return out;
    };
    auto info = document_patch_info(uuid);
    if (!bool(info["editable"]))
        return fail(String(info["reason"]).utf8().get_data());
    auto found =
        std::find_if(last_scene_model_.fixture_patches.begin(), last_scene_model_.fixture_patches.end(),
                     [&](const auto &p) { return p.fixture_uuid == id; });
    auto proposed = *found;
    proposed.addresses.clear();
    proposed.mvr_universe = proposed.mvr_address = -1;
    std::set<int> seen;
    for (int64_t i = 0; i < entries.size(); ++i) {
        Dictionary row = entries[i];
        const int number = int(row.get("break", -1)), universe = int(row.get("universe", 0)),
                  address = int(row.get("address", 0));
        if (number < 0 || !seen.insert(number).second || universe < 1 || universe > 32768 || address < 1 ||
            address > 512)
            return fail("Invalid or duplicate canonical break assignment");
        proposed.addresses.push_back(
            {number, universe, address, int(i), bool(row.get("explicit_break", true))});
        if (number == 0) {
            proposed.mvr_universe = universe;
            proposed.mvr_address = address;
        }
    }
    if (proposed.addresses.empty())
        return fail("Removing the last assignment would unbind the fixture; a routing-only transaction "
                    "cannot retire its renderer plan");
    peraviz::gdtf_runtime::RuntimeRoutingOptions routing;
    routing.policy = peraviz::gdtf_runtime::parse_auto_span_policy(auto_span_policy_);
    const auto before = peraviz::gdtf_runtime::compile_runtime_scene(last_scene_model_, universe_offset,
                                                                     routing, prepared_->fixture_types.get());
    if (std::none_of(before.fixtures.begin(), before.fixtures.end(),
                     [&](const auto &fixture) { return fixture.fixture_uuid == id; }))
        return fail(
            "No installed fixture controls under the current Auto Span policy; no edit was committed");
    const auto previous = *found;
    *found = proposed;
    // Restore source metadata even if compilation throws; no staged operation owns the live model yet.
    struct Restore {
        peraviz::SceneModel::FixturePatch &target;
        peraviz::SceneModel::FixturePatch value;
        // Restore live metadata on every staging return path.
        ~Restore() { target = std::move(value); }
    } restore{*found, previous};
    auto candidate = peraviz::gdtf_runtime::compile_runtime_scene(last_scene_model_, universe_offset, routing,
                                                                  prepared_->fixture_types.get());
    for (const auto &d : candidate.diagnostics)
        if (d.severity == "error" && d.subject.rfind(id, 0) == 0)
            return fail(d.message);
    if (!same_topology(before, candidate))
        return fail("The proposed patch changes installed control topology (unpatched/missing breaks or Auto "
                    "Span fallback). Complete required assignments externally or choose a supported "
                    "address/policy; no edit was committed");
    Array warnings;
    const auto &type = peraviz::gdtf_runtime::cached_fixture_type(proposed, *prepared_->fixture_types);
    const auto ranges = widths(type);
    for (const auto &entry : proposed.addresses) {
        auto width = ranges.find(entry.mvr_break);
        if (width == ranges.end())
            continue;
        if (int64_t(entry.address) + width->second - 1 > 512)
            warnings.push_back(String("Break ") + String::num_int64(entry.mvr_break) +
                               ": footprint crosses slot 512 (Auto Span: " +
                               String::utf8(auto_span_policy_.c_str()) + ").");
        bool overlap = false, unknown = false;
        for (const auto &other : last_scene_model_.fixture_patches)
            if (other.fixture_uuid != id) {
                const auto &other_type =
                    peraviz::gdtf_runtime::cached_fixture_type(other, *prepared_->fixture_types);
                if (!other_type.dmx_patch_supported || other_type.channel_programs.empty()) {
                    unknown = true;
                    continue;
                }
                for (const auto &[number, size] : widths(other_type)) {
                    const auto address = peraviz::gdtf_runtime::source_patch(other, number + 1);
                    overlap |= address.universe == entry.universe &&
                               int64_t(entry.address) < int64_t(address.address) + size &&
                               int64_t(address.address) < int64_t(entry.address) + width->second;
                }
            }
        if (overlap) {
            const String message("Overlaps another authored fixture footprint.");
            warnings.push_back(proposed.addresses.size() == 1
                                   ? message
                                   : String("Break ") + String::num_int64(entry.mvr_break) + ": " + message);
        }
        if (unknown)
            warnings.push_back(
                String("DMX occupancy unknown for fixtures without supported GDTF data."));
    }
    staged_patch_ = StagedPatch{id, proposed, std::move(candidate), universe_offset, routing.policy};
    out["ok"] = true;
    out["warnings"] = warnings;
    return out;
}
// Publish prepared metadata only after the exclusive native routing operation succeeds.
bool PeravizLoader::commit_document_patch(const Ref<PeravizVisualRuntime> &runtime) {
    if (!staged_patch_ || runtime.is_null() || !runtime->replace_routes(staged_patch_->compiled))
        return false;
    for (auto &patch : last_scene_model_.fixture_patches)
        if (patch.fixture_uuid == staged_patch_->uuid)
            patch = staged_patch_->patch;
    // Keep the existing read-only table projection synchronized with canonical authored metadata.
    auto table = last_scene_model_.runtime_tables.find("fixtures");
    if (table != last_scene_model_.runtime_tables.end()) {
        table->second.set_cell(staged_patch_->uuid, 5, int64_t(staged_patch_->patch.mvr_universe));
        table->second.set_cell(staged_patch_->uuid, 6, int64_t(staged_patch_->patch.mvr_address));
    }
    prepared_->compiled = std::move(staged_patch_->compiled);
    prepared_->universe_offset = staged_patch_->offset;
    prepared_->auto_span_policy = staged_patch_->policy;
    staged_patch_.reset();
    return true;
}
// Drop an uncommitted compiler candidate at a failed document transaction boundary.
void PeravizLoader::cancel_document_patch() { staged_patch_.reset(); }
} // namespace godot
