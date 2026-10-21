#pragma once
#include <cstdlib>
#include <string_view>

namespace peraviz {
// Developer-only setup comparisons; sampled at load/compile boundaries, never during playback.
struct SceneSetupOptions {
    bool fixture_templates = true;
    bool indexed_classification = true;
    // Environment switches are reference escapes, independent of canonical scene data.
    static SceneSetupOptions read() {
        const auto enabled = [](const char *key) {
            const char *value = std::getenv(key);
            return value && std::string_view(value) == "1";
        };
        return {!enabled("PERAVIZ_SETUP_REFERENCE_GEOMETRY"), !enabled("PERAVIZ_SETUP_REFERENCE_INDEXES")};
    }
};
}
