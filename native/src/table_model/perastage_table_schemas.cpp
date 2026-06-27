#include "table_model/perastage_table_schemas.h"

namespace peraviz::table_model {

const char *const kFixturesTableId = "fixtures";
const char *const kTrussesTableId = "trusses";
const char *const kSceneObjectsTableId = "scene_objects";

namespace {

// Creates a schema column with stable model metadata.
RuntimeTableColumn column(int index, const char *name, RuntimeColumnValueKind kind) {
    return RuntimeTableColumn{index, name, kind};
}

} // namespace

// Returns the Perastage-compatible fixture table schema.
RuntimeTableSchema fixtures_schema() {
    return RuntimeTableSchema{kFixturesTableId, 1, {
        column(0, "FixtureId", RuntimeColumnValueKind::Integer),
        column(1, "Name", RuntimeColumnValueKind::String),
        column(2, "Type", RuntimeColumnValueKind::String),
        column(3, "Layer", RuntimeColumnValueKind::String),
        column(4, "HangPosition", RuntimeColumnValueKind::String),
        column(5, "Universe", RuntimeColumnValueKind::Integer),
        column(6, "Channel", RuntimeColumnValueKind::Integer),
        column(7, "Mode", RuntimeColumnValueKind::String),
        column(8, "ChannelCount", RuntimeColumnValueKind::Integer),
        column(9, "ModelFile", RuntimeColumnValueKind::String),
        column(10, "PositionX", RuntimeColumnValueKind::Decimal),
        column(11, "PositionY", RuntimeColumnValueKind::Decimal),
        column(12, "PositionZ", RuntimeColumnValueKind::Decimal),
        column(13, "Roll", RuntimeColumnValueKind::Decimal),
        column(14, "Pitch", RuntimeColumnValueKind::Decimal),
        column(15, "Yaw", RuntimeColumnValueKind::Decimal),
        column(16, "Power", RuntimeColumnValueKind::Decimal),
        column(17, "Weight", RuntimeColumnValueKind::Decimal),
        column(18, "Category", RuntimeColumnValueKind::String),
        column(19, "VisualColor", RuntimeColumnValueKind::String),
        column(20, "MvrColor", RuntimeColumnValueKind::String),
    }};
}

// Returns the Perastage-compatible truss table schema.
RuntimeTableSchema trusses_schema() {
    return RuntimeTableSchema{kTrussesTableId, 1, {
        column(0, "Name", RuntimeColumnValueKind::String),
        column(1, "Layer", RuntimeColumnValueKind::String),
        column(2, "ModelFile", RuntimeColumnValueKind::String),
        column(3, "HangPosition", RuntimeColumnValueKind::String),
        column(4, "PositionX", RuntimeColumnValueKind::Decimal),
        column(5, "PositionY", RuntimeColumnValueKind::Decimal),
        column(6, "PositionZ", RuntimeColumnValueKind::Decimal),
        column(7, "Roll", RuntimeColumnValueKind::Decimal),
        column(8, "Pitch", RuntimeColumnValueKind::Decimal),
        column(9, "Yaw", RuntimeColumnValueKind::Decimal),
        column(10, "Manufacturer", RuntimeColumnValueKind::String),
        column(11, "Model", RuntimeColumnValueKind::String),
        column(12, "Length", RuntimeColumnValueKind::Decimal),
        column(13, "Width", RuntimeColumnValueKind::Decimal),
        column(14, "Height", RuntimeColumnValueKind::Decimal),
        column(15, "Weight", RuntimeColumnValueKind::Decimal),
        column(16, "Load", RuntimeColumnValueKind::Decimal),
    }};
}

// Returns the Perastage-compatible scene object table schema.
RuntimeTableSchema scene_objects_schema() {
    return RuntimeTableSchema{kSceneObjectsTableId, 1, {
        column(0, "Name", RuntimeColumnValueKind::String),
        column(1, "Layer", RuntimeColumnValueKind::String),
        column(2, "ModelFile", RuntimeColumnValueKind::String),
        column(3, "PositionX", RuntimeColumnValueKind::Decimal),
        column(4, "PositionY", RuntimeColumnValueKind::Decimal),
        column(5, "PositionZ", RuntimeColumnValueKind::Decimal),
        column(6, "Roll", RuntimeColumnValueKind::Decimal),
        column(7, "Pitch", RuntimeColumnValueKind::Decimal),
        column(8, "Yaw", RuntimeColumnValueKind::Decimal),
    }};
}

// Creates empty runtime tables for all supported Perastage-compatible schemas.
std::map<std::string, RuntimeTable> create_perastage_runtime_tables() {
    std::map<std::string, RuntimeTable> tables;
    tables.emplace(kFixturesTableId, RuntimeTable(fixtures_schema()));
    tables.emplace(kTrussesTableId, RuntimeTable(trusses_schema()));
    tables.emplace(kSceneObjectsTableId, RuntimeTable(scene_objects_schema()));
    return tables;
}

} // namespace peraviz::table_model
