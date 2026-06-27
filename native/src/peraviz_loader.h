#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "scene_model.h"

namespace godot {

class PeravizLoader : public Object {
    GDCLASS(PeravizLoader, Object)

protected:
    static void _bind_methods();

public:
    Array load_mvr(const String &path, bool peraviz_debug_baseline = false,
                   bool peraviz_debug_coords = false);
    Dictionary load_3ds_mesh_data(const String &path) const;
    Array get_fixtures_patch() const;
    Dictionary build_fixture_dmx_bindings(int universe_offset = -1) const;
    Dictionary build_fixture_dimmer_bindings(int universe_offset = -1) const;
    Dictionary get_runtime_table_schema(const String &table_id) const;
    Array get_runtime_table_rows(const String &table_id) const;
    Dictionary get_runtime_table_row(const String &table_id, const String &row_uuid) const;
    Variant get_runtime_table_cell(const String &table_id, const String &row_uuid, int column_index) const;
    bool set_runtime_table_cell_for_test(const String &table_id, const String &row_uuid, int column_index, const Variant &value);

private:
    peraviz::SceneModel last_scene_model_;
};

} // namespace godot
