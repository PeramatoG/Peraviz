#include "table_model/runtime_table.h"

namespace peraviz::table_model {

// Creates a runtime table using the provided stable schema metadata.
RuntimeTable::RuntimeTable(RuntimeTableSchema schema) : schema_(std::move(schema)) {}

// Removes all rows while preserving the table schema.
void RuntimeTable::clear() {
    rows_by_uuid_.clear();
}

// Returns the stable schema associated with this table.
const RuntimeTableSchema &RuntimeTable::schema() const {
    return schema_;
}

// Inserts or replaces a complete row addressed by UUID.
bool RuntimeTable::set_row(const std::string &row_uuid, RuntimeTableRow row) {
    if (row_uuid.empty() || static_cast<int>(row.size()) != schema_.column_count()) {
        return false;
    }
    rows_by_uuid_[row_uuid] = std::move(row);
    return true;
}

// Returns a row by UUID when it exists.
const RuntimeTableRow *RuntimeTable::get_row(const std::string &row_uuid) const {
    const auto it = rows_by_uuid_.find(row_uuid);
    if (it == rows_by_uuid_.end()) {
        return nullptr;
    }
    return &it->second;
}

// Returns a cell by UUID and column index when both are valid.
std::optional<RuntimeCellValue> RuntimeTable::get_cell(const std::string &row_uuid, int column_index) const {
    const RuntimeTableRow *row = get_row(row_uuid);
    if (!row || column_index < 0 || column_index >= schema_.column_count()) {
        return std::nullopt;
    }
    return (*row)[static_cast<std::size_t>(column_index)];
}

// Updates a single cell by UUID and column index for validation and future sync tests.
bool RuntimeTable::set_cell(const std::string &row_uuid, int column_index, RuntimeCellValue value) {
    auto it = rows_by_uuid_.find(row_uuid);
    if (it == rows_by_uuid_.end() || column_index < 0 || column_index >= schema_.column_count()) {
        return false;
    }
    it->second[static_cast<std::size_t>(column_index)] = std::move(value);
    return true;
}

// Lists row UUIDs in deterministic order.
std::vector<std::string> RuntimeTable::row_uuids() const {
    std::vector<std::string> ids;
    ids.reserve(rows_by_uuid_.size());
    for (const auto &entry : rows_by_uuid_) {
        ids.push_back(entry.first);
    }
    return ids;
}

// Lists rows in deterministic UUID order.
std::vector<RuntimeTableRowRecord> RuntimeTable::rows() const {
    std::vector<RuntimeTableRowRecord> out;
    out.reserve(rows_by_uuid_.size());
    for (const auto &entry : rows_by_uuid_) {
        out.push_back(RuntimeTableRowRecord{entry.first, entry.second});
    }
    return out;
}

} // namespace peraviz::table_model
