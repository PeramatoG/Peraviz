#include "runtime_storage.h"

#include <filesystem>
#include <fstream>
#include <iostream>

namespace {

// Reports a test failure message.
int fail(const std::string &message) {
    std::cerr << message << "\n";
    return 1;
}

// Verifies operation workspaces are deleted by scope exit.
int test_temporary_workspace_cleanup() {
    std::filesystem::path workspace_path;
    {
        peraviz::runtime_storage::TemporaryWorkspace workspace("unit-op");
        if (!workspace.valid()) return fail("Expected a valid temporary workspace");
        workspace_path = workspace.path();
        std::ofstream(workspace_path / "marker.txt") << "ok";
        if (!std::filesystem::exists(workspace_path / "marker.txt")) return fail("Expected marker file");
    }
    if (std::filesystem::exists(workspace_path)) return fail("Expected workspace cleanup after scope exit");
    return 0;
}

// Verifies moved workspaces are deleted exactly once by the final owner.
int test_temporary_workspace_move() {
    std::filesystem::path workspace_path;
    {
        peraviz::runtime_storage::TemporaryWorkspace first("unit-move");
        workspace_path = first.path();
        peraviz::runtime_storage::TemporaryWorkspace second(std::move(first));
        if (!second.valid()) return fail("Expected moved workspace to remain valid");
        peraviz::runtime_storage::TemporaryWorkspace third("unit-other");
        third = std::move(second);
        if (!third.valid()) return fail("Expected move-assigned workspace to remain valid");
    }
    if (std::filesystem::exists(workspace_path)) return fail("Expected moved workspace cleanup");
    return 0;
}

// Verifies transferred leases keep files alive until the final shared owner is destroyed.
int test_runtime_lease_lifetime() {
    std::filesystem::path workspace_path;
    peraviz::runtime_storage::RuntimeDirectoryLease copied;
    {
        peraviz::runtime_storage::TemporaryWorkspace workspace("unit-lease");
        workspace_path = workspace.path();
        std::ofstream(workspace_path / "asset.txt") << "asset";
        peraviz::runtime_storage::RuntimeDirectoryLease lease = workspace.transfer_to_runtime_lease();
        copied = lease;
        if (!std::filesystem::exists(workspace_path / "asset.txt")) return fail("Expected leased asset to exist");
    }
    if (!std::filesystem::exists(workspace_path / "asset.txt")) return fail("Expected copied lease to keep asset alive");
    copied = {};
    if (std::filesystem::exists(workspace_path)) return fail("Expected final lease release to clean workspace");
    return 0;
}

} // namespace

// Runs runtime storage ownership tests against an isolated root.
int main() {
    const std::filesystem::path test_root = std::filesystem::temp_directory_path() / "peraviz_runtime_storage_test_root";
    std::filesystem::remove_all(test_root);
    peraviz::runtime_storage::set_runtime_root_for_tests(test_root);

    if (const int rc = test_temporary_workspace_cleanup(); rc != 0) return rc;
    if (const int rc = test_temporary_workspace_move(); rc != 0) return rc;
    if (const int rc = test_runtime_lease_lifetime(); rc != 0) return rc;

    peraviz::runtime_storage::cleanup_current_session();
    peraviz::runtime_storage::reset_runtime_root_for_tests();
    std::filesystem::remove_all(test_root);
    return 0;
}
