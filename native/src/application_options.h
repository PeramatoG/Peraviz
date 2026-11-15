#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {
class PeravizApplicationOptions : public RefCounted {
    GDCLASS(PeravizApplicationOptions, RefCounted)
protected:
    static void _bind_methods();
public:
    static bool has_fps_override();
};
}
