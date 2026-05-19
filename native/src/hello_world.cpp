#include "hello_world.h"

#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

// Registers class methods so they are callable from Godot scripts.
void HelloWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("ping"), &HelloWorld::ping);
}

// Returns a simple string used to verify module wiring.
String HelloWorld::ping() const {
    const String message = "pong from Peraviz native C++";
    UtilityFunctions::print("[PeravizNative] ", message);
    return message;
}

} // namespace godot
