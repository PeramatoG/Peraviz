#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::gdtf_runtime {

enum class ModeMasterTargetKind : uint8_t { None = 0, DmxChannel, ChannelFunction, Invalid };
enum class DmxValueConversion : uint8_t { Mirror = 0, Shift };

struct ParsedDmxValue {
    uint32_t value = 0;
    uint8_t byte_count = 1;
    DmxValueConversion conversion = DmxValueConversion::Mirror;
};

struct ModeMasterCondition {
    ModeMasterTargetKind target_kind = ModeMasterTargetKind::None;
    int32_t target_id = 0;
    int32_t master_program_id = 0;
    uint32_t from = 0;
    uint32_t to = 0;
    uint8_t master_byte_count = 1;
    std::string source_link;
    bool valid = true;
    int32_t master_channel_id = 0;
};

struct ModeMasterNodeRecord {
    ModeMasterTargetKind kind = ModeMasterTargetKind::Invalid;
    int32_t id = 0;
    int32_t channel_id = 0;
    int32_t source_program_id = 0;
    uint8_t byte_count = 1;
    std::string path;
};

struct ChannelFunctionActivation {
    int32_t function_id = 0;
    int32_t source_id = 0;
    uint32_t dmx_from = 0;
    uint32_t dmx_to = 255;
    ModeMasterCondition mode_master;
};

bool parse_gdtf_dmx_value(const std::string &raw, ParsedDmxValue &out);
bool convert_gdtf_dmx_value(const ParsedDmxValue &value, uint8_t target_bytes, uint32_t &out);
bool parse_and_convert_gdtf_dmx_value(const std::string &raw, uint8_t target_bytes, uint32_t &out);
bool resolve_mode_master_condition(const std::string &source_link,
                                   const std::string &mode_from,
                                   const std::string &mode_to,
                                   const std::vector<ModeMasterNodeRecord> &nodes,
                                   ModeMasterCondition &out,
                                   std::string &diagnostic);
bool validate_mode_master_graph(const std::vector<ChannelFunctionActivation> &functions, std::string &diagnostic);
bool is_channel_function_active(int32_t function_id,
                                const std::vector<ChannelFunctionActivation> &functions,
                                const std::vector<uint32_t> &source_values);

} // namespace peraviz::gdtf_runtime
