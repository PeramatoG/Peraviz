#include "table_model/perastage_table_schemas.h"

#include <iostream>
#include <string>

namespace {

// Records a validation failure when a condition is false.
bool expect_true(bool condition, const std::string &message) {
    if (!condition) {
        std::cerr << message << '\n';
        return false;
    }
    return true;
}

} // namespace

// Validates Perastage-compatible runtime table schemas and safe row access.
int main() {
    using namespace peraviz::table_model;
    bool ok = true;
    const auto fixtures = fixtures_schema();
    const auto trusses = trusses_schema();
    const auto objects = scene_objects_schema();

    ok &= expect_true(fixtures.column_count() == 21, "fixture schema column count must be 21");
    ok &= expect_true(trusses.column_count() == 17, "truss schema column count must be 17");
    ok &= expect_true(objects.column_count() == 9, "scene object schema column count must be 9");
    ok &= expect_true(fixtures.column_at(0)->name == "FixtureId", "fixture column 0 must be FixtureId");
    ok &= expect_true(fixtures.column_at(7)->name == "Mode", "fixture column 7 must be Mode");
    ok &= expect_true(fixtures.column_at(10)->name == "PositionX", "fixture column 10 must be PositionX");
    ok &= expect_true(fixtures.column_at(20)->name == "MvrColor", "fixture column 20 must be MvrColor");
    ok &= expect_true(trusses.column_at(0)->name == "Name", "truss column 0 must be Name");
    ok &= expect_true(trusses.column_at(4)->name == "PositionX", "truss column 4 must be PositionX");
    ok &= expect_true(trusses.column_at(16)->name == "Load", "truss column 16 must be Load");
    ok &= expect_true(objects.column_at(0)->name == "Name", "scene object column 0 must be Name");
    ok &= expect_true(objects.column_at(3)->name == "PositionX", "scene object column 3 must be PositionX");
    ok &= expect_true(objects.column_at(8)->name == "Yaw", "scene object column 8 must be Yaw");

    auto tables = create_perastage_runtime_tables();
    auto fixtures_it = tables.find(kFixturesTableId);
    ok &= expect_true(fixtures_it != tables.end(), "fixtures table id must exist");
    RuntimeTableRow row(fixtures.column_count());
    row[0] = int64_t{101};
    row[1] = std::string("Fixture 101");
    ok &= expect_true(fixtures_it->second.set_row("fixture-uuid", row), "row insert must succeed");
    ok &= expect_true(fixtures_it->second.get_row("fixture-uuid") != nullptr, "row must be retrievable by UUID");
    ok &= expect_true(fixtures_it->second.get_row("missing") == nullptr, "missing row must fail safely");
    ok &= expect_true(!fixtures_it->second.get_cell("fixture-uuid", 99).has_value(), "invalid column must fail safely");
    ok &= expect_true(tables.find("invalid") == tables.end(), "invalid table id must fail safely");

    return ok ? 0 : 1;
}
