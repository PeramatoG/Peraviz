#pragma once
#include "presentation/render_emitter_groups.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace peraviz::presentation {
godot::Array serialize_render_groups(const std::vector<RenderEmitterGroup> &groups, int32_t fixture_id);
godot::Dictionary serialize_control_fallbacks(const ControlGroupFallbacks &fallbacks);
}
