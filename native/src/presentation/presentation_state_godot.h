#pragma once
#include "presentation/render_group_projection.h"
#include "presentation/presentation_material_bindings.h"
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
    bool install_render_rows(const PackedInt32Array &membership, const PackedInt32Array &classes);
    bool install_materials(const Array &rids, const PackedInt32Array &owners, const PackedFloat32Array &scales, const PackedInt32Array &routes);
    int64_t set_materials_enabled(bool enabled);
    PackedFloat32Array physical_values(int32_t index) const;
    PackedFloat32Array material_values(const RID &rid) const;
    void clear();
    void invalidate_renderer();
    Dictionary compose(int64_t generation, const PackedInt32Array &descriptors, const PackedInt32Array &integers,
            const PackedFloat32Array &values, bool trace);
    Dictionary get_sizes() const;
private:
    peraviz::presentation::DensePresentationState state_;
    peraviz::presentation::RenderGroupProjection projection_;
    PresentationMaterialBindings materials_;
    bool diagnostic_skip_lens_writes_=false, lens_writes_suppressed_=false;
    // Exactly renderer-row-sized borrowed buffers; no physical/group duplicate payloads.
    PackedInt32Array indices_masks_;
    PackedFloat32Array values_;
};
} // namespace godot
