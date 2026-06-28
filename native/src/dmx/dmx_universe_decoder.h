#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

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
    void clear();

private:
    struct FixtureChannelBinding {
        int fixture_id = 0;
        int start_address = 0;
        int channel_type = 0;
        int bit_depth = 8;
        double scale_min = 0.0;
        double scale_max = 1.0;
    };

    static FixtureChannelBinding parse_binding(const Dictionary &binding);
    static double read_normalized_value(const PackedByteArray &frame, const FixtureChannelBinding &binding);
    static int bytes_for_bit_depth(int bit_depth);

    std::unordered_map<int, std::vector<FixtureChannelBinding>> bindings_by_universe_;
    std::unordered_map<int, PackedByteArray> previous_frames_by_universe_;
};

} // namespace godot
