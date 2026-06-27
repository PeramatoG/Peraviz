#include "mvrxchange/mvr_xchange_service_name.h"

#include <cstdlib>
#include <iostream>

namespace {

// Verifies that a condition is true and prints a useful failure message.
void expect_true(bool value, const char *message) {
    if (!value) {
        std::cerr << message << std::endl;
        std::exit(1);
    }
}

} // namespace

// Runs lightweight MVR-xchange service-name parsing checks.
int main() {
    using namespace peraviz::mvrxchange;
    ParsedServiceName parsed = parse_mvr_xchange_service_name("Perastage@Default._mvrxchange._tcp.local.");
    expect_true(parsed.valid, "Expected service name to parse");
    expect_true(parsed.station_name == "Perastage", "Expected station name");
    expect_true(parsed.group == "Default", "Expected group name");
    expect_true(mvr_xchange_service_matches_group("Desk@Default._mvrxchange._tcp.local.", "Default"), "Expected group match");
    expect_true(!mvr_xchange_service_matches_group("Desk@Show._mvrxchange._tcp.local.", "Default"), "Expected group mismatch");
    expect_true(normalize_group_name("") == "Default", "Expected default group fallback");
    return 0;
}
