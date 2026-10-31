#pragma once
#include "runtime/visual_runtime_types.h"
#include <godot_cpp/variant/array.hpp>

namespace peraviz::presentation { struct RenderEmitterGroup; }
namespace godot {
Array shutter_setup_metadata(const peraviz::runtime::CompiledRuntimeScene &scene,int universe_offset,const std::vector<peraviz::presentation::RenderEmitterGroup> &groups);
}
