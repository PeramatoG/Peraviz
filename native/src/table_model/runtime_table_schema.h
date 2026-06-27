#pragma once

#include <string>
#include <vector>

namespace peraviz::table_model {

enum class RuntimeColumnValueKind {
    Empty,
    String,
    Integer,
    Decimal,
    Boolean,
};

struct RuntimeTableColumn {
    int index = -1;
    std::string name;
    RuntimeColumnValueKind value_kind = RuntimeColumnValueKind::String;
};

struct RuntimeTableSchema {
    std::string table_id;
    int schema_version = 1;
    std::vector<RuntimeTableColumn> columns;

    int column_count() const;
    const RuntimeTableColumn *column_at(int column_index) const;
};

const char *to_string(RuntimeColumnValueKind kind);

} // namespace peraviz::table_model
