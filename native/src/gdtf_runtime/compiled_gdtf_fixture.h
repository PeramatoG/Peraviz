#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::gdtf_runtime {

struct AttributeIdentity {
    int32_t id = 0;
    std::string name;
    std::string canonical_family;
    int32_t primary_index = 0;
    std::vector<int32_t> wildcard_indexes;
    int32_t secondary_index = 0;
    bool known_official = false;
    bool custom = false;
};

struct GeometryInstance {
    int32_t id = 0;
    int32_t parent_id = 0;
    std::string name;
    std::string path;
    std::string type;
};

struct ComponentBinding {
    int32_t component_id = 0;
    int32_t geometry_instance_id = 0;
    int32_t attribute_id = 0;
    int32_t wheel_id = 0;
    int32_t render_target_id = 0;
};

struct ChannelProgram {
    int32_t id = 0;
    std::vector<int32_t> dmx_offsets_1_based;
    int32_t bit_depth = 8;
    int32_t attribute_id = 0;
    int32_t geometry_instance_id = 0;
    int32_t component_id = 0;
    uint32_t dmx_from = 0;
    uint32_t dmx_to = 255;
    double physical_from = 0.0;
    double physical_to = 1.0;
    std::string attribute_name;
    std::string function_name;
};

struct RuntimeDiagnostic {
    std::string code;
    std::string severity;
    std::string message;
    std::string subject;
};

struct CompiledGdtfFixtureType {
    std::string fixture_type_name;
    std::string dmx_mode_name;
    int32_t semantic_contract_version = 1;
    int32_t gdtf_files_opened = 0;
    int32_t selected_modes_found = 0;
    int32_t dmxchannels_containers_found = 0;
    int32_t dmxchannel_records_found = 0;
    int32_t logical_channels_found = 0;
    int32_t channel_functions_found = 0;
    int32_t dimmer_program_count = 0;
    int32_t pan_program_count = 0;
    int32_t tilt_program_count = 0;
    std::vector<AttributeIdentity> attributes;
    std::vector<GeometryInstance> geometries;
    std::vector<ComponentBinding> components;
    std::vector<ChannelProgram> channel_programs;
    std::vector<RuntimeDiagnostic> diagnostics;
};

AttributeIdentity normalize_attribute_identity(int32_t id, const std::string &attribute_name);
CompiledGdtfFixtureType compile_gdtf_fixture_type(const std::string &gdtf_path,
                                                  const std::string &dmx_mode_name);
CompiledGdtfFixtureType make_two_gobo_wheel_regression_fixture();

} // namespace peraviz::gdtf_runtime
