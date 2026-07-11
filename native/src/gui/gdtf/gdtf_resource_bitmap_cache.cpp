#include "gui/gdtf/gdtf_resource_bitmap_cache.h"

#include <algorithm>

namespace peraviz::gui::gdtf {
namespace {

// Builds a stable cache key from source, archive entry, and requested size.
std::string make_key(const GdtfBitmapCacheKey &key) {
    return key.source_id + "|" + key.archive_entry_path + "|" + std::to_string(key.width) + "x" + std::to_string(key.height);
}

} // namespace

// Creates a bounded GUI-only resource bitmap cache.
GdtfResourceBitmapCache::GdtfResourceBitmapCache(std::size_t max_bytes)
    : max_bytes_(max_bytes) {}

// Clears cached previews for a changed GDTF source.
void GdtfResourceBitmapCache::clear_for_source(const std::string &source_id) {
    for (auto it = entries_.begin(); it != entries_.end();) {
        if (it->first.rfind(source_id + "|", 0) == 0) {
            used_bytes_ -= std::min(used_bytes_, it->second.rgba_bytes.size());
            it = entries_.erase(it);
        } else {
            ++it;
        }
    }
}

// Clears all cached GUI previews.
void GdtfResourceBitmapCache::clear() {
    entries_.clear();
    used_bytes_ = 0;
}

// Stores a safe placeholder until the wxWidgets frontend decodes and scales image bytes.
GdtfDecodedBitmapPreview GdtfResourceBitmapCache::get_or_store_placeholder(const GdtfBitmapCacheKey &key,
                                                                           const std::vector<std::uint8_t> &encoded_bytes) {
    const std::string cache_key = make_key(key);
    const auto found = entries_.find(cache_key);
    if (found != entries_.end()) {
        return found->second;
    }
    GdtfDecodedBitmapPreview preview;
    preview.width = std::max(0, key.width);
    preview.height = std::max(0, key.height);
    preview.valid = !encoded_bytes.empty() && preview.width > 0 && preview.height > 0;
    preview.status = preview.valid ? "resource-bytes-ready-for-gui-decode" : "resource-placeholder";
    const std::size_t estimated = static_cast<std::size_t>(preview.width) * static_cast<std::size_t>(preview.height) * 4U;
    if (estimated <= max_bytes_ && used_bytes_ + estimated <= max_bytes_) {
        entries_[cache_key] = preview;
        used_bytes_ += estimated;
    }
    return preview;
}

} // namespace peraviz::gui::gdtf
