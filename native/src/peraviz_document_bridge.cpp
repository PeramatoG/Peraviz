#include "peraviz_loader.h"
#include <unordered_map>
namespace godot {
// Synchronize canonical metadata and prepared numeric flags without rebuilding geometry or renderer
// resources.
void PeravizLoader::sync_document_inversions(const Array &values) {
    std::unordered_map<std::string, Dictionary> changed;
    for (int64_t i = 0; i < values.size(); ++i) {
        Dictionary row = values[i];
        String id = row["fixture_uuid"];
        changed.emplace(id.utf8().get_data(), row);
    }
    for (auto &patch : last_scene_model_.fixture_patches) {
        auto found = changed.find(patch.fixture_uuid);
        if (found == changed.end())
            continue;
        const auto &row = found->second;
        patch.invert_pan = {bool(row["pan_present"]), bool(row["pan"]), true, {}};
        patch.invert_tilt = {bool(row["tilt_present"]), bool(row["tilt"]), true, {}};
    }
    if (prepared_)
        for (auto &fixture : prepared_->compiled.fixtures) {
            auto found = changed.find(fixture.fixture_uuid);
            if (found == changed.end())
                continue;
            fixture.invert_pan = bool(found->second["pan"]);
            fixture.invert_tilt = bool(found->second["tilt"]);
        }
}
} // namespace godot
