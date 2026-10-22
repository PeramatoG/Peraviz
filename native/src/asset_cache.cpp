#include "asset_cache.h"

#include "archive/zip_archive.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <vector>


namespace {

// Converts ASCII text to lowercase for normalized comparisons.
std::string to_lower_ascii(std::string value) {
// Applies lowercase conversion to each character in the string.
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
    });
    return value;
}

// Normalizes archive paths for deterministic cache keys.
std::string normalize_archive_path(const std::string &raw) {
    return peraviz::archive::ZipArchive::normalize_path(raw);
}

// Replaces unsafe filename characters in one path segment.
std::string sanitize_path_component_for_fs(std::string component) {
    for (char &ch : component) {
        const unsigned char c = static_cast<unsigned char>(ch);
        const bool is_control = c < 32;
        const bool is_forbidden =
            ch == '<' || ch == '>' || ch == ':' || ch == '"' || ch == '|' ||
            ch == '?' || ch == '*' || ch == '\\' || ch == '/';
        if (is_control || is_forbidden) {
            ch = '_';
        }
    }

    while (!component.empty() &&
           (component.back() == ' ' || component.back() == '.')) {
        component.pop_back();
    }

    if (component.empty()) {
        return "_";
    }
    return component;
}

// Builds a filesystem-safe relative path for cached assets.
std::filesystem::path cache_safe_relative_path(const std::string &normalized_archive_path) {
    std::filesystem::path normalized =
        std::filesystem::u8path(normalized_archive_path).lexically_normal();

    std::filesystem::path safe_path;
    for (const std::filesystem::path &part : normalized) {
        const std::string component = part.u8string();
        if (component.empty() || component == ".") {
            continue;
        }
        if (component == "..") {
            continue;
        }
        safe_path /= std::filesystem::u8path(sanitize_path_component_for_fs(component));
    }
    return safe_path;
}

// Trims ASCII whitespace from both ends of a string.
std::string trim_ascii(std::string value) {
    const auto is_space = [](unsigned char c) {
        return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
    };

    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.erase(value.begin());
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.pop_back();
    }
    return value;
}

// Returns the lowercase extension of a filesystem path.
std::string path_extension_lower(const std::string &normalized_path) {
    const std::filesystem::path path = std::filesystem::u8path(normalized_path);
    return to_lower_ascii(path.extension().u8string());
}

// Returns whether an extension is a supported model dependency.
bool is_supported_texture_or_scene_dependency_extension(const std::string &extension_lower) {
    return extension_lower == ".png" || extension_lower == ".jpg" ||
           extension_lower == ".jpeg" || extension_lower == ".bmp" ||
           extension_lower == ".tga" || extension_lower == ".gif" ||
           extension_lower == ".webp" || extension_lower == ".hdr" ||
           extension_lower == ".dds" || extension_lower == ".ktx2" ||
           extension_lower == ".mtl" || extension_lower == ".bin";
}

// Computes a stable 128-bit non-cryptographic content fingerprint plus byte length.
std::string hash_file_contents(const std::filesystem::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return "missing";
    }

    std::uint64_t hash = 1469598103934665603ULL;
    constexpr std::uint64_t prime = 1099511628211ULL;
    std::uint64_t second_hash = 7809847782465536322ULL;
    std::uint64_t size = 0;
    char buffer[4096];
    while (input.read(buffer, sizeof(buffer)) || input.gcount() > 0) {
        for (std::streamsize i = 0; i < input.gcount(); ++i) {
            hash ^= static_cast<unsigned char>(buffer[i]);
            hash *= prime;
            second_hash ^= static_cast<unsigned char>(buffer[i]);
            second_hash *= 14029467366897019727ULL;
            ++size;
        }
    }

    std::ostringstream ss;
    ss << std::hex << std::setfill('0') << std::setw(16) << hash
       << std::setw(16) << second_hash << "_" << size;
    return ss.str();
}

// Returns the parent directory that stores extracted archive data.
std::string parent_archive_dir(const std::string &normalized_path) {
    const std::filesystem::path path = std::filesystem::u8path(normalized_path);
    const std::filesystem::path parent = path.parent_path();
    if (parent.empty()) {
        return {};
    }
    std::string value = normalize_archive_path(parent.u8string());
    if (!value.empty() && value.back() != '/') {
        value.push_back('/');
    }
    return value;
}

} // namespace

namespace peraviz {

// Creates one content-keyed workspace and indexes its source archive once.
ZipAssetCache::ZipAssetCache(std::string source_path)
    : source_path_(std::filesystem::u8path(source_path)) {
    const std::string cache_key = "archive_" + hash_file_contents(source_path_);
    cache_lease_ = runtime_storage::acquire_session_cache_directory(cache_key);
    cache_dir_ = cache_lease_.path();
    if (archive_.open_read(source_path_)) entries_ = archive_.list_files();
    else last_error_ = "archive_open_failed";
}

// Returns the directory used to store extracted cache files.
const std::filesystem::path &ZipAssetCache::cache_dir() const { return cache_dir_; }

// Returns the shared lease that keeps extracted files available.
runtime_storage::RuntimeDirectoryLease ZipAssetCache::cache_lease() const { return cache_lease_; }

// Returns the number of unique assets extracted by this cache owner.
int ZipAssetCache::extracted_assets() const { return static_cast<int>(extracted_.size()); }

// Returns a stable reason for the most recent resolution/extraction failure.
const std::string &ZipAssetCache::last_error() const { return last_error_; }

// Resolves exact normalized entries before unambiguous compatibility lookups.
std::string ZipAssetCache::resolve_entry(const std::string &reference, bool basename_fallback) {
    if (!archive_.is_open()) { last_error_ = "archive_open_failed"; return {}; }
    const std::string normalized = normalize_archive_path(reference);
    if (normalized.empty()) { last_error_ = "invalid_resource_reference"; return {}; }
    const auto exact = std::find(entries_.begin(), entries_.end(), normalized);
    if (exact != entries_.end()) return *exact;
    const std::string folded = to_lower_ascii(normalized);
    std::string match;
    for (const auto &entry : entries_) {
        if (to_lower_ascii(entry) != folded) continue;
        if (!match.empty()) { last_error_ = "ambiguous_resource_reference"; return {}; }
        match = entry;
    }
    if (!match.empty() || !basename_fallback) return match;
    const auto filename = to_lower_ascii(std::filesystem::u8path(normalized).filename().u8string());
    for (const auto &entry : entries_) {
        if (to_lower_ascii(std::filesystem::u8path(entry).filename().u8string()) != filename) continue;
        if (!match.empty()) { last_error_ = "ambiguous_resource_reference"; return {}; }
        match = entry;
    }
    return match;
}

// Extracts the canonical archive entry without aliasing sanitized filesystem names.
std::string ZipAssetCache::ensure_extracted(const std::string &reference) {
    last_error_.clear();
    const std::string entry = resolve_entry(reference, false);
    if (entry.empty()) {
        if (last_error_.empty()) last_error_ = archive_.is_open() ? "resource_not_found" : "archive_open_failed";
        return {};
    }
    if (const auto found = resolved_.find(entry); found != resolved_.end()) return found->second;
    const auto relative = cache_safe_relative_path(entry);
    // Reject mappings that collide after Windows filename sanitation on every OS.
    for (const auto &other : entries_) {
        if (other != entry && to_lower_ascii(cache_safe_relative_path(other).generic_u8string()) ==
                              to_lower_ascii(relative.generic_u8string())) {
            last_error_ = "ambiguous_extraction_path";
            return {};
        }
    }
    const auto output = cache_dir_ / relative;
    std::error_code ec;
    if (!std::filesystem::is_regular_file(output, ec) && !archive_.extract_file(entry, output)) {
        last_error_ = "resource_extraction_failed";
        return {};
    }
    extracted_.insert(entry);
    return resolved_.emplace(entry, output.u8string()).first->second;
}

// Extracts a named file, accepting a unique nested basename for compatibility.
std::string ZipAssetCache::ensure_archive_file_extracted(const std::string &reference) {
    last_error_.clear();
    const auto entry = resolve_entry(reference, true);
    if (!entry.empty()) return ensure_extracted(entry);
    if (last_error_.empty()) last_error_ = "resource_not_found";
    return {};
}

// Resolves explicit GDTF extensions without changing the incoming specification.
std::string ZipAssetCache::ensure_gdtf_spec_extracted(const std::string &spec) {
    std::string normalized = trim_ascii(normalize_archive_path(spec));
    if (std::filesystem::u8path(normalized).extension().empty()) normalized += ".gdtf";
    return ensure_archive_file_extracted(normalized);
}

// Extracts companion assets once per model directory while retaining relative paths.
void ZipAssetCache::extract_model_dependencies(const std::string &entry) {
    const auto directory = parent_archive_dir(entry);
    if (!dependencies_extracted_.insert(directory).second) return;
    for (const auto &dependency : entries_) {
        if ((!directory.empty() && dependency.rfind(directory, 0) != 0) ||
            (directory.empty() && dependency.find('/') != std::string::npos)) continue;
        if (is_supported_texture_or_scene_dependency_extension(path_extension_lower(dependency)))
            ensure_extracted(dependency);
    }
}

// Resolves models without substituting a different explicit format or ambiguous stem.
std::string ZipAssetCache::ensure_model_extracted(const std::string &reference, bool gdtf_basename) {
    last_error_.clear();
    const auto normalized = normalize_archive_path(reference);
    if (normalized.empty()) { last_error_ = "invalid_resource_reference"; return {}; }
    const auto extension = path_extension_lower(normalized);
    const std::vector<std::string> formats = {".3ds", ".glb", ".gltf", ".obj", ".dae", ".fbx", ".stl"};
    const bool explicit_format = std::find(formats.begin(), formats.end(), extension) != formats.end();
    std::vector<std::string> candidates;
    if (gdtf_basename && explicit_format) candidates.push_back(normalized);
    if (gdtf_basename) {
        const auto filename = std::filesystem::u8path(normalized).filename().u8string();
        // Model.File is an extensionless basename: periods are ordinary name characters.
        // Known extensions/subfolders are accepted only as compatibility references.
        for (const auto *folder : {"3ds", "gltf", "3ds_low", "gltf_low", "3ds_high", "gltf_high"}) {
            const std::string format = std::string(folder).rfind("gltf", 0) == 0 ? ".glb" : ".3ds";
            if (!explicit_format || extension == format)
                candidates.push_back("models/" + std::string(folder) + "/" + filename + (explicit_format ? "" : format));
        }
    }
    if (!gdtf_basename && !extension.empty()) candidates.push_back(normalized);
    else if (!explicit_format) for (const auto &format : formats) candidates.push_back(normalized + format);
    // Exact paths across all candidate formats take priority over basename heuristics.
    for (bool fallback : {false, true}) {
        for (const auto &candidate : candidates) {
            const auto entry = resolve_entry(candidate, fallback);
            if (!last_error_.empty()) return {};
            if (entry.empty()) continue;
            const auto extracted = ensure_extracted(entry);
            if (extracted.empty()) return {};
            extract_model_dependencies(entry);
            last_error_.clear();
            return extracted;
        }
    }
    last_error_ = "resource_not_found";
    return {};
}

// Resolves an MVR Geometry3D reference through the shared archive cache.
std::string ZipAssetCache::ensure_mvr_model_extracted(const std::string &reference) {
    return ensure_model_extracted(reference, false);
}

// Resolves GDTF File basenames, including standard models/3ds and models/gltf directories.
std::string ZipAssetCache::ensure_gdtf_model_extracted(const std::string &reference) {
    return ensure_model_extracted(reference, true);
}

} // namespace peraviz
