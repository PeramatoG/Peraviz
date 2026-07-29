#include "runtime_storage.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <random>
#include <sstream>
#include <system_error>
#include <thread>

namespace {

std::filesystem::path g_runtime_root_override;

// Returns a process-local session identifier that avoids timestamp-only names.
std::string session_id() {
    static const std::string value = [] {
        std::random_device rd;
        std::ostringstream ss;
        ss << "session-" << std::chrono::steady_clock::now().time_since_epoch().count()
           << "-" << std::this_thread::get_id() << "-" << std::hex << rd();
        return ss.str();
    }();
    return value;
}

// Returns a filesystem-safe identifier segment.
std::string sanitize_segment(std::string value) {
    for (char &ch : value) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if (c < 32 || ch == '/' || ch == '\\' || ch == ':' || ch == '*' || ch == '?' || ch == '"' || ch == '<' || ch == '>' || ch == '|') {
            ch = '_';
        }
    }
    if (value.empty()) {
        return "workspace";
    }
    return value;
}

// Creates a unique directory under a trusted parent path.
std::filesystem::path create_unique_directory(const std::filesystem::path &parent, const std::string &prefix) {
    std::error_code ec;
    std::filesystem::create_directories(parent, ec);
    if (ec) {
        std::cerr << "[PeravizRuntimeStorage] unable to create parent " << parent.u8string() << ": " << ec.message() << "\n";
        return {};
    }

    std::random_device rd;
    for (int attempt = 0; attempt < 64; ++attempt) {
        std::ostringstream name;
        name << sanitize_segment(prefix) << "-" << std::chrono::steady_clock::now().time_since_epoch().count()
             << "-" << std::hex << rd() << "-" << attempt;
        const std::filesystem::path candidate = parent / name.str();
        if (std::filesystem::create_directory(candidate, ec)) {
            std::cerr << "[PeravizRuntimeStorage] created workspace " << candidate.u8string() << "\n";
            return candidate;
        }
        if (ec) {
            std::cerr << "[PeravizRuntimeStorage] unable to create workspace " << candidate.u8string() << ": " << ec.message() << "\n";
            return {};
        }
        ec.clear();
    }
    return {};
}

// Removes an owned directory only when it remains inside the Peraviz runtime root.
void remove_owned_directory(const std::filesystem::path &path) noexcept {
    if (path.empty() || !peraviz::runtime_storage::is_within_runtime_root(path)) {
        std::cerr << "[PeravizRuntimeStorage] refused cleanup outside runtime root: " << path.u8string() << "\n";
        return;
    }
    std::error_code ec;
    const auto removed = std::filesystem::remove_all(path, ec);
    if (ec) {
        std::cerr << "[PeravizRuntimeStorage] cleanup failed for " << path.u8string() << ": " << ec.message() << "\n";
    } else {
        std::cerr << "[PeravizRuntimeStorage] removed workspace " << path.u8string() << " entries=" << removed << "\n";
    }
}

} // namespace

namespace peraviz::runtime_storage {

struct RuntimeDirectoryLease::State {
    explicit State(std::filesystem::path owned_path) : path(std::move(owned_path)) {}
    ~State() { remove_owned_directory(path); }
    std::filesystem::path path;
};

// Returns the Peraviz-owned runtime root under the system temp directory.
std::filesystem::path runtime_root() {
    if (!g_runtime_root_override.empty()) {
        return g_runtime_root_override;
    }
    return std::filesystem::temp_directory_path() / "Peraviz";
}

// Returns the current process session root for scene-scoped runtime data.
std::filesystem::path session_root() {
    return runtime_root() / "sessions" / session_id();
}

// Returns the current session cache root for regenerable extracted assets.
std::filesystem::path cache_root() {
    return session_root() / "cache" / "v1";
}

// Overrides the runtime root for isolated tests.
void set_runtime_root_for_tests(std::filesystem::path root) {
    g_runtime_root_override = std::move(root);
}

// Clears the test runtime root override.
void reset_runtime_root_for_tests() {
    g_runtime_root_override.clear();
}

// Returns whether a path is lexically contained by the Peraviz runtime root.
bool is_within_runtime_root(const std::filesystem::path &path) {
    const std::filesystem::path root = runtime_root().lexically_normal();
    const std::filesystem::path target = path.lexically_normal();
    auto root_it = root.begin();
    auto target_it = target.begin();
    for (; root_it != root.end(); ++root_it, ++target_it) {
        if (target_it == target.end() || *root_it != *target_it) {
            return false;
        }
    }
    return true;
}

// Creates a shared lease for an existing runtime-owned directory.
RuntimeDirectoryLease::RuntimeDirectoryLease(std::filesystem::path path)
    : state_(std::make_shared<State>(std::move(path))) {}

// Returns the leased directory path.
const std::filesystem::path &RuntimeDirectoryLease::path() const {
    static const std::filesystem::path empty;
    return state_ ? state_->path : empty;
}

// Returns whether this lease owns a runtime directory.
bool RuntimeDirectoryLease::valid() const {
    return state_ != nullptr && !state_->path.empty();
}

// Creates a move-only operation workspace.
TemporaryWorkspace::TemporaryWorkspace(std::string prefix)
    : path_(create_unique_directory(session_root() / "operations", prefix)), owns_(!path_.empty()) {}

// Moves workspace ownership from another instance.
TemporaryWorkspace::TemporaryWorkspace(TemporaryWorkspace &&other) noexcept
    : path_(std::move(other.path_)), owns_(other.owns_) {
    other.owns_ = false;
}

// Replaces workspace ownership with another instance.
TemporaryWorkspace &TemporaryWorkspace::operator=(TemporaryWorkspace &&other) noexcept {
    if (this != &other) {
        if (owns_) {
            remove_owned_directory(path_);
        }
        path_ = std::move(other.path_);
        owns_ = other.owns_;
        other.owns_ = false;
    }
    return *this;
}

// Removes the workspace when it remains operation-owned.
TemporaryWorkspace::~TemporaryWorkspace() {
    if (owns_) {
        remove_owned_directory(path_);
    }
}

// Returns the workspace directory path.
const std::filesystem::path &TemporaryWorkspace::path() const {
    return path_;
}

// Returns whether the workspace owns a directory.
bool TemporaryWorkspace::valid() const {
    return owns_ && !path_.empty();
}

// Transfers operation ownership to a shared scene/session lease.
RuntimeDirectoryLease TemporaryWorkspace::transfer_to_runtime_lease() {
    if (!owns_) {
        return {};
    }
    owns_ = false;
    return RuntimeDirectoryLease(path_);
}

// Creates a shared session-cache directory lease.
RuntimeDirectoryLease create_session_cache_directory(const std::string &prefix) {
    const std::filesystem::path path = create_unique_directory(cache_root(), prefix);
    if (path.empty()) {
        return {};
    }
    return RuntimeDirectoryLease(path);
}

// Removes the current session root during clean shutdown.
void cleanup_current_session() {
    remove_owned_directory(session_root());
}

} // namespace peraviz::runtime_storage
