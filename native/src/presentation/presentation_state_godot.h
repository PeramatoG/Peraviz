#pragma once
#include "presentation/dense_presentation_state.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {
class PeravizPresentationState : public RefCounted {
    GDCLASS(PeravizPresentationState, RefCounted)
protected:
    static void _bind_methods();
public:
    int64_t install(const PackedInt32Array &ids, const PackedFloat32Array &scales, const PackedInt32Array &routes);
    bool install_groups(const PackedInt32Array &representatives);
    void clear();
    void invalidate_renderer();
    Dictionary compose(int64_t generation, const PackedInt32Array &descriptors, const PackedInt32Array &integers,
            const PackedFloat32Array &values, bool trace);
    Dictionary get_sizes() const;
private:
    peraviz::presentation::DensePresentationState state_;
    // Fixed physical-output-sized payloads. The adapter releases its shared view before the next write.
    PackedInt32Array indices_masks_;
    PackedFloat32Array values_;
    PackedInt32Array group_indices_masks_;
    PackedFloat32Array group_values_;
};
} // namespace godot
