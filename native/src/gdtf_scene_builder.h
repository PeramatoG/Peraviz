#pragma once

#include "scene_model.h"
#include "types.h"

#include <string>
#include <vector>
#include <map>
#include <utility>
#include <tuple>
#include <filesystem>

namespace peraviz {

struct GdtfBuildRequest {
    std::string gdtf_archive_path;
    std::string gdtf_mode;
    std::string fixture_node_id;
    std::string fixture_name;
};

struct GdtfGeometryBuildResult {
    std::vector<SceneNode> nodes;
    runtime_storage::RuntimeDirectoryLease cache_lease;
    std::string cache_path;
};

GdtfGeometryBuildResult build_fixture_geometry_nodes(const GdtfBuildRequest &request,
                                                     const std::string &parent_id,
                                                     const Matrix &parent_world,
                                                     int &extracted_asset_count);

// Generation-scoped immutable definitions. MVR extraction paths are content-addressed and
// leased for the entire setup; no template survives reload or a source-file revision.
class FixtureGeometryTemplates {
public:
    GdtfGeometryBuildResult instantiate(const GdtfBuildRequest &request,
        const std::string &parent_id, int &extracted_asset_count);
    size_t definitions() const { return templates_.size(); }
    size_t hits() const { return hits_; }
private:
    std::map<std::tuple<std::string, std::string, std::filesystem::file_time_type, uintmax_t>, GdtfGeometryBuildResult> templates_;
    size_t hits_ = 0;
};

} // namespace peraviz
