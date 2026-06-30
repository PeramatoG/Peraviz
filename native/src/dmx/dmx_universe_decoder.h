#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

class PeravizDmxUniverseDecoder : public RefCounted {
    GDCLASS(PeravizDmxUniverseDecoder, RefCounted)

protected:
    static void _bind_methods();

public:
    void set_fixture_bindings(int universe_id, const Array &bindings);
    Array decode_universe(int universe_id, const PackedByteArray &current_frame);
    PackedFloat32Array decode_universe_compact(int universe_id, const PackedByteArray &current_frame);
    void set_fixture_render_params(int fixture_id, const Dictionary &render_params);
    PackedFloat32Array decode_universe_render_ready(int universe_id, const PackedByteArray &current_frame);
    PackedFloat32Array decode_universe_visual_render_ready(int universe_id, const PackedByteArray &current_frame);
    void clear();

private:
    struct FixtureRenderParams {
        double luminous_flux = 10000.0;
        double beam_angle_default = 25.0;
        double zoom_min_deg = -1.0;
        double zoom_max_deg = -1.0;
        bool has_zoom = false;
        bool has_color_temperature = false;
        double color_temp_k = 5600.0;
        double spot_multiplier = 1.0;
        double beam_multiplier = 20.0;
    };

    struct FixtureVisualState {
        bool initialized = false;
        float compact_values[13] = {};
        float render_values[9] = {};
    };

    struct FixtureChannelBinding {
        int fixture_id = 0;
        int start_address = 0;
        int fine_address = -1;
        int ultra_fine_address = -1;
        int channel_type = 0;
        int bit_depth = 8;
        double scale_min = 0.0;
        double scale_max = 1.0;
    };

    static FixtureChannelBinding parse_binding(const Dictionary &binding);
    static Dictionary read_channel_value(const PackedByteArray &frame, const FixtureChannelBinding &binding);
    static double read_normalized_value(const PackedByteArray &frame, const FixtureChannelBinding &binding);
    static PackedInt32Array read_channel_bytes(const PackedByteArray &frame, const FixtureChannelBinding &binding);
    static int address_for_byte_index(const FixtureChannelBinding &binding, int byte_index);
    static int bytes_for_bit_depth(int bit_depth);
    static int compact_index_for_channel_type(int channel_type);
    static double compact_value_at(const PackedFloat32Array &compact, int base, int compact_index);
    static void append_render_ready_values(PackedFloat32Array &out, const PackedFloat32Array &compact, int base, const FixtureRenderParams &params);
    static bool visual_value_changed(float previous_value, float current_value, float epsilon);
    static bool fixture_visual_state_changed(FixtureVisualState &state, const PackedFloat32Array &compact, int base);

    std::unordered_map<int, std::vector<FixtureChannelBinding>> bindings_by_universe_;
    std::unordered_map<int, PackedByteArray> previous_frames_by_universe_;
    std::unordered_map<int, FixtureRenderParams> render_params_by_fixture_;
    std::unordered_map<int, FixtureVisualState> visual_state_by_fixture_;
};

} // namespace godot
