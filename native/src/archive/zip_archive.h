#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

struct zip;

namespace peraviz::archive {

class ZipArchive {
public:
    ZipArchive();
    ~ZipArchive();

    ZipArchive(const ZipArchive &) = delete;
    ZipArchive &operator=(const ZipArchive &) = delete;

    ZipArchive(ZipArchive &&other) noexcept;
    ZipArchive &operator=(ZipArchive &&other) noexcept;

    bool open_read(const std::filesystem::path &path);
    bool open_create_or_modify(const std::filesystem::path &path);
    bool is_open() const;
    std::vector<std::string> list_files() const;
    bool file_exists(const std::string &archive_path) const;
    std::vector<std::uint8_t> read_file(const std::string &archive_path) const;
    std::string read_text_file(const std::string &archive_path) const;
    bool extract_file(const std::string &archive_path, const std::filesystem::path &output_path) const;
    bool write_file(const std::string &archive_path, const std::vector<std::uint8_t> &data);
    bool write_file(const std::string &archive_path, const std::string &data);
    bool close();

    static std::string normalize_path(const std::string &archive_path);

private:
    zip *archive_ = nullptr;
    bool writable_ = false;

    void reset();
    std::string find_entry_name(const std::string &archive_path) const;
};

} // namespace peraviz::archive
