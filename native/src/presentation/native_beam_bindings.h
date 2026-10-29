#pragma once
#include "presentation/render_group_projection.h"
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {
struct NativeBeamApplyStats {
    size_t applied=0,changed=0,unchanged=0,visibility=0,parameters=0,dynamic=0,stale=0;
};
// Main-thread renderer cache only. No semantic state or worker-visible Godot objects.
class NativeBeamBindings {
public:
    bool install(const PackedInt64Array &objects,const PackedFloat64Array &thresholds);
    void clear();
    bool install_group_materials(const Array &materials);
    void invalidate(uint32_t row);
    // Identifies the existing shared-uniform route without material inspection during playback.
    bool uses_group_material(uint32_t row) const { return row<entries_.size() && entries_[row].group>=0; }
    void set_policy(bool enabled,double multiplier);
    NativeBeamApplyStats apply(const std::vector<peraviz::presentation::PreparedRenderRow> &rows,int32_t *fallback,size_t &fallback_count);
    // Reports admitted weak renderer bindings without scanning scene resources.
    size_t count() const { return count_; }
    // Reports retained resource-cache bytes separately from physical state.
    size_t buffer_bytes() const { return entries_.capacity()*sizeof(Entry); }
private:
    struct Entry { uint64_t object=0; Color dynamic; double threshold=0.015; bool known=false; int32_t group=-1; };
    struct Group { RID rid; Color dynamic; bool known=false; };
    std::vector<Group> groups_;
    std::vector<Entry> entries_;
    size_t count_=0;
    bool enabled_=false;
    double multiplier_=1;
    StringName group_dynamic_{"control_group_dynamic_state"},dynamic_{"beam_dynamic_state"},maximum_{"intensity_max"};
};
} // namespace godot
