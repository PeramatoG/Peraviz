#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace peraviz::gui::gdtf {

struct GdtfBitmapCacheKey {
    std::string source_id;
    std::string archive_entry_path;
    int width = 0;
    int height = 0;
};

struct GdtfDecodedBitmapPreview {
    bool valid = false;
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> rgba_bytes;
    std::string status;
};

class GdtfResourceBitmapCache {
public:
    explicit GdtfResourceBitmapCache(std::size_t max_bytes = 8U * 1024U * 1024U);
    void clear_for_source(const std::string &source_id);
    void clear();
    GdtfDecodedBitmapPreview get_or_store_placeholder(const GdtfBitmapCacheKey &key,
                                                       const std::vector<std::uint8_t> &encoded_bytes);

private:
    std::size_t max_bytes_;
    std::size_t used_bytes_ = 0;
    std::unordered_map<std::string, GdtfDecodedBitmapPreview> entries_;
};

} // namespace peraviz::gui::gdtf
