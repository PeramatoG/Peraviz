#pragma once

#include <cstdint>
#include <string>

namespace peraviz::gdtf_runtime {

enum class GoboSemanticKind : uint8_t {
    None = 0, Selection, SelectSpin, SelectShake, SelectEffects,
    WheelIndex, WheelSpin, WheelShake, WheelRandom, WheelAudio,
    Pos, PosRotate, PosShake,
};

enum class GoboControlledScope : uint8_t {
    None = 0, Selection, SelectedGobo, CompleteWheel, SelectionAndSelectedGobo,
};

struct ParsedGoboSemantic {
    GoboSemanticKind kind = GoboSemanticKind::None;
    GoboControlledScope scope = GoboControlledScope::None;
    int32_t wheel_number = 0;
    std::string normalized_name;
    bool recognized = false;
    bool evaluation_supported = false;
};

ParsedGoboSemantic parse_gobo_semantic(const std::string &attribute_name);

} // namespace peraviz::gdtf_runtime
