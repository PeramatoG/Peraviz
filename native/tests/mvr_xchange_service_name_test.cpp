#include "mvrxchange/mvr_xchange_service_name.h"
#include "mvrxchange/mvr_xchange_transfer.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>

namespace {

// Reports a failed test expectation and exits.
void expect_true(bool condition, const char *message) {
    if (!condition) {
        std::cerr << message << std::endl;
        std::exit(1);
    }
}

}

// Runs lightweight MVR-xchange parsing and file finalization checks.
int main() {
    using namespace peraviz::mvrxchange;
    ParsedServiceName parsed = parse_mvr_xchange_service_name("Perastage@Default._mvrxchange._tcp.local.");
    expect_true(parsed.valid, "Expected valid service name");
    expect_true(parsed.station_name == "Perastage", "Expected station name");
    expect_true(parsed.group == "Default", "Expected group");
    expect_true(mvr_xchange_service_matches_group("Desk@Default._mvrxchange._tcp.local.", "Default"), "Expected group match");
    expect_true(!mvr_xchange_service_matches_group("Desk@Show._mvrxchange._tcp.local.", "Default"), "Expected group mismatch");

    StationInfo station;
    station.service_name = "Perastage@Default._mvrxchange._tcp.local.";
    station.station_name = "Perastage";
    MvrXchangeCommitInfo commit = parse_commit_message("{\"Type\":\"MVR_COMMIT\",\"FileUUID\":\"abc\",\"Message\":\"Published\"}", station);
    expect_true(commit.file_uuid == "abc", "Expected parsed commit file UUID");
    expect_true(build_line_message("MVR_REQUEST", "abc").find("MVR_REQUEST") != std::string::npos, "Expected request message type");

    const std::filesystem::path temp_dir = std::filesystem::temp_directory_path() / "peraviz_mvr_xchange_test";
    std::filesystem::create_directories(temp_dir);
    const std::filesystem::path target = temp_dir / "received.mvr";
    std::string error;
    expect_true(write_completed_mvr_file(target.string(), "PK\003\004test", error), "Expected safe MVR write to succeed");
    expect_true(std::filesystem::exists(target), "Expected final MVR path");
    expect_true(!std::filesystem::exists(target.string() + ".part"), "Expected no remaining part file");
    std::filesystem::remove_all(temp_dir);
    return 0;
}
