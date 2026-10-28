#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "scene_model.h"
#include "scene_setup_preparation.h"
#include <future>
#include <optional>

namespace godot {

class PeravizLoader : public Object {
    GDCLASS(PeravizLoader, Object)

protected:
    static void _bind_methods();

public:
    Array load_mvr(const String &path, bool peraviz_debug_baseline = false,
                   bool peraviz_debug_coords = false);
    bool set_gdtf_model_detail(const String &detail);
    Dictionary load_3ds_mesh_data(const String &path) const;
    bool begin_load_mvr(const String &path, int universe_offset = -1);
    bool is_load_mvr_ready() const;
    String get_load_phase() const;
    Array finish_load_mvr();
    Dictionary get_load_metrics() const;
    Array get_fixtures_patch() const;
    Dictionary build_fixture_dmx_bindings(int universe_offset = -1);
    Dictionary compile_visual_runtime_scene(int universe_offset = -1) const;
    Dictionary build_fixture_dimmer_bindings(int universe_offset = -1);
    Dictionary get_runtime_table_schema(const String &table_id) const;
    Array get_runtime_table_rows(const String &table_id) const;
    Dictionary get_runtime_table_row(const String &table_id, const String &row_uuid) const;
    Variant get_runtime_table_cell(const String &table_id, const String &row_uuid, int column_index) const;
    bool set_runtime_table_cell_for_test(const String &table_id, const String &row_uuid, int column_index, const Variant &value);

private:
    Array serialize_scene_nodes(bool baseline_debug, bool coords_debug);
    peraviz::GdtfModelDetail model_detail_ = peraviz::GdtfModelDetail::Default;
    peraviz::SceneSetupProgress load_progress_;
    std::future<peraviz::SceneSetupPreparation> preparation_;
    std::optional<peraviz::SceneSetupPreparation> prepared_;
    peraviz::SceneModel last_scene_model_;
    mutable Dictionary load_metrics_;
};

} // namespace godot
