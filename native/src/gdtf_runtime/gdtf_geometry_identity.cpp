#include "gdtf_runtime/gdtf_geometry_identity.h"

namespace peraviz::gdtf_runtime {

// Appends one instantiated geometry segment to a canonical GDTF geometry path.
std::string append_geometry_path(const std::string &parent_path, const std::string &instance_name) {
    if (parent_path.empty()) return instance_name;
    if (instance_name.empty()) return parent_path;
    return parent_path + "/" + instance_name;
}

// Combines a fixture UUID with a canonical fixture-local geometry path.
std::string make_fixture_geometry_key(const std::string &fixture_uuid, const std::string &canonical_path) {
    if (fixture_uuid.empty()) return canonical_path;
    if (canonical_path.empty()) return fixture_uuid;
    return fixture_uuid + "/" + canonical_path;
}

} // namespace peraviz::gdtf_runtime
