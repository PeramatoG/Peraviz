#include "archive/zip_archive.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <sstream>
#include <unordered_set>

#include <zip.h>

namespace peraviz::archive {

namespace {

// Converts ASCII text to lowercase for archive path comparisons.
std::string lower_ascii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
    });
    return value;
}

// Returns whether an archive path represents a directory entry.
bool is_directory_entry(const std::string &archive_path) {
    return !archive_path.empty() && archive_path.back() == '/';
}

} // namespace

// Initializes an empty archive wrapper.
ZipArchive::ZipArchive() = default;

// Closes or discards the open archive handle.
ZipArchive::~ZipArchive() {
    reset();
}

// Moves ownership of an archive handle into this wrapper.
ZipArchive::ZipArchive(ZipArchive &&other) noexcept
    : archive_(other.archive_), writable_(other.writable_) {
    other.index_ready_ = false;
    other.entries_.clear();
    other.folded_entries_.clear();
    other.archive_ = nullptr;
    other.writable_ = false;
}

// Replaces this wrapper with another archive handle.
ZipArchive &ZipArchive::operator=(ZipArchive &&other) noexcept {
    if (this != &other) {
        reset();
        archive_ = other.archive_;
        writable_ = other.writable_;
        other.index_ready_ = false;
        other.entries_.clear();
        other.folded_entries_.clear();
        other.archive_ = nullptr;
        other.writable_ = false;
    }
    return *this;
}

// Opens an existing archive for reading.
bool ZipArchive::open_read(const std::filesystem::path &path) {
    reset();
    int error = 0;
    archive_ = zip_open(path.u8string().c_str(), ZIP_RDONLY, &error);
    writable_ = false;
    return archive_ != nullptr;
}

// Opens an archive for creating or modifying entries.
bool ZipArchive::open_create_or_modify(const std::filesystem::path &path) {
    reset();
    int error = 0;
    archive_ = zip_open(path.u8string().c_str(), ZIP_CREATE, &error);
    writable_ = archive_ != nullptr;
    return archive_ != nullptr;
}

// Returns whether an archive handle is currently open.
bool ZipArchive::is_open() const {
    return archive_ != nullptr;
}

// Lists normalized file entries from the archive.
std::vector<std::string> ZipArchive::list_files() const {
    std::vector<std::string> files;
    if (!archive_) {
        return files;
    }

    build_index();
    for (const auto &entry : entries_) files.push_back(entry.first);
    std::sort(files.begin(), files.end());
    return files;
}

// Returns whether a file exists in the archive.
bool ZipArchive::file_exists(const std::string &archive_path) const {
    return !find_entry_name(archive_path).empty();
}

// Reads a binary file from the archive.
std::vector<std::uint8_t> ZipArchive::read_file(const std::string &archive_path) const {
    std::vector<std::uint8_t> data;
    if (!archive_) {
        return data;
    }

    const std::string entry_name = find_entry_name(archive_path);
    if (entry_name.empty()) {
        return data;
    }

    zip_stat_t stat;
    zip_stat_init(&stat);
    if (zip_stat(archive_, entry_name.c_str(), ZIP_FL_ENC_GUESS, &stat) != 0) {
        return data;
    }
    if (stat.size > static_cast<zip_uint64_t>(std::numeric_limits<std::size_t>::max())) {
        return data;
    }

    zip_file_t *file = zip_fopen(archive_, entry_name.c_str(), ZIP_FL_ENC_GUESS);
    if (!file) {
        return data;
    }

    data.resize(static_cast<std::size_t>(stat.size));
    std::size_t offset = 0;
    while (offset < data.size()) {
        const zip_int64_t bytes = zip_fread(file, data.data() + offset, data.size() - offset);
        if (bytes < 0) {
            data.clear();
            break;
        }
        if (bytes == 0) {
            break;
        }
        offset += static_cast<std::size_t>(bytes);
    }
    const int close_result = zip_fclose(file);

    if (offset != data.size() || close_result != 0) data.clear();
    return data;
}

// Reads a UTF-8 text file from the archive.
std::string ZipArchive::read_text_file(const std::string &archive_path) const {
    const std::vector<std::uint8_t> data = read_file(archive_path);
    return std::string(data.begin(), data.end());
}

// Extracts an archive file to the requested output path.
bool ZipArchive::extract_file(const std::string &archive_path, const std::filesystem::path &output_path) const {
    const std::vector<std::uint8_t> data = read_file(archive_path);
    const auto entry = find_entry_name(archive_path);
    zip_stat_t stat;
    zip_stat_init(&stat);
    if (entry.empty() || zip_stat(archive_, entry.c_str(), ZIP_FL_ENC_GUESS, &stat) != 0 ||
        stat.size != data.size()) return false;

    std::error_code ec;
    const std::filesystem::path parent = output_path.parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent, ec);
        if (ec) {
            return false;
        }
    }

    std::ofstream output(output_path, std::ios::binary);
    if (!output) {
        return false;
    }
    if (!data.empty()) {
        output.write(reinterpret_cast<const char *>(data.data()), static_cast<std::streamsize>(data.size()));
    }
    output.close();
    if (output.good()) return true;
    std::filesystem::remove(output_path, ec);
    return false;
}

// Adds or replaces a binary file in a writable archive.
bool ZipArchive::write_file(const std::string &archive_path, const std::vector<std::uint8_t> &data) {
    if (!archive_ || !writable_) {
        return false;
    }

    const std::string normalized = normalize_path(archive_path);
    if (normalized.empty() || is_directory_entry(normalized)) {
        return false;
    }

    void *buffer = nullptr;
    if (!data.empty()) {
        buffer = std::malloc(data.size());
        if (!buffer) {
            return false;
        }
        std::memcpy(buffer, data.data(), data.size());
    }

    zip_source_t *source = zip_source_buffer(archive_, buffer, data.size(), 1);
    if (!source) {
        std::free(buffer);
        return false;
    }

    const zip_int64_t index = zip_file_add(archive_, normalized.c_str(), source,
                                           ZIP_FL_OVERWRITE | ZIP_FL_ENC_UTF_8);
    if (index < 0) {
        zip_source_free(source);
        return false;
    }
    index_ready_ = false;
    return true;
}

// Adds or replaces a text file in a writable archive.
bool ZipArchive::write_file(const std::string &archive_path, const std::string &data) {
    const auto *begin = reinterpret_cast<const std::uint8_t *>(data.data());
    return write_file(archive_path, std::vector<std::uint8_t>(begin, begin + data.size()));
}

// Closes the archive and commits pending changes when writable.
bool ZipArchive::close() {
    if (!archive_) {
        return true;
    }

    zip *handle = archive_;
    archive_ = nullptr;
    writable_ = false;
    if (zip_close(handle) == 0) {
        return true;
    }
    zip_discard(handle);
    return false;
}

// Normalizes an internal archive path for portable lookups.
std::string ZipArchive::normalize_path(const std::string &archive_path) {
    std::string normalized = archive_path;
    std::replace(normalized.begin(), normalized.end(), '\\', '/');
    while (normalized.rfind("./", 0) == 0) normalized.erase(0, 2);
    if (normalized.empty() || normalized.front() == '/' || normalized.find(':') != std::string::npos)
        return {};
    std::string result;
    std::istringstream parts(normalized);
    std::string part;
    while (std::getline(parts, part, '/')) {
        if (part == "..") return {};
        if (part.empty() || part == ".") continue;
        if (!result.empty()) result += '/';
        result += part;
    }
    if (!result.empty() && normalized.back() == '/') result += '/';
    return result;
}

// Discards an open archive handle without committing changes.
void ZipArchive::reset() {
    index_ready_ = false;
    entries_.clear();
    folded_entries_.clear();
    if (archive_) {
        zip_discard(archive_);
        archive_ = nullptr;
    }
    writable_ = false;
}

// Indexes normalized identities while retaining original ZIP spellings for reads.
void ZipArchive::build_index() const {
    if (index_ready_ || !archive_) return;
    entries_.clear();
    folded_entries_.clear();
    std::unordered_set<std::string> ambiguous;
    const zip_int64_t count = zip_get_num_entries(archive_, 0);
    for (zip_int64_t i = 0; i < count; ++i) {
        const char *raw = zip_get_name(archive_, static_cast<zip_uint64_t>(i), ZIP_FL_ENC_GUESS);
        if (!raw) continue;
        const std::string normalized = normalize_path(raw);
        if (normalized.empty() || is_directory_entry(normalized)) continue;
        const std::string folded = lower_ascii(normalized);
        if (ambiguous.count(folded)) continue;
        const auto prior = folded_entries_.find(folded);
        if (prior != folded_entries_.end()) {
            entries_.erase(prior->second);
            folded_entries_.erase(prior);
            ambiguous.insert(folded);
            continue;
        }
        entries_.emplace(normalized, raw);
        folded_entries_.emplace(folded, normalized);
    }
    index_ready_ = true;
}

// Prefers exact identities, then an unambiguous ASCII case-insensitive match.
std::string ZipArchive::find_entry_name(const std::string &archive_path) const {
    build_index();
    const std::string target = normalize_path(archive_path);
    const auto exact = entries_.find(target);
    if (exact != entries_.end()) return exact->second;
    const auto folded = folded_entries_.find(lower_ascii(target));
    return folded == folded_entries_.end() ? std::string{} : entries_.at(folded->second);
}

} // namespace peraviz::archive
