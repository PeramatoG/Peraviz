#include "document/mvr_document_godot.h"
#include <godot_cpp/core/class_db.hpp>
namespace godot {
// Expose bounded document operations; no XML or binary resource buffers cross into Godot.
void PeravizMvrDocument::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open", "path"), &PeravizMvrDocument::open);
    ClassDB::bind_method(D_METHOD("fixture", "uuid"), &PeravizMvrDocument::fixture);
    ClassDB::bind_method(D_METHOD("prepare", "ids", "axis", "value"), &PeravizMvrDocument::prepare);
    ClassDB::bind_method(D_METHOD("prepare_history", "redo"), &PeravizMvrDocument::prepare_history);
    ClassDB::bind_method(D_METHOD("pending_values"), &PeravizMvrDocument::pending_values);
    ClassDB::bind_method(D_METHOD("commit"), &PeravizMvrDocument::commit);
    ClassDB::bind_method(D_METHOD("cancel"), &PeravizMvrDocument::cancel);
    ClassDB::bind_method(D_METHOD("canonical_path"), &PeravizMvrDocument::canonical_path);
    ClassDB::bind_method(D_METHOD("export_mvr", "path"), &PeravizMvrDocument::export_mvr);
    ClassDB::bind_method(D_METHOD("mark_saved"), &PeravizMvrDocument::mark_saved);
    ClassDB::bind_method(D_METHOD("state"), &PeravizMvrDocument::state);
}
// Open one scene-owned immutable source snapshot.
bool PeravizMvrDocument::open(const String &path) {
    return document_.open(std::filesystem::u8path(path.utf8().get_data()));
}
// Publish only indexed fixture metadata and an explicit editing rejection reason.
Dictionary PeravizMvrDocument::fixture(const String &uuid) const {
    Dictionary result;
    auto f = document_.fixture(uuid.utf8().get_data());
    result["editable"] = f && f->reason.empty();
    result["reason"] = String::utf8(f                   ? f->reason.c_str()
                                    : document_.ready() ? "Not a canonical source Fixture UUID"
                                                        : document_.error().c_str());
    if (f) {
        result["uuid"] = String::utf8(f->uuid.c_str());
        for (int axis = 0; axis < 2; ++axis) {
            const String prefix = axis ? "tilt" : "pan";
            result[prefix] = f->current[axis].value;
            result[prefix + String("_present")] = f->current[axis].present;
            result[prefix + String("_valid")] = f->current[axis].valid;
        }
    }
    return result;
}
// Stage one atomic command for the complete validated selection.
bool PeravizMvrDocument::prepare(const PackedStringArray &ids, int axis, bool value) {
    std::vector<std::string> selection;
    for (int64_t i = 0; i < ids.size(); ++i)
        selection.emplace_back(ids[i].utf8().get_data());
    return document_.prepare(selection, axis, value);
}
// Stage an existing history operation without losing its previous XML absence.
bool PeravizMvrDocument::prepare_history(bool redo) { return document_.prepare_history(redo); }
// Publish prospective canonical states for a synchronous native runtime transaction.
Array PeravizMvrDocument::pending_values() const {
    Array result;
    for (const auto &change : document_.pending()) {
        auto f = document_.fixture(change.uuid);
        auto values = f->current;
        values[change.axis] = change.after;
        Dictionary row;
        row["fixture_uuid"] = String::utf8(f->uuid.c_str());
        for (int axis = 0; axis < 2; ++axis) {
            String p = axis ? "tilt" : "pan";
            row[p] = values[axis].value;
            row[p + String("_present")] = values[axis].present;
        }
        result.push_back(row);
    }
    return result;
}
// Commit a staged command after its runtime configuration has been accepted.
bool PeravizMvrDocument::commit() { return document_.commit(); }
// Cancel an unapplied command with no history or document changes.
void PeravizMvrDocument::cancel() { document_.cancel(); }
// Return the single cached canonical serialization, without copying its binary contents into Godot.
String PeravizMvrDocument::canonical_path() {
    return String::utf8(document_.canonical_archive().u8string().c_str());
}
// Export to a new destination using verified streaming archive preservation.
bool PeravizMvrDocument::export_mvr(const String &path) {
    return document_.export_mvr(std::filesystem::u8path(path.utf8().get_data()));
}
// Mark only successful project saves as clean.
void PeravizMvrDocument::mark_saved() { document_.mark_saved(); }
// Publish constant-size session metadata for menus and title updates.
Dictionary PeravizMvrDocument::state() const {
    Dictionary d;
    d["ready"] = document_.ready();
    d["dirty"] = document_.dirty();
    d["can_undo"] = document_.can_undo();
    d["can_redo"] = document_.can_redo();
    d["error"] = String::utf8(document_.error().c_str());
    return d;
}
} // namespace godot
