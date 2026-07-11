#include "dmx/gdtf_archive_resource_reader.h"

#include "archive/zip_archive.h"
#include "dmx/gdtf_xml_reader.h"

#include <algorithm>
#include <filesystem>
#include <unordered_set>

namespace peraviz::dmx {
namespace {

// Returns true when an extension can be previewed as a static image resource.
bool is_supported_resource_extension(const std::string &extension) {
    const std::string lower = lower_ascii(extension);
    return lower == ".png" || lower == ".jpg" || lower == ".jpeg" || lower == ".svg";
}

// Returns whether a candidate path has the requested file stem and supported media extension.
bool matches_resource_stem(const std::string &entry, const std::string &reference) {
    const std::filesystem::path entry_path = std::filesystem::u8path(entry);
    const std::filesystem::path reference_path = std::filesystem::u8path(reference);
    return lower_ascii(entry_path.stem().u8string()) == lower_ascii(reference_path.stem().u8string()) &&
           is_supported_resource_extension(entry_path.extension().u8string());
}

// Builds canonical wheel-resource candidates before broader compatibility fallbacks.
std::vector<std::string> build_resource_candidates(const std::string &media_file_name) {
    const std::string normalized = peraviz::archive::ZipArchive::normalize_path(trim_ascii(media_file_name));
    std::vector<std::string> candidates;
    if (normalized.empty()) {
        return candidates;
    }
    candidates.push_back(normalized);
    candidates.push_back("wheels/" + normalized);
    candidates.push_back("wheels/images/" + normalized);
    const std::filesystem::path path = std::filesystem::u8path(normalized);
    if (path.extension().empty()) {
        for (const char *extension : {".png", ".jpg", ".jpeg", ".svg"}) {
            candidates.push_back(normalized + extension);
            candidates.push_back("wheels/" + normalized + extension);
            candidates.push_back("wheels/images/" + normalized + extension);
        }
    }
    return candidates;
}

// Reads an archive entry after enforcing the configured size limit.
GdtfArchiveResource read_entry(peraviz::archive::ZipArchive &archive,
                               const std::string &requested_path,
                               const std::string &entry_path,
                               const GdtfResourceReadOptions &options) {
    GdtfArchiveResource resource;
    resource.requested_path = requested_path;
    resource.archive_entry_path = entry_path;
    const std::filesystem::path path = std::filesystem::u8path(entry_path);
    resource.media_type = lower_ascii(path.extension().u8string());
    if (!is_supported_resource_extension(resource.media_type)) {
        resource.diagnostics.push_back({"unsupported_resource", "Wheel resource extension is not supported for preview."});
        return resource;
    }
    resource.bytes = archive.read_file(entry_path);
    if (resource.bytes.size() > options.max_bytes) {
        resource.bytes.clear();
        resource.diagnostics.push_back({"oversized_resource", "Wheel resource exceeds the configured size limit."});
        return resource;
    }
    if (resource.bytes.empty()) {
        resource.diagnostics.push_back({"unreadable_resource", "Wheel resource could not be read from the archive."});
        return resource;
    }
    resource.loaded = true;
    return resource;
}

} // namespace

// Validates that a GDTF archive resource reference cannot escape the archive namespace.
bool is_safe_gdtf_resource_path(const std::string &path) {
    const std::string normalized = peraviz::archive::ZipArchive::normalize_path(trim_ascii(path));
    if (normalized.empty() || normalized.find(':') != std::string::npos) {
        return false;
    }
    for (const std::filesystem::path &part : std::filesystem::u8path(normalized)) {
        if (part == "..") {
            return false;
        }
    }
    return true;
}

// Lazily reads one wheel, animation, graphic-wheel, or media resource from a GDTF archive.
GdtfArchiveResource read_gdtf_wheel_resource(const std::filesystem::path &gdtf_path,
                                             const std::string &media_file_name,
                                             const GdtfResourceReadOptions &options) {
    GdtfArchiveResource resource;
    resource.requested_path = media_file_name;
    if (!is_safe_gdtf_resource_path(media_file_name)) {
        resource.diagnostics.push_back({"unsafe_path", "Wheel resource path is unsafe."});
        return resource;
    }

    peraviz::archive::ZipArchive archive;
    if (!archive.open_read(gdtf_path)) {
        resource.diagnostics.push_back({"unreadable_archive", "GDTF archive could not be opened."});
        return resource;
    }

    for (const std::string &candidate : build_resource_candidates(media_file_name)) {
        if (archive.file_exists(candidate)) {
            return read_entry(archive, media_file_name, candidate, options);
        }
    }

    std::vector<std::string> matches;
    for (const std::string &entry : archive.list_files()) {
        if (matches_resource_stem(entry, media_file_name)) {
            matches.push_back(entry);
        }
    }
    if (matches.size() == 1U) {
        GdtfArchiveResource fallback = read_entry(archive, media_file_name, matches.front(), options);
        fallback.diagnostics.push_back({"case_insensitive_fallback", "Used an unambiguous compatibility resource match."});
        return fallback;
    }
    resource.diagnostics.push_back({matches.empty() ? "missing_resource" : "ambiguous_resource",
                                    matches.empty() ? "Wheel resource was not found." : "Wheel resource reference is ambiguous."});
    return resource;
}

} // namespace peraviz::dmx
