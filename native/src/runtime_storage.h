#pragma once

#include <filesystem>
#include <memory>
#include <string>

namespace peraviz::runtime_storage {

std::filesystem::path runtime_root();
std::filesystem::path session_root();
std::filesystem::path cache_root();
void set_runtime_root_for_tests(std::filesystem::path root);
void reset_runtime_root_for_tests();
bool is_within_runtime_root(const std::filesystem::path &path);

class RuntimeDirectoryLease {
public:
    RuntimeDirectoryLease() = default;
    explicit RuntimeDirectoryLease(std::filesystem::path path);

    const std::filesystem::path &path() const;
    bool valid() const;

private:
    struct State;
    std::shared_ptr<State> state_;
};

class TemporaryWorkspace {
public:
    explicit TemporaryWorkspace(std::string prefix);
    TemporaryWorkspace(const TemporaryWorkspace &) = delete;
    TemporaryWorkspace &operator=(const TemporaryWorkspace &) = delete;
    TemporaryWorkspace(TemporaryWorkspace &&other) noexcept;
    TemporaryWorkspace &operator=(TemporaryWorkspace &&other) noexcept;
    ~TemporaryWorkspace();

    const std::filesystem::path &path() const;
    bool valid() const;
    RuntimeDirectoryLease transfer_to_runtime_lease();

private:
    std::filesystem::path path_;
    bool owns_ = false;
};

RuntimeDirectoryLease create_session_cache_directory(const std::string &prefix);
void cleanup_current_session();

} // namespace peraviz::runtime_storage
