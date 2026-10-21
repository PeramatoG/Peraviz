#pragma once
#include "presentation/dense_presentation_state.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {
// Main-thread Godot boundary: retained material RIDs never own or inspect SceneTree nodes.
class PresentationMaterialBindings {
public:
    bool install(size_t physical_count, const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes);
    void clear();
    size_t set_enabled(bool enabled);
    void invalidate();
    void apply(const peraviz::presentation::DensePresentationState &physical);
    PackedFloat32Array values(const RID &rid) const;
    // Reports actual material setters in the last applied batch.
    size_t writes() const { return writes_; }
    // Reports redundant shared-RID setters avoided in that batch.
    size_t avoided() const { return avoided_; }
private:
    struct Binding { RID rid; uint32_t owner=0, users=0; float scale=1, red=-1, green=-1, blue=-1, energy=-1; bool dirty=false; };
    std::vector<Binding> bindings_;
    std::vector<std::vector<uint32_t>> routes_;
    std::vector<uint32_t> dirty_;
    size_t writes_=0, avoided_=0;
    bool enabled_=true;
    const StringName emission_{"emission"}, energy_{"emission_energy_multiplier"};
};
}
