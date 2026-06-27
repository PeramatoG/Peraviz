#include "table_model/runtime_table_schema.h"

namespace peraviz::table_model {

// Returns the number of columns declared by the schema.
int RuntimeTableSchema::column_count() const {
    return static_cast<int>(columns.size());
}

// Returns schema metadata for a column index when it exists.
const RuntimeTableColumn *RuntimeTableSchema::column_at(int column_index) const {
    if (column_index < 0 || column_index >= column_count()) {
        return nullptr;
    }
    return &columns[static_cast<std::size_t>(column_index)];
}

// Converts a value kind to its stable string representation.
const char *to_string(RuntimeColumnValueKind kind) {
    switch (kind) {
        case RuntimeColumnValueKind::Empty:
            return "empty";
        case RuntimeColumnValueKind::String:
            return "string";
        case RuntimeColumnValueKind::Integer:
            return "integer";
        case RuntimeColumnValueKind::Decimal:
            return "decimal";
        case RuntimeColumnValueKind::Boolean:
            return "boolean";
    }
    return "string";
}

} // namespace peraviz::table_model
