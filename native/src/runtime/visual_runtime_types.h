#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::runtime {

enum VisualChangeMask : uint32_t {
    VisualChangeNone = 0,
    VisualChangeTransform = 1U << 0,
    VisualChangeDimmer = 1U << 1,
    VisualChangeColor = 1U << 2,
    VisualChangeZoom = 1U << 3,
    VisualChangeGobo = 1U << 4,
    VisualChangeGoboRotation = 1U << 5,
    VisualChangePrism = 1U << 6,
    VisualChangeStrobe = 1U << 7,
    VisualChangeMaterial = 1U << 8,
    VisualChangeBeamTopology = 1U << 9,
};

enum class CompiledSemantic : int32_t {
    Unknown = 0,
    Pan,
    Tilt,
    Dimmer,
    Zoom,
};

struct CompiledDmxByteSource {
    int32_t universe_id = -1;
    int32_t address = -1;
    int32_t byte_order = 0;
};

struct CompiledDmxSourceProgram {
    int32_t program_id = 0;
    CompiledSemantic semantic = CompiledSemantic::Unknown;
    std::vector<CompiledDmxByteSource> sources;
    uint32_t dmx_from = 0;
    uint32_t dmx_to = 255;
    double physical_from = 0.0;
    double physical_to = 1.0;
    std::string attribute_name;
    std::string function_name;
    int32_t geometry_id = 0;
    std::string geometry_name;
};

enum class CompiledContributorOperation : int32_t {
    WeightedAdd = 0,
};

struct CompiledPropertyContributor {
    int32_t source_program_id = 0;
    double weight = 1.0;
    CompiledContributorOperation operation = CompiledContributorOperation::WeightedAdd;
};

struct CompiledComponentProperty {
    int32_t property_id = 0;
    int32_t fixture_id = 0;
    int32_t component_id = 0;
    int32_t render_target_id = 0;
    CompiledSemantic semantic = CompiledSemantic::Unknown;
    std::vector<CompiledPropertyContributor> contributors;
    int32_t geometry_id = 0;
    std::string geometry_name;
};

struct CompiledFixtureInstance {
    int32_t fixture_id = 0;
    std::string fixture_uuid;
    std::string fixture_type_name;
    std::string dmx_mode_name;
    int32_t universe_id = -1;
    int32_t start_address = -1;
    double luminous_flux = 10000.0;
    double beam_angle_default = 25.0;
    double spot_multiplier = 1.0;
    double beam_multiplier = 20.0;
};


struct CompiledBeamOpticalProfile {
    int32_t fixture_id = 0;
    std::string fixture_uuid;
    int32_t geometry_instance_id = 0;
    std::string geometry_path;
    std::string geometry_key;
    int32_t render_target_id = 0;
    std::string beam_type = "Wash";
    std::string beam_type_raw;
    std::string beam_type_effective = "Wash";
    std::string beam_type_source = "official_default";
    bool beam_type_valid = true;
    double beam_angle_deg = 25.0;
    double field_angle_deg = 25.0;
    double beam_radius_m = 0.05;
    double throw_ratio = 1.0;
    double rectangle_ratio = 1.7777;
    double luminous_flux = 10000.0;
    double fixture_projected_flux_lm = 10000.0;
    double target_flux_fraction = 1.0;
    double color_temperature = 6000.0;
    std::string beam_angle_source = "fallback";
    std::string field_angle_source = "fallback";
    std::string beam_radius_source = "fallback";
    std::string aperture_source = "official_beam_type";
    std::string photometric_weight_source = "fallback";
    bool has_projected_beam = true;
    bool valid = true;
};

struct CompiledRuntimeDiagnostic {
    std::string code;
    std::string severity;
    std::string message;
    std::string subject;
};

struct CompiledRuntimeScene {
    int32_t contract_version = 1;
    int32_t mvr_fixture_patches = 0;
    int32_t gdtf_files_opened = 0;
    int32_t selected_modes_found = 0;
    int32_t dmxchannels_containers_found = 0;
    int32_t dmxchannel_records_found = 0;
    int32_t logical_channels_found = 0;
    int32_t channel_functions_found = 0;
    int32_t dimmer_program_count = 0;
    int32_t pan_program_count = 0;
    int32_t tilt_program_count = 0;
    int32_t zoom_program_count = 0;
    std::vector<CompiledFixtureInstance> fixtures;
    std::vector<CompiledDmxSourceProgram> source_programs;
    std::vector<CompiledComponentProperty> properties;
    std::vector<CompiledBeamOpticalProfile> beam_profiles;
    std::vector<CompiledRuntimeDiagnostic> diagnostics;
};

struct FixtureRenderParams {
    double luminous_flux = 10000.0;
    double beam_angle_default = 25.0;
    double zoom_min_deg = -1.0;
    double zoom_max_deg = -1.0;
    double color_temp_k = 5600.0;
    double spot_multiplier = 1.0;
    double beam_multiplier = 20.0;
    bool has_zoom = false;
    bool has_color_temperature = false;
};

struct VisualFrameStats {
    uint64_t packets_submitted = 0;
    uint64_t packets_coalesced = 0;
    uint64_t universes_ignored = 0;
    uint64_t universes_considered = 0;
    uint64_t fixtures_dirty = 0;
    uint64_t fixtures_skipped = 0;
    uint64_t changed_transform = 0;
    uint64_t changed_dimmer = 0;
    uint64_t changed_color = 0;
    uint64_t changed_zoom = 0;
    uint64_t changed_gobo = 0;
    uint64_t changed_gobo_rotation = 0;
    uint64_t gobo_topology_updates = 0;
    uint64_t gobo_parametric_updates = 0;
    uint64_t beam_optics_rows = 0;
    uint64_t beam_optics_parametric_updates = 0;
};

} // namespace peraviz::runtime
