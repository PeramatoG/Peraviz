#include "scene_model.h"

#include <system_error>

namespace peraviz {
namespace {

// Normalizes one lease directory for stable scene-generation deduplication.
std::filesystem::path normalized_lease_path(const std::filesystem::path &path) {
    if (path.empty()) return {};
    std::error_code ec;
    const std::filesystem::path canonical = std::filesystem::weakly_canonical(path, ec);
    return (ec ? path : canonical).lexically_normal();
}

} // namespace

// Retains one distinct extraction directory for the active scene generation.
void SceneAssetLeaseSet::retain(const runtime_storage::RuntimeDirectoryLease &lease) {
    if (!lease.valid()) return;
    const std::filesystem::path key = normalized_lease_path(lease.path());
    if (!key.empty()) leases_by_path_.emplace(key, lease);
}

// Releases all extraction directories owned by this scene generation.
void SceneAssetLeaseSet::clear() {
    leases_by_path_.clear();
}

// Returns the number of distinct extraction directories retained by the scene.
std::size_t SceneAssetLeaseSet::size() const {
    return leases_by_path_.size();
}

// Reports whether the scene owns the lease directory containing a path.
bool SceneAssetLeaseSet::owns(const std::filesystem::path &path) const {
    const std::filesystem::path normalized = normalized_lease_path(path);
    for (const auto &[lease_path, _] : leases_by_path_) {
        auto lease_it = lease_path.begin();
        auto path_it = normalized.begin();
        for (; lease_it != lease_path.end() && path_it != normalized.end() && *lease_it == *path_it; ++lease_it, ++path_it) {}
        if (lease_it == lease_path.end()) return true;
    }
    return false;
}

// Returns retained lease directories for diagnostics and lifetime tests.
std::vector<std::filesystem::path> SceneAssetLeaseSet::paths() const {
    std::vector<std::filesystem::path> out;
    out.reserve(leases_by_path_.size());
    for (const auto &[path, _] : leases_by_path_) out.push_back(path);
    return out;
}

} // namespace peraviz
