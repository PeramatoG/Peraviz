#pragma once

#include "table_model/runtime_table_schema.h"

#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace peraviz::table_model {

using RuntimeCellValue = std::variant<std::monostate, std::string, int64_t, double, bool>;
using RuntimeTableRow = std::vector<RuntimeCellValue>;

struct RuntimeTableRowRecord {
    std::string row_uuid;
    RuntimeTableRow cells;
};

class RuntimeTable {
public:
    explicit RuntimeTable(RuntimeTableSchema schema = {});

    void clear();
    const RuntimeTableSchema &schema() const;
    bool set_row(const std::string &row_uuid, RuntimeTableRow row);
    const RuntimeTableRow *get_row(const std::string &row_uuid) const;
    std::optional<RuntimeCellValue> get_cell(const std::string &row_uuid, int column_index) const;
    bool set_cell(const std::string &row_uuid, int column_index, RuntimeCellValue value);
    std::vector<std::string> row_uuids() const;
    std::vector<RuntimeTableRowRecord> rows() const;

private:
    RuntimeTableSchema schema_;
    std::map<std::string, RuntimeTableRow> rows_by_uuid_;
};

} // namespace peraviz::table_model
