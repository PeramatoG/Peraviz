#pragma once

#include "runtime/peraviz_visual_runtime.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class PeravizVisualRuntime : public RefCounted {
    GDCLASS(PeravizVisualRuntime, RefCounted)

protected:
    static void _bind_methods();

public:
    void clear();
    void set_fixture_bindings(const Array &bindings);
    void set_fixture_render_params(int fixture_id, const Dictionary &render_params);
    void submit_universe_frame(int universe_id, const PackedByteArray &data);
    Dictionary consume_latest_visual_frame();
    Dictionary get_visual_frame_schema() const;
    Dictionary get_stats() const;

private:
    static peraviz::runtime::FixtureChannelBinding parse_binding(const Dictionary &binding);
    static peraviz::runtime::FixtureRenderParams parse_render_params(const Dictionary &render_params);
    static Dictionary stats_to_dictionary(const peraviz::runtime::VisualFrameStats &stats);

    peraviz::runtime::PeravizVisualRuntimeCore core_;
};

} // namespace godot
