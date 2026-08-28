#include "gdtf_runtime/mode_master.h"
#include "gdtf_runtime/string_utils.h"

#include <algorithm>
#include <cstdlib>
#include <functional>
#include <unordered_map>

namespace peraviz::gdtf_runtime {
namespace {

// Returns the maximum unsigned value representable by the supported byte width.
uint32_t byte_max(uint8_t bytes) {
    if (bytes == 0 || bytes > 4) return 0;
    return bytes == 4 ? 0xffffffffU : (1U << (bytes * 8U)) - 1U;
}

} // namespace

// Parses the GDTF Uint/n and Uint/ns lexical forms without lossy conversion.
bool parse_gdtf_dmx_value(const std::string &raw, ParsedDmxValue &out) {
    const std::string text = trim_ascii_token(raw);
    if (text.empty()) return false;
    const size_t slash = text.find('/');
    const std::string value_text = slash == std::string::npos ? text : text.substr(0, slash);
    std::string resolution = slash == std::string::npos ? "1" : text.substr(slash + 1);
    if (resolution.empty()) return false;
    out.conversion = DmxValueConversion::Mirror;
    if (resolution.back() == 's' || resolution.back() == 'S') {
        out.conversion = DmxValueConversion::Shift;
        resolution.pop_back();
    }
    char *end = nullptr;
    const unsigned long bytes = std::strtoul(resolution.c_str(), &end, 10);
    if (end == resolution.c_str() || *end != '\0' || bytes < 1 || bytes > 4) return false;
    end = nullptr;
    const unsigned long long value = std::strtoull(value_text.c_str(), &end, 10);
    if (end == value_text.c_str() || *end != '\0' || value > byte_max(static_cast<uint8_t>(bytes))) return false;
    out.value = static_cast<uint32_t>(value);
    out.byte_count = static_cast<uint8_t>(bytes);
    return true;
}

// Converts a parsed DMXValue using normative byte mirroring or byte shifting.
bool convert_gdtf_dmx_value(const ParsedDmxValue &value, uint8_t target_bytes, uint32_t &out) {
    if (value.byte_count == 0 || value.byte_count > 4 || target_bytes == 0 || target_bytes > 4) return false;
    if (value.byte_count == target_bytes) { out = value.value; return true; }
    if (value.byte_count > target_bytes) {
        out = value.value >> ((value.byte_count - target_bytes) * 8U);
        return true;
    }
    if (value.conversion == DmxValueConversion::Shift) {
        out = value.value << ((target_bytes - value.byte_count) * 8U);
        return true;
    }
    uint32_t converted = value.value;
    uint8_t filled = value.byte_count;
    while (filled < target_bytes) {
        const uint8_t take = std::min<uint8_t>(value.byte_count, target_bytes - filled);
        converted = (converted << (take * 8U)) | (value.value >> ((value.byte_count - take) * 8U));
        filled += take;
    }
    out = converted;
    return true;
}

// Parses and converts one GDTF DMXValue through the shared normative implementation.
bool parse_and_convert_gdtf_dmx_value(const std::string &raw, uint8_t target_bytes, uint32_t &out) {
    ParsedDmxValue parsed;
    return parse_gdtf_dmx_value(raw, parsed) && convert_gdtf_dmx_value(parsed, target_bytes, out);
}

// Resolves an exact mode-relative Node path and applies official ModeFrom/ModeTo defaults.
bool resolve_mode_master_condition(const std::string &source_link,
                                   const std::string &mode_from,
                                   const std::string &mode_to,
                                   const std::vector<ModeMasterNodeRecord> &nodes,
                                   ModeMasterCondition &out,
                                   std::string &diagnostic) {
    const std::string preserved_link = trim_ascii_token(source_link);
    out = {};
    out.source_link = preserved_link;
    if (out.source_link.empty() || out.source_link.front() == '.' || out.source_link.back() == '.' || out.source_link.find("..") != std::string::npos) {
        out.target_kind = ModeMasterTargetKind::Invalid;
        out.valid = false;
        diagnostic = "PVZ-GDTF-MODEMASTER-NODE-MALFORMED";
        return false;
    }
    const ModeMasterNodeRecord *match = nullptr;
    for (const ModeMasterNodeRecord &node : nodes) {
        if (node.path != out.source_link) continue;
        if (match) {
            out.target_kind = ModeMasterTargetKind::Invalid;
            out.valid = false;
            diagnostic = "PVZ-GDTF-MODEMASTER-NODE-AMBIGUOUS";
            return false;
        }
        match = &node;
    }
    if (!match) {
        out.target_kind = ModeMasterTargetKind::Invalid;
        out.valid = false;
        diagnostic = "PVZ-GDTF-MODEMASTER-UNRESOLVED";
        return false;
    }
    const std::string from_source = trim_ascii_token(mode_from).empty() ? "0/1" : mode_from;
    const std::string to_source = trim_ascii_token(mode_to).empty() ? "0/1" : mode_to;
    if (!parse_and_convert_gdtf_dmx_value(from_source, match->byte_count, out.from) ||
        !parse_and_convert_gdtf_dmx_value(to_source, match->byte_count, out.to) || out.from > out.to) {
        out.target_kind = ModeMasterTargetKind::Invalid;
        out.valid = false;
        diagnostic = "PVZ-GDTF-MODEMASTER-RANGE-INVALID";
        return false;
    }
    out.target_kind = match->kind;
    out.target_id = match->id;
    out.master_program_id = match->source_program_id;
    out.master_channel_id = match->channel_id;
    out.master_byte_count = match->byte_count;
    out.valid = true;
    diagnostic.clear();
    return true;
}

// Validates resolved ChannelFunction dependencies and rejects deterministic cycles.
bool validate_mode_master_graph(const std::vector<ChannelFunctionActivation> &functions, std::string &diagnostic) {
    std::unordered_map<int32_t, size_t> indexes;
    for (size_t i = 0; i < functions.size(); ++i) indexes[functions[i].function_id] = i;
    std::vector<uint8_t> state(functions.size(), 0);
    std::function<bool(size_t)> visit = [&](size_t index) {
        if (state[index] == 1) { diagnostic = "PVZ-GDTF-MODEMASTER-CYCLE:function=" + std::to_string(functions[index].function_id); return false; }
        if (state[index] == 2) return true;
        state[index] = 1;
        const auto &condition = functions[index].mode_master;
        if (condition.target_kind == ModeMasterTargetKind::Invalid || !condition.valid) { diagnostic = "PVZ-GDTF-MODEMASTER-UNRESOLVED:function=" + std::to_string(functions[index].function_id); return false; }
        if (condition.target_kind == ModeMasterTargetKind::ChannelFunction) {
            const auto target = indexes.find(condition.target_id);
            if (target == indexes.end()) { diagnostic = "PVZ-GDTF-MODEMASTER-UNRESOLVED:function=" + std::to_string(functions[index].function_id); return false; }
            if (!visit(target->second)) return false;
        }
        state[index] = 2;
        return true;
    };
    for (size_t i = 0; i < functions.size(); ++i) if (!visit(i)) return false;
    diagnostic.clear();
    return true;
}

// Evaluates own DMX range and the resolved ModeMaster dependency cascade without allocation.
bool is_channel_function_active(int32_t function_id, const std::vector<ChannelFunctionActivation> &functions, const std::vector<uint32_t> &source_values) {
    const auto find_index = [&](int32_t id) {
        for (size_t index = 0; index < functions.size(); ++index) if (functions[index].function_id == id) return index;
        return functions.size();
    };
    std::function<bool(size_t, size_t)> evaluate = [&](size_t index, size_t depth) {
        if (index >= functions.size() || depth > functions.size()) return false;
        const auto &function = functions[index];
        if (function.source_id < 0 || static_cast<size_t>(function.source_id) >= source_values.size()) return false;
        const uint32_t own = source_values[function.source_id];
        if (own < function.dmx_from || own > function.dmx_to) return false;
        const auto &condition = function.mode_master;
        if (!condition.valid || condition.target_kind == ModeMasterTargetKind::Invalid) return false;
        if (condition.target_kind == ModeMasterTargetKind::None) return true;
        const size_t master = find_index(condition.target_kind == ModeMasterTargetKind::ChannelFunction ? condition.target_id : condition.master_program_id);
        if (master >= functions.size()) return false;
        const auto &master_function = functions[master];
        if (master_function.source_id < 0 || static_cast<size_t>(master_function.source_id) >= source_values.size()) return false;
        const uint32_t master_value = source_values[master_function.source_id];
        if (master_value < condition.from || master_value > condition.to) return false;
        return condition.target_kind != ModeMasterTargetKind::ChannelFunction || evaluate(master, depth + 1);
    };
    const size_t found = find_index(function_id);
    return found < functions.size() && evaluate(found, 0);
}

} // namespace peraviz::gdtf_runtime
