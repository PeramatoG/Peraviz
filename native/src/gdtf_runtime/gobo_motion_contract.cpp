#include "gdtf_runtime/gobo_motion_contract.h"

#include <cctype>
#include <algorithm>
#include <unordered_map>

namespace peraviz::gdtf_runtime {

// Trims ASCII whitespace without depending on the XML parser.
std::string trim_ascii_local(const std::string &value) {
    const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char ch) { return std::isspace(ch) != 0; });
    const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char ch) { return std::isspace(ch) != 0; }).base();
    return first < last ? std::string(first, last) : std::string();
}

// Lowercases normalized ASCII GDTF names for case-insensitive matching.
std::string lower_ascii_local(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
}

// Parses only exact normalized GDTF Gobo(n) identities without substring heuristics.
ParsedGoboSemantic parse_gobo_semantic(const std::string &attribute_name) {
    const std::string trimmed = trim_ascii_local(attribute_name);
    const std::string lower = lower_ascii_local(trimmed);
    ParsedGoboSemantic result;
    if (lower.rfind("gobo", 0) != 0) return result;
    size_t cursor = 4;
    const size_t number_start = cursor;
    while (cursor < lower.size() && std::isdigit(static_cast<unsigned char>(lower[cursor]))) ++cursor;
    if (cursor == number_start) return result;
    try { result.wheel_number = std::stoi(lower.substr(number_start, cursor - number_start)); }
    catch (...) { return {}; }
    if (result.wheel_number <= 0) return {};
    const std::string suffix = lower.substr(cursor);
    struct Definition { GoboSemanticKind kind; GoboControlledScope scope; const char *canonical_suffix; bool supported; };
    static const std::unordered_map<std::string, Definition> definitions = {
        {"", {GoboSemanticKind::Selection, GoboControlledScope::Selection, "", true}},
        {"selectspin", {GoboSemanticKind::SelectSpin, GoboControlledScope::SelectionAndSelectedGobo, "SelectSpin", true}},
        {"selectshake", {GoboSemanticKind::SelectShake, GoboControlledScope::SelectionAndSelectedGobo, "SelectShake", true}},
        {"selecteffects", {GoboSemanticKind::SelectEffects, GoboControlledScope::SelectionAndSelectedGobo, "SelectEffects", false}},
        {"wheelindex", {GoboSemanticKind::WheelIndex, GoboControlledScope::CompleteWheel, "WheelIndex", true}},
        {"wheelspin", {GoboSemanticKind::WheelSpin, GoboControlledScope::CompleteWheel, "WheelSpin", true}},
        {"wheelshake", {GoboSemanticKind::WheelShake, GoboControlledScope::CompleteWheel, "WheelShake", true}},
        {"wheelrandom", {GoboSemanticKind::WheelRandom, GoboControlledScope::CompleteWheel, "WheelRandom", false}},
        {"wheelaudio", {GoboSemanticKind::WheelAudio, GoboControlledScope::CompleteWheel, "WheelAudio", false}},
        {"pos", {GoboSemanticKind::Pos, GoboControlledScope::SelectedGobo, "Pos", true}},
        {"posrotate", {GoboSemanticKind::PosRotate, GoboControlledScope::SelectedGobo, "PosRotate", true}},
        {"posshake", {GoboSemanticKind::PosShake, GoboControlledScope::SelectedGobo, "PosShake", true}},
    };
    const auto found = definitions.find(suffix);
    if (found == definitions.end()) return {};
    result.kind = found->second.kind;
    result.scope = found->second.scope;
    result.normalized_name = "Gobo" + std::to_string(result.wheel_number) + found->second.canonical_suffix;
    result.recognized = true;
    result.evaluation_supported = found->second.supported;
    return result;
}

} // namespace peraviz::gdtf_runtime
