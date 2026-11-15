#include "application_options.h"

#include <godot_cpp/core/class_db.hpp>
#include <string>
#include <vector>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#elif defined(__APPLE__)
#include <crt_externs.h>
#else
#include <fstream>
#endif

namespace {
// Read startup arguments before Godot's filtering; no shell process or new library is needed.
std::vector<std::string> startup_arguments() {
    std::vector<std::string> args;
#ifdef _WIN32
    const wchar_t *begin = GetCommandLineW();
    const wchar_t *cursor = begin;
    std::string token;
    bool quoted = false;
    for (; *cursor; ++cursor) {
        if (*cursor == L'"') {
            // An escaped quote is literal, so it cannot terminate a quoted path.
            size_t slashes = 0;
            for (const wchar_t *p = cursor; p > begin && p[-1] == L'\\'; --p) ++slashes;
            if (slashes % 2) token += '"';
            else quoted = !quoted;
        } else if ((*cursor == L' ' || *cursor == L'\t') && !quoted) {
            if (!token.empty()) { args.push_back(token); token.clear(); }
        } else token += *cursor <= 127 ? char(*cursor) : '?';
    }
    if (!token.empty()) args.push_back(token);
#elif defined(__APPLE__)
    for (int i = 0; i < *_NSGetArgc(); ++i) args.emplace_back((*_NSGetArgv())[i]);
#else
    std::ifstream input("/proc/self/cmdline", std::ios::binary);
    for (std::string token; std::getline(input, token, '\0');) args.push_back(token);
#endif
    return args;
}
}

namespace godot {
// Bind a startup-only query for engine FPS flags consumed before GDScript starts.
void PeravizApplicationOptions::_bind_methods() {
    ClassDB::bind_static_method("PeravizApplicationOptions", D_METHOD("has_fps_override"), &PeravizApplicationOptions::has_fps_override);
}

// Only engine arguments count; options following the application separator do not.
bool PeravizApplicationOptions::has_fps_override() {
    const auto args = startup_arguments();
    for (size_t i = 1; i < args.size(); ++i) {
        if (args[i] == "--" || args[i] == "++") break;
        if (args[i] == "--max-fps" || args[i] == "--fixed-fps") return true;
    }
    return false;
}
}
