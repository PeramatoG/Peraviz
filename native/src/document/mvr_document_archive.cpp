#include "document/mvr_document.h"
#include "document/mvr_inversion_xml.h"
#include <cerrno>
#include <chrono>
#include <fstream>
#include <set>
#include <zip.h>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
#elif defined(__APPLE__)
#include <stdio.h>
#endif
#include <algorithm>
namespace peraviz::document {
namespace {
constexpr zip_uint64_t max_xml = 32 * 1024 * 1024;
// Atomically publish a new file without replacing a destination that appeared concurrently.
bool publish_new(const std::filesystem::path &stage, const std::filesystem::path &destination,
                 std::error_code &error) {
#ifdef _WIN32
    if (MoveFileExW(stage.c_str(), destination.c_str(), MOVEFILE_WRITE_THROUGH))
        return true;
    error = std::error_code(GetLastError(), std::system_category());
    return false;
#elif defined(__linux__)
    if (syscall(SYS_renameat2, AT_FDCWD, stage.c_str(), AT_FDCWD, destination.c_str(), 1) == 0)
        return true;
    if (errno != ENOSYS && errno != EINVAL) {
        error = std::error_code(errno, std::generic_category());
        return false;
    }
#elif defined(__APPLE__)
    if (renamex_np(stage.c_str(), destination.c_str(), RENAME_EXCL) == 0)
        return true;
    error = std::error_code(errno, std::generic_category());
    return false;
#endif
    std::filesystem::create_hard_link(stage, destination, error);
    return !error;
}
// Reject ambiguous, encrypted and unsafe entry paths before editing or writing.
bool safe_entries(zip_t *archive, std::string &error) {
    std::set<std::string> names;
    const auto count = zip_get_num_entries(archive, 0);
    if (count < 1 || count > 1000000) {
        error = "Unsupported ZIP entry count";
        return false;
    }
    int xml_count = 0;
    for (zip_int64_t i = 0; i < count; ++i) {
        zip_stat_t s;
        zip_stat_init(&s);
        if (zip_stat_index(archive, i, 0, &s) != 0 || !s.name) {
            error = "Unreadable ZIP directory";
            return false;
        }
        std::string name = s.name, folded = name;
        std::transform(folded.begin(), folded.end(), folded.begin(),
                       [](unsigned char c) { return char(c >= 'A' && c <= 'Z' ? c + 32 : c); });
        bool unsafe = name.empty() || name.front() == '/' || name.find('\\') != std::string::npos ||
                      name.find(':') != std::string::npos;
        size_t start = 0;
        while (start < name.size()) {
            auto end = name.find('/', start);
            auto part = name.substr(start, end - start);
            if (part == ".." || part == "." || part.empty())
                unsafe = true;
            if (end == std::string::npos)
                break;
            start = end + 1;
        }
        if (unsafe || !names.insert(folded).second || s.encryption_method != ZIP_EM_NONE ||
            (s.comp_method != ZIP_CM_STORE && s.comp_method != ZIP_CM_DEFLATE)) {
            error = "Unsafe, duplicate, encrypted or unsupported ZIP entry: " + name;
            return false;
        }
        if (name == "GeneralSceneDescription.xml") {
            ++xml_count;
        }
    }
    if (xml_count != 1) {
        error = "Exactly one canonical GeneralSceneDescription.xml is required";
        return false;
    }
    return true;
}
// Compare decompressed streams in fixed-size blocks; resources never accumulate in memory.
bool same_entry(zip_t *a, zip_t *b, zip_uint64_t index) {
    auto x = zip_fopen_index(a, index, 0), y = zip_fopen_index(b, index, 0);
    if (!x || !y) {
        if (x)
            zip_fclose(x);
        if (y)
            zip_fclose(y);
        return false;
    }
    char left[65536], right[65536];
    bool valid = true;
    for (;;) {
        const auto nx = zip_fread(x, left, sizeof(left)), ny = zip_fread(y, right, sizeof(right));
        if (nx < 0 || nx != ny || (nx > 0 && !std::equal(left, left + nx, right))) {
            valid = false;
            break;
        }
        if (!nx)
            break;
    }
    valid = zip_fclose(x) == 0 && valid;
    valid = zip_fclose(y) == 0 && valid;
    return valid;
}
} // namespace
// Read only bounded XML after validating central-directory names and supported ZIP operations.
bool inspect_archive(const std::filesystem::path &path, std::string &xml, std::string &error,
                     bool *safe_zip) {
    if (safe_zip)
        *safe_zip = false;
    int code = 0;
    auto archive = zip_open(path.u8string().c_str(), ZIP_RDONLY | ZIP_CHECKCONS, &code);
    if (!archive) {
        error = "Cannot open consistent MVR ZIP";
        return false;
    }
    bool valid = safe_entries(archive, error);
    if (safe_zip)
        *safe_zip = valid;
    if (valid) {
        zip_stat_t s;
        zip_stat_init(&s);
        zip_stat(archive, "GeneralSceneDescription.xml", 0, &s);
        if (s.size > max_xml) {
            zip_discard(archive);
            error = "Scene XML exceeds the 32 MiB editing bound; only opaque PVZ preservation is available";
            return false;
        }
        auto file = zip_fopen(archive, "GeneralSceneDescription.xml", 0);
        xml.resize(size_t(s.size));
        size_t offset = 0;
        if (!file)
            valid = false;
        while (valid && offset < xml.size()) {
            auto n = zip_fread(file, xml.data() + offset, xml.size() - offset);
            if (n <= 0)
                valid = false;
            else
                offset += size_t(n);
        }
        if (file && zip_fclose(file) != 0)
            valid = false;
    }
    zip_discard(archive);
    if (!valid && error.empty())
        error = "Unable to read scene XML";
    return valid;
}
// Stage beside the destination, validate XML and byte-preserve every other entry before commit.
bool write_archive(const std::filesystem::path &source, const std::filesystem::path &destination,
                   const std::string &xml, bool changed, std::string &error) {
    std::error_code ec;
    if (destination.empty() || std::filesystem::exists(destination, ec)) {
        error = "Choose a new destination; existing files are never overwritten by MVR export";
        return false;
    }
    const auto stage_dir =
        destination.parent_path() /
        (".peraviz-export-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    if (!std::filesystem::create_directory(stage_dir, ec)) {
        error = "Cannot create export staging directory";
        return false;
    }
    struct Cleanup {
        std::filesystem::path path; /* Remove unpublished staging files on every return path. */
        ~Cleanup() {
            std::error_code e;
            std::filesystem::remove_all(path, e);
        }
    } cleanup{stage_dir};
    const auto stage = stage_dir / "scene.mvr";
    if (!std::filesystem::copy_file(source, stage, std::filesystem::copy_options::none, ec)) {
        error = "Cannot copy source MVR to staging";
        return false;
    }
    if (changed) {
        tinyxml2::XMLDocument document;
        if (document.Parse(xml.data(), xml.size()) != tinyxml2::XML_SUCCESS) {
            error = "Edited XML failed validation";
            return false;
        }
        int code = 0;
        auto archive = zip_open(stage.u8string().c_str(), 0, &code);
        if (!archive) {
            error = "Cannot update staged ZIP";
            return false;
        }
        zip_stat_t original;
        zip_stat_init(&original);
        zip_stat(archive, "GeneralSceneDescription.xml", 0, &original);
        const auto index = zip_name_locate(archive, "GeneralSceneDescription.xml", 0);
        auto data = zip_source_buffer(archive, xml.data(), xml.size(), 0);
        if (!data || zip_file_replace(archive, index, data, 0) < 0) {
            if (data)
                zip_source_free(data);
            zip_discard(archive);
            error = "Cannot replace scene XML";
            return false;
        }
        if (zip_file_set_mtime(archive, index, original.mtime, 0) != 0 ||
            zip_set_file_compression(archive, index, original.comp_method, 0) != 0) {
            zip_discard(archive);
            error = "Cannot preserve scene XML archive metadata";
            return false;
        }
        if (zip_close(archive) != 0) {
            zip_discard(archive);
            error = "Cannot finalize edited ZIP";
            return false;
        }
    }
    std::string checked;
    if (!inspect_archive(stage, checked, error) || checked != xml) {
        error = "Export XML verification failed: " + error;
        return false;
    }
    int code = 0;
    auto a = zip_open(source.u8string().c_str(), ZIP_RDONLY, &code),
         b = zip_open(stage.u8string().c_str(), ZIP_RDONLY, &code);
    bool valid = a && b;
    if (valid) {
        valid = zip_get_num_entries(a, 0) == zip_get_num_entries(b, 0);
        for (zip_int64_t i = 0; valid && i < zip_get_num_entries(a, 0); ++i) {
            const char *name = zip_get_name(a, i, 0);
            valid = name && std::string(name) == zip_get_name(b, i, 0);
            if (valid && std::string(name) != "GeneralSceneDescription.xml")
                valid = same_entry(a, b, i);
        }
    }
    if (a)
        zip_discard(a);
    if (b)
        zip_discard(b);
    if (!valid) {
        error = "Export resource verification failed; nothing was published";
        return false;
    }
    if (!publish_new(stage, destination, ec)) {
        error = "Atomic export publication failed; choose a new filename on a supported filesystem: " +
                ec.message();
        return false;
    }
    return true;
}
} // namespace peraviz::document
