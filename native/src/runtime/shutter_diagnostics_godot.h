#pragma once
#include "runtime/visual_runtime_types.h"
#include <godot_cpp/variant/array.hpp>

namespace godot {
Array shutter_setup_metadata(const peraviz::runtime::CompiledRuntimeScene &scene,int universe_offset);
}
