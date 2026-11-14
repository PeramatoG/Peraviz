#pragma once

#include <cstdint>
#include <map>
#include <string>

namespace peraviz {

// Setup-only aggregate observations; never part of canonical scene/runtime semantics.
struct AssetCacheMetrics {
    double archive_open_index_ms = 0, extraction_ms = 0, dependency_discovery_ms = 0;
    uint64_t archive_entries = 0, indexed_lookups = 0, unique_lookup_references = 0, unique_asset_references = 0;
    uint64_t cache_hits = 0, cache_misses = 0, extraction_count = 0, extracted_bytes = 0;
    uint64_t dependency_candidates = 0;

    // Combines archive owners once, independently of template instance fan-out.
    void add(const AssetCacheMetrics &other) {
        archive_open_index_ms += other.archive_open_index_ms;
        extraction_ms += other.extraction_ms;
        dependency_discovery_ms += other.dependency_discovery_ms;
        archive_entries += other.archive_entries;
        indexed_lookups += other.indexed_lookups;
        unique_lookup_references += other.unique_lookup_references;
        unique_asset_references += other.unique_asset_references;
        cache_hits += other.cache_hits; cache_misses += other.cache_misses;
        extraction_count += other.extraction_count; extracted_bytes += other.extracted_bytes;
        dependency_candidates += other.dependency_candidates;
    }
};

} // namespace peraviz
