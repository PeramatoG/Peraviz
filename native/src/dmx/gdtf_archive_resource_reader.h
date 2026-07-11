#pragma once

#include "dmx/gdtf_color_cie.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace peraviz::dmx {

struct GdtfResourceReadOptions {
    std::size_t max_bytes = 2U * 1024U * 1024U;
};

struct GdtfArchiveResource {
    bool loaded = false;
    std::string requested_path;
    std::string archive_entry_path;
    std::string media_type;
    std::vector<std::uint8_t> bytes;
    std::vector<GdtfDiagnostic> diagnostics;
};

bool is_safe_gdtf_resource_path(const std::string &path);
GdtfArchiveResource read_gdtf_wheel_resource(const std::filesystem::path &gdtf_path,
                                             const std::string &media_file_name,
                                             const GdtfResourceReadOptions &options = {});

} // namespace peraviz::dmx
