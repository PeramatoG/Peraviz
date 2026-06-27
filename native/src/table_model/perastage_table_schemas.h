#pragma once

#include "table_model/runtime_table.h"

#include <map>
#include <string>

namespace peraviz::table_model {

extern const char *const kFixturesTableId;
extern const char *const kTrussesTableId;
extern const char *const kSceneObjectsTableId;

RuntimeTableSchema fixtures_schema();
RuntimeTableSchema trusses_schema();
RuntimeTableSchema scene_objects_schema();
std::map<std::string, RuntimeTable> create_perastage_runtime_tables();

} // namespace peraviz::table_model
