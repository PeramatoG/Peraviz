#pragma once

#include <filesystem>
#include <unordered_set>
#include "asset_cache_metrics.h"
#include "archive/zip_archive.h"
#include <unordered_map>
#include <vector>
#include "runtime_storage.h"
#include <set>
#include <string>

namespace peraviz {

enum class GdtfModelDetail { Default, Low, High };

class ZipAssetCache {
public:
    explicit ZipAssetCache(std::string source_path, AssetCacheMetrics *aggregate = nullptr);
    ~ZipAssetCache();
    const AssetCacheMetrics &metrics() const { return metrics_; }

    const std::filesystem::path &cache_dir() const;
    runtime_storage::RuntimeDirectoryLease cache_lease() const;
    int extracted_assets() const;
    const std::string &last_error() const;

    std::string read_mvr_scene_description() const;
    std::string ensure_extracted(const std::string &archive_relative_path);
    std::string ensure_archive_file_extracted(const std::string &file_name);
    std::string ensure_gdtf_spec_extracted(const std::string &gdtf_spec);
    std::string ensure_mvr_model_extracted(const std::string &model_reference);
    std::string ensure_gdtf_model_extracted(const std::string &model_reference, GdtfModelDetail detail = GdtfModelDetail::Default);
    // Reports the exact archive identity selected for the most recent model.
    const std::string &model_entry() const { return model_entry_; }
    // Reports the selected authored tier, including explicit compatibility paths.
    const std::string &model_quality() const { return model_quality_; }

private:
    archive::ZipArchive archive_;
    std::unordered_set<std::string> exact_entries_;
    // Empty values mark ambiguous aliases; exact paths retain precedence.
    std::unordered_map<std::string, std::string> folded_entries_, basename_entries_;
    std::unordered_map<std::string, std::filesystem::path> destinations_;
    std::unordered_set<std::string> colliding_entries_;
    std::unordered_map<std::string, std::vector<std::string>> directory_dependencies_;
    std::unordered_set<std::string> lookup_references_, referenced_entries_;
    std::string mvr_description_entry_;
    AssetCacheMetrics metrics_;
    AssetCacheMetrics *aggregate_ = nullptr;
    void build_indexes(const std::vector<std::string> &entries);
    std::unordered_map<std::string, std::string> resolved_;
    std::set<std::string> dependencies_extracted_;
    std::string last_error_;
    std::string model_entry_, model_quality_;
    std::string resolve_entry(const std::string &reference, bool basename_fallback);
    std::string ensure_model_extracted(const std::string &reference, bool gdtf_basename, GdtfModelDetail detail = GdtfModelDetail::Default);
    void extract_model_dependencies(const std::string &entry);
    std::filesystem::path source_path_;
    std::filesystem::path cache_dir_;
    std::set<std::string> extracted_;
    runtime_storage::RuntimeDirectoryLease cache_lease_;
};

} // namespace peraviz
