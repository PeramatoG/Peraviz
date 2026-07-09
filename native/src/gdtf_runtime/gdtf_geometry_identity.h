#pragma once

#include <cstdint>
#include <string>

namespace peraviz::gdtf_runtime {

struct GeometryIdentity {
    int32_t id = 0;
    int32_t parent_id = 0;
    std::string source_name;
    std::string reference_context;
    std::string canonical_path;
    std::string display_name;
    std::string geometry_type;
};

std::string append_geometry_path(const std::string &parent_path, const std::string &instance_name);
std::string make_fixture_geometry_key(const std::string &fixture_uuid, const std::string &canonical_path);

} // namespace peraviz::gdtf_runtime
