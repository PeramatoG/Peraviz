#include "presentation/render_group_manifest.h"
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace peraviz::presentation {
// Serializes setup-only renderer membership and optical geometry, never live physical rows.
godot::Array serialize_render_groups(const std::vector<RenderEmitterGroup> &groups, int32_t fixture_id) {
    godot::Array out;
    for (const auto &group:groups) {
        if (group.fixture_id!=fixture_id) continue;
        godot::Dictionary d;
        d["id"]=group.id; d["presentation_class"]=int32_t(group.presentation);
        godot::PackedInt32Array physical, controls;
        for (int32_t id:group.physical_ids) physical.push_back(id);
        for (int32_t id:group.control_group_ids) controls.push_back(id);
        d["physical_ids"]=physical; d["control_group_ids"]=controls;
        d["anchor_geometry_key"]=godot::String(group.anchor_geometry_key.c_str());
        d["origin"]=godot::Vector3(group.origin[0],group.origin[1],group.origin[2]);
        d["direction"]=godot::Vector3(group.direction[0],group.direction[1],group.direction[2]);
        d["aperture_radius"]=group.aperture_radius; d["nominal_flux"]=group.nominal_flux;
        d["beam_angle"]=group.beam_angle; d["field_angle"]=group.field_angle; d["packing_density"]=group.packing_density;
        out.push_back(d);
    }
    return out;
}
// Exposes bounded reason counts once at setup rather than fixture/output logs in playback.
godot::Dictionary serialize_control_fallbacks(const ControlGroupFallbacks &f) {
    godot::Dictionary d;
    d["split_dimmer_authority"]=f.dimmer; d["split_color_authority"]=f.color;
    d["split_optics"]=f.optics; d["split_projector_gobo"]=f.projector_gobo;
    d["split_wheel"]=f.wheel; d["split_scaling"]=f.scaling; d["split_ambiguous"]=f.ambiguous;
    return d;
}
}
