#include "peraviz_debug_runtime.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <array>

namespace peraviz::debug_runtime {
namespace {

bool g_baseline_debug_enabled = false;
bool g_coordinate_debug_enabled = false;

// Describes the purpose of vec to string.
godot::String vec_to_string(const std::array<float, 3> &v) {
    godot::String out("(");
    out += godot::String::num(v[0]);
    out += godot::String(", ");
    out += godot::String::num(v[1]);
    out += godot::String(", ");
    out += godot::String::num(v[2]);
    out += godot::String(")");
    return out;
}

// Describes the purpose of vec to string.
godot::String vec_to_string(const peraviz::Vec3 &v) {
    godot::String out("(");
    out += godot::String::num(v.x);
    out += godot::String(", ");
    out += godot::String::num(v.y);
    out += godot::String(", ");
    out += godot::String::num(v.z);
    out += godot::String(")");
    return out;
}

// Describes the purpose of matrix to string.
godot::String matrix_to_string(const Matrix &m) {
    godot::String out("u=");
    out += vec_to_string(m.u);
    out += godot::String(" v=");
    out += vec_to_string(m.v);
    out += godot::String(" w=");
    out += vec_to_string(m.w);
    out += godot::String(" o=");
    out += vec_to_string(m.o);
    return out;
}

// Describes the purpose of scene transform to string.
godot::String scene_transform_to_string(const SceneTransform &transform) {
    godot::String out("pos=");
    out += vec_to_string(transform.position);
    out += godot::String(" basis_x=");
    out += vec_to_string(transform.basis_x);
    out += godot::String(" basis_y=");
    out += vec_to_string(transform.basis_y);
    out += godot::String(" basis_z=");
    out += vec_to_string(transform.basis_z);
    out += godot::String(" scale=");
    out += vec_to_string(transform.scale);
    out += godot::String(" rot_deg=");
    out += vec_to_string(transform.rotation_degrees);
    return out;
}

} // namespace

// Describes the purpose of set baseline debug enabled.
void set_baseline_debug_enabled(bool enabled) {
    g_baseline_debug_enabled = enabled;
}

// Describes the purpose of is baseline debug enabled.
bool is_baseline_debug_enabled() {
    return g_baseline_debug_enabled;
}

// Describes the purpose of set coordinate debug enabled.
void set_coordinate_debug_enabled(bool enabled) {
    g_coordinate_debug_enabled = enabled;
}

// Describes the purpose of is coordinate debug enabled.
bool is_coordinate_debug_enabled() {
    return g_coordinate_debug_enabled;
}

// Describes the purpose of log coordinate mapping metadata.
void log_coordinate_mapping_metadata() {
    if (!g_coordinate_debug_enabled) {
        return;
    }

    godot::UtilityFunctions::print(
        "[PeravizCoordDebug] event=coordinate_mapping_metadata"
        " scale_global=mm_to_m(0.001)"
        " godot_up=+Y"
        " godot_forward=-Z"
        " godot_handedness=right_handed"
        " source_to_godot=(x,y,z)->(x,z,-y)"
        " beam_reference_local_direction=-Z");
}

void log_coordinate_debug_event(const std::string &event,
                                const std::string &scope,
                                const std::string &detail) {
    if (!g_coordinate_debug_enabled) {
        return;
    }

    godot::UtilityFunctions::print("[PeravizCoordDebug] event=", godot::String(event.c_str()),
                                   " scope=", godot::String(scope.c_str()),
                                   " detail=", godot::String(detail.c_str()));
}

void log_baseline_transform_comparison(const std::string &context,
                                       const Matrix &source_local,
                                       const SceneTransform &mapped_transform) {
    if (!g_baseline_debug_enabled) {
        return;
    }

    godot::UtilityFunctions::print("[PeravizBaseline] context=", godot::String(context.c_str()),
                                   " source_local=", matrix_to_string(source_local),
                                   " mapped=", scene_transform_to_string(mapped_transform));
}

void log_transform_adjustment(const std::string &context,
                              const std::string &reason,
                              const Matrix &before,
                              const Matrix &after) {
    if (!g_coordinate_debug_enabled) {
        return;
    }

    godot::UtilityFunctions::print(
        "[PeravizCoordDebug] event=transform_adjustment"
        " context=", godot::String(context.c_str()),
        " reason=", godot::String(reason.c_str()),
        " before=", matrix_to_string(before),
        " after=", matrix_to_string(after));
}

} // namespace peraviz::debug_runtime
