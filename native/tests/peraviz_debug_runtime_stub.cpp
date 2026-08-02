#include "peraviz_debug_runtime.h"

namespace peraviz::debug_runtime {

// Ignores baseline debug configuration in native ownership tests.
void set_baseline_debug_enabled(bool) {}

// Reports disabled baseline debugging in native ownership tests.
bool is_baseline_debug_enabled() { return false; }

// Ignores coordinate debug configuration in native ownership tests.
void set_coordinate_debug_enabled(bool) {}

// Reports disabled coordinate debugging in native ownership tests.
bool is_coordinate_debug_enabled() { return false; }

// Suppresses coordinate metadata output in native ownership tests.
void log_coordinate_mapping_metadata() {}

// Suppresses coordinate event output in native ownership tests.
void log_coordinate_debug_event(const std::string &, const std::string &, const std::string &) {}

// Suppresses baseline transform output in native ownership tests.
void log_baseline_transform_comparison(const std::string &, const Matrix &, const SceneTransform &) {}

// Suppresses transform adjustment output in native ownership tests.
void log_transform_adjustment(const std::string &, const std::string &, const Matrix &, const Matrix &) {}

} // namespace peraviz::debug_runtime
