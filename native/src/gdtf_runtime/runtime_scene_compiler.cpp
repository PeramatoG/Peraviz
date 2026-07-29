#include "gdtf_runtime/runtime_scene_compiler.h"

#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/gdtf_xml_reader.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include "runtime/color_science.h"

namespace peraviz::gdtf_runtime {
namespace {

constexpr double kReferenceLuminousFluxLm = 10000.0;

// Creates deterministic nonzero IDs from fixture UUID and semantic labels using FNV-1a.
int32_t stable_id(const std::string &fixture_uuid, const std::string &label) {
    constexpr uint64_t fnv_offset = 1469598103934665603ULL;
    constexpr uint64_t fnv_prime = 1099511628211ULL;
    uint64_t hash = fnv_offset;
    const std::string key = fixture_uuid + ":" + label;
    for (unsigned char value : key) {
        hash ^= static_cast<uint64_t>(value);
        hash *= fnv_prime;
    }
    return static_cast<int32_t>((hash % 2000000000ULL) + 1ULL);
}

// Maps parser-owned attribute identities into the current runtime semantic slice.
runtime::CompiledSemantic semantic_for_attribute(const AttributeIdentity &attribute) {
    if (attribute.canonical_family == "Dimmer") return runtime::CompiledSemantic::Dimmer;
    if (attribute.canonical_family == "Pan") return runtime::CompiledSemantic::Pan;
    if (attribute.canonical_family == "Tilt") return runtime::CompiledSemantic::Tilt;
    if (attribute.canonical_family == "Zoom") return runtime::CompiledSemantic::Zoom;
    std::string lower = dmx::lower_ascii(dmx::trim_ascii(attribute.name));
    if (lower == "coloradd_r" || lower == "colorrgb_red") return runtime::CompiledSemantic::ColorAddRed;
    if (lower == "coloradd_g" || lower == "colorrgb_green") return runtime::CompiledSemantic::ColorAddGreen;
    if (lower == "coloradd_b" || lower == "colorrgb_blue") return runtime::CompiledSemantic::ColorAddBlue;
    if (lower == "coloradd_w") return runtime::CompiledSemantic::ColorAddWhite;
    if (lower == "coloradd_ry") return runtime::CompiledSemantic::ColorAddAmber;
    if (lower == "coloradd_gy") return runtime::CompiledSemantic::ColorAddLime;
    if (lower == "cie_x") return runtime::CompiledSemantic::CieX;
    if (lower == "cie_y") return runtime::CompiledSemantic::CieY;
    if (lower == "cie_brightness") return runtime::CompiledSemantic::CieBrightness;
    if (lower == "cto") return runtime::CompiledSemantic::Cto;
    if (lower == "ctb") return runtime::CompiledSemantic::Ctb;
    if (lower == "ctc") return runtime::CompiledSemantic::Ctc;
    if (lower == "tint") return runtime::CompiledSemantic::Tint;
    if (lower == "colorsub_c" || lower == "cyan") return runtime::CompiledSemantic::ColorSubCyan;
    if (lower == "colorsub_m" || lower == "magenta") return runtime::CompiledSemantic::ColorSubMagenta;
    if (lower == "colorsub_y" || lower == "yellow") return runtime::CompiledSemantic::ColorSubYellow;
    const dmx::ParsedAttribute parsed = dmx::parse_attribute_name(attribute.name);
    if (parsed.role == dmx::AttributeRole::kDimmer) return runtime::CompiledSemantic::Dimmer;
    if (parsed.role == dmx::AttributeRole::kPan) return runtime::CompiledSemantic::Pan;
    if (parsed.role == dmx::AttributeRole::kTilt) return runtime::CompiledSemantic::Tilt;
    if (parsed.role == dmx::AttributeRole::kZoom) return runtime::CompiledSemantic::Zoom;
    return runtime::CompiledSemantic::Unknown;
}

// Returns true when the corrected color slice supports this semantic end to end.
bool is_supported_color_semantic(runtime::CompiledSemantic semantic) {
    return semantic == runtime::CompiledSemantic::ColorAddRed || semantic == runtime::CompiledSemantic::ColorAddGreen || semantic == runtime::CompiledSemantic::ColorAddBlue || semantic == runtime::CompiledSemantic::ColorAddWhite || semantic == runtime::CompiledSemantic::ColorAddAmber || semantic == runtime::CompiledSemantic::ColorAddLime || semantic == runtime::CompiledSemantic::ColorSubCyan || semantic == runtime::CompiledSemantic::ColorSubMagenta || semantic == runtime::CompiledSemantic::ColorSubYellow || semantic == runtime::CompiledSemantic::CieX || semantic == runtime::CompiledSemantic::CieY || semantic == runtime::CompiledSemantic::CieBrightness || semantic == runtime::CompiledSemantic::Cto || semantic == runtime::CompiledSemantic::Ctb || semantic == runtime::CompiledSemantic::Ctc || semantic == runtime::CompiledSemantic::Tint;
}

// Finds a parser-owned attribute identity by ID.
const AttributeIdentity *find_attribute(const CompiledGdtfFixtureType &fixture, int32_t attribute_id) {
    for (const AttributeIdentity &attribute : fixture.attributes) {
        if (attribute.id == attribute_id) return &attribute;
    }
    return nullptr;
}

// Finds a parser-owned component binding by ID.
const ComponentBinding *find_component(const CompiledGdtfFixtureType &fixture, int32_t component_id) {
    for (const ComponentBinding &component : fixture.components) {
        if (component.component_id == component_id) return &component;
    }
    return nullptr;
}

// Finds a parser-owned geometry identity by ID.
const GeometryInstance *find_geometry(const CompiledGdtfFixtureType &fixture, int32_t geometry_id) {
    for (const GeometryInstance &geometry : fixture.geometries) {
        if (geometry.id == geometry_id) return &geometry;
    }
    return nullptr;
}

// Returns the explicit physical range or a diagnostic fallback for the supported semantic.
void apply_physical_fallback(runtime::CompiledRuntimeScene &scene,
                             const SceneModel::FixturePatch &patch,
                             runtime::CompiledSemantic semantic,
                             runtime::CompiledDmxSourceProgram &program) {
    if (program.physical_from != 0.0 || program.physical_to != 1.0 || semantic == runtime::CompiledSemantic::Dimmer) return;
    if (semantic == runtime::CompiledSemantic::Pan) { program.physical_from = -270.0; program.physical_to = 270.0; }
    if (semantic == runtime::CompiledSemantic::Tilt) { program.physical_from = -135.0; program.physical_to = 135.0; }
    if (semantic == runtime::CompiledSemantic::Zoom) { program.physical_from = 8.0; program.physical_to = 40.0; }
    scene.diagnostics.push_back({"PVZ-GDTF-PHYSICAL-FALLBACK", "warning", "ChannelFunction is missing a valid physical range; using explicit runtime fallback.", patch.fixture_uuid + " mode=" + patch.dmx_mode + " attribute=" + program.attribute_name + " function=" + program.function_name});
}

// Builds ordered patch-adjusted source bytes for one parser-owned ChannelFunction program.
std::vector<runtime::CompiledDmxByteSource> make_sources(runtime::CompiledRuntimeScene &scene,
                                                         const SceneModel::FixturePatch &patch,
                                                         const ChannelProgram &program,
                                                         int artnet_universe) {
    std::vector<runtime::CompiledDmxByteSource> sources;
    for (size_t index = 0; index < program.dmx_offsets_1_based.size() && index < 4; ++index) {
        const int address = (patch.mvr_address - 1) + (program.dmx_offsets_1_based[index] - 1);
        if (address < 0 || address >= 512) {
            scene.diagnostics.push_back({"PVZ-GDTF-SOURCE-OUT-OF-RANGE", "warning", "Patch-adjusted DMX source address is outside the 512-slot universe.", patch.fixture_uuid + " mode=" + patch.dmx_mode + " universe=" + std::to_string(artnet_universe) + " address=" + std::to_string(address + 1) + " attribute=" + program.attribute_name + " function=" + program.function_name});
            continue;
        }
        sources.push_back({artnet_universe, address, static_cast<int32_t>(index)});
    }
    if (program.dmx_offsets_1_based.size() > 4) {
        scene.diagnostics.push_back({"PVZ-GDTF-UNSUPPORTED-BIT-DEPTH", "warning", "Runtime compiler supports up to 32-bit source values.", patch.fixture_uuid});
    }
    return sources;
}

// Checks generated registry IDs without treating intentional component references as collisions.
void check_generated_id(std::unordered_set<int32_t> &ids, runtime::CompiledRuntimeScene &scene, int32_t id, const std::string &subject) {
    if (id <= 0 || !ids.insert(id).second) scene.diagnostics.push_back({"PVZ-RUNTIME-ID-COLLISION", "error", "Native compiler generated an invalid or duplicate runtime ID.", subject});
}


// Normalizes official GDTF BeamType values into renderer-facing profile labels.
std::string normalize_beam_type(const std::string &beam_type) {
    const std::string lower = dmx::lower_ascii(dmx::trim_ascii(beam_type));
    if (lower == "wash") return "Wash";
    if (lower == "pc") return "PC";
    if (lower == "fresnel") return "Fresnel";
    if (lower == "rectangle") return "Rectangle";
    if (lower == "none") return "None";
    if (lower == "glow") return "Glow";
    return "Wash";
}

// Returns true when a normalized BeamType creates a projected renderer beam.
bool is_projected_beam_type(const std::string &beam_type) {
    return beam_type == "Wash" || beam_type == "Spot" || beam_type == "Rectangle" || beam_type == "PC" || beam_type == "Fresnel";
}

// Resolves GDTF Beam LuminousFlux provenance and renderer scales for one exact Beam geometry.
void resolve_luminous_flux(runtime::CompiledRuntimeScene &out, runtime::CompiledBeamOpticalProfile &profile, const SceneNode &node, const SceneModel::FixturePatch &patch) {
    profile.raw_luminous_flux = node.has_luminous_flux ? static_cast<double>(node.luminous_flux) : kReferenceLuminousFluxLm;
    if (!node.has_luminous_flux) {
        profile.effective_luminous_flux_lm = kReferenceLuminousFluxLm;
        profile.luminous_flux_source = "gdtf_default";
    } else if (std::isfinite(profile.raw_luminous_flux) && profile.raw_luminous_flux >= 0.0) {
        profile.effective_luminous_flux_lm = profile.raw_luminous_flux;
        profile.luminous_flux_source = "explicit";
    } else {
        profile.effective_luminous_flux_lm = 0.0;
        profile.luminous_flux_source = "invalid_safe_value";
        out.diagnostics.push_back({"PVZ-GDTF-BEAM-LUMINOUS-FLUX-INVALID", "warning", "Beam geometry has invalid explicit LuminousFlux; using a safe non-negative renderer value.", patch.fixture_uuid + " geometry=" + node.gdtf_geometry_path});
    }
    profile.luminous_flux = profile.effective_luminous_flux_lm;
    profile.emission_lumen_scale = profile.effective_luminous_flux_lm / kReferenceLuminousFluxLm;
    profile.projected_lumen_scale = profile.has_projected_beam ? profile.emission_lumen_scale : 0.0;
}

// Appends setup-time Beam profiles for exact GDTF Beam geometry nodes in one fixture patch.
void append_beam_profiles(runtime::CompiledRuntimeScene &out, const SceneModel &scene, const SceneModel::FixturePatch &patch, int32_t fixture_id) {
    const std::string prefix = patch.fixture_uuid + "/";
    for (const SceneNode &node : scene.nodes) {
        if (!node.is_beam || node.gdtf_geometry_key.rfind(prefix, 0) != 0) continue;
        runtime::CompiledBeamOpticalProfile profile;
        profile.fixture_id = fixture_id;
        profile.fixture_uuid = patch.fixture_uuid;
        profile.geometry_path = node.gdtf_geometry_path;
        profile.geometry_key = node.gdtf_geometry_key;
        profile.render_target_id = stable_id(patch.fixture_uuid, "beam:target:" + node.gdtf_geometry_path);
        profile.beam_type = normalize_beam_type(node.has_beam_type ? node.beam_type : "Wash");
        profile.beam_angle_deg = node.has_beam_angle ? node.beam_angle : profile.beam_angle_deg;
        profile.field_angle_deg = node.has_field_angle ? node.field_angle : profile.field_angle_deg;
        profile.beam_radius_m = node.has_beam_radius ? node.beam_radius : profile.beam_radius_m;
        profile.throw_ratio = node.has_throw_ratio ? node.throw_ratio : profile.throw_ratio;
        profile.rectangle_ratio = node.has_rectangle_ratio ? node.rectangle_ratio : profile.rectangle_ratio;
        profile.color_temperature = node.has_color_temperature ? node.color_temperature : profile.color_temperature;
        profile.beam_angle_source = node.has_beam_angle ? "explicit" : "fallback";
        profile.field_angle_source = node.has_field_angle ? "explicit" : "fallback";
        profile.beam_radius_source = node.has_beam_radius ? "explicit" : "fallback";
        profile.has_projected_beam = is_projected_beam_type(profile.beam_type);
        resolve_luminous_flux(out, profile, node, patch);
        if (profile.beam_radius_m <= 0.0 || profile.beam_angle_deg < 0.0 || profile.rectangle_ratio <= 0.0) {
            profile.valid = false;
            out.diagnostics.push_back({"PVZ-GDTF-BEAM-PROFILE-INVALID", "warning", "Beam geometry profile contains invalid optical values.", patch.fixture_uuid + " geometry=" + node.gdtf_geometry_path});
        }
        out.beam_profiles.push_back(profile);
    }
}

// Builds a cache key for parser-owned fixture type compilation.
std::string fixture_type_cache_key(const SceneModel::FixturePatch &patch) {
    return patch.gdtf_path + "\n" + dmx::lower_ascii(dmx::trim_ascii(patch.dmx_mode));
}

// Adds parser setup counters from a unique fixture type into the runtime setup report.
void add_fixture_type_counters(runtime::CompiledRuntimeScene &out, const CompiledGdtfFixtureType &fixture_type) {
    out.gdtf_files_opened += fixture_type.gdtf_files_opened;
    out.selected_modes_found += fixture_type.selected_modes_found;
    out.dmxchannels_containers_found += fixture_type.dmxchannels_containers_found;
    out.dmxchannel_records_found += fixture_type.dmxchannel_records_found;
    out.logical_channels_found += fixture_type.logical_channels_found;
    out.channel_functions_found += fixture_type.channel_functions_found;
    out.dimmer_program_count += fixture_type.dimmer_program_count;
    out.pan_program_count += fixture_type.pan_program_count;
    out.tilt_program_count += fixture_type.tilt_program_count;
    out.zoom_program_count += fixture_type.zoom_program_count;
    out.color_program_count += fixture_type.color_program_count;
}

// Appends one runtime property containing all ChannelFunction programs for the same component.
void append_property(runtime::CompiledRuntimeScene &scene,
                     const SceneModel::FixturePatch &patch,
                     const CompiledGdtfFixtureType &fixture_type,
                     const ComponentBinding &component,
                     const std::vector<const ChannelProgram *> &programs,
                     int artnet_universe,
                     int32_t fixture_id,
                     int32_t &next_program_id) {
    if (programs.empty()) return;
    const AttributeIdentity *attribute = find_attribute(fixture_type, component.attribute_id);
    const GeometryInstance *geometry = find_geometry(fixture_type, component.geometry_instance_id);
    if (!attribute || !geometry) return;
    const runtime::CompiledSemantic semantic = semantic_for_attribute(*attribute);
    if (semantic == runtime::CompiledSemantic::Unknown || is_supported_color_semantic(semantic)) return;
    const bool is_color_semantic = false;
    const std::string semantic_label = semantic == runtime::CompiledSemantic::Pan ? "pan" : semantic == runtime::CompiledSemantic::Tilt ? "tilt" : semantic == runtime::CompiledSemantic::Zoom ? "zoom" : (semantic == runtime::CompiledSemantic::Dimmer ? "dimmer" : "color");
    const int32_t component_id = stable_id(patch.fixture_uuid, semantic_label + ":component:" + geometry->path);
    const int32_t target_id = semantic == runtime::CompiledSemantic::Zoom ? stable_id(patch.fixture_uuid, "beam:target:" + geometry->path) : (semantic == runtime::CompiledSemantic::Dimmer ? stable_id(patch.fixture_uuid, semantic_label + ":target:" + geometry->path) : component_id);
    const int32_t property_id = stable_id(patch.fixture_uuid, semantic_label + ":property:" + geometry->path);
    runtime::CompiledComponentProperty property;
    property.property_id = property_id;
    property.fixture_id = fixture_id;
    property.component_id = component_id;
    property.render_target_id = target_id;
    property.semantic = semantic;
    property.geometry_id = geometry->id;
    property.geometry_name = geometry->path.empty() ? geometry->name : geometry->path;
    for (const ChannelProgram *parser_program : programs) {
        runtime::CompiledDmxSourceProgram runtime_program;
        runtime_program.program_id = next_program_id++;
        runtime_program.semantic = semantic;
        runtime_program.sources = make_sources(scene, patch, *parser_program, artnet_universe);
        if (runtime_program.sources.empty()) continue;
        runtime_program.dmx_from = parser_program->dmx_from;
        runtime_program.dmx_to = parser_program->dmx_to;
        runtime_program.physical_from = parser_program->physical_from;
        runtime_program.physical_to = parser_program->physical_to;
        runtime_program.attribute_name = parser_program->attribute_name.empty() ? attribute->name : parser_program->attribute_name;
        runtime_program.function_name = parser_program->function_name.empty() ? runtime_program.attribute_name : parser_program->function_name;
        runtime_program.geometry_id = geometry->id;
        runtime_program.geometry_name = property.geometry_name;
        apply_physical_fallback(scene, patch, semantic, runtime_program);
        scene.source_programs.push_back(runtime_program);
        property.contributors.push_back({runtime_program.program_id, 1.0, runtime::CompiledContributorOperation::WeightedAdd});
    }
    if (!property.contributors.empty()) scene.properties.push_back(property);
}

// Returns true when a channel geometry controls a candidate Beam output by GDTF trickle-down inheritance.
bool color_channel_controls_beam(const GeometryInstance &channel_geometry, const runtime::CompiledBeamOpticalProfile &beam) {
    if (channel_geometry.path.empty()) return true;
    return beam.geometry_path == channel_geometry.path || beam.geometry_path.rfind(channel_geometry.path + "/", 0) == 0;
}

// Appends target-level color programs after Beam target IDs are known.
void append_color_targets(runtime::CompiledRuntimeScene &scene,
                          const SceneModel::FixturePatch &patch,
                          const CompiledGdtfFixtureType &fixture_type,
                          int artnet_universe,
                          int32_t fixture_id,
                          int32_t &next_program_id) {
    std::unordered_map<int32_t, const AttributeIdentity *> attributes_by_id;
    std::unordered_map<int32_t, const GeometryInstance *> geometries_by_id;
    for (const AttributeIdentity &attribute : fixture_type.attributes) attributes_by_id[attribute.id] = &attribute;
    for (const GeometryInstance &geometry : fixture_type.geometries) geometries_by_id[geometry.id] = &geometry;
    std::unordered_map<int32_t, runtime::CompiledColorTargetProgram> targets_by_beam_id;
    for (const ChannelProgram &parser_program : fixture_type.channel_programs) {
        auto attribute_it = attributes_by_id.find(parser_program.attribute_id);
        auto geometry_it = geometries_by_id.find(parser_program.geometry_instance_id);
        if (attribute_it == attributes_by_id.end() || geometry_it == geometries_by_id.end()) continue;
        const runtime::CompiledSemantic semantic = semantic_for_attribute(*attribute_it->second);
        if (!is_supported_color_semantic(semantic)) continue;
        runtime::CompiledDmxSourceProgram runtime_program;
        runtime_program.program_id = next_program_id++;
        runtime_program.semantic = semantic;
        runtime_program.sources = make_sources(scene, patch, parser_program, artnet_universe);
        if (runtime_program.sources.empty()) continue;
        runtime_program.dmx_from = parser_program.dmx_from;
        runtime_program.dmx_to = parser_program.dmx_to;
        runtime_program.physical_from = parser_program.physical_from;
        runtime_program.physical_to = parser_program.physical_to;
        runtime_program.attribute_name = parser_program.attribute_name;
        runtime_program.function_name = parser_program.function_name.empty() ? parser_program.attribute_name : parser_program.function_name;
        runtime_program.geometry_id = parser_program.geometry_instance_id;
        runtime_program.geometry_name = geometry_it->second->path;
        runtime_program.emitter_resource_id = parser_program.emitter_resource_id > 0 ? stable_id(patch.fixture_uuid, "emitter:" + std::to_string(parser_program.emitter_resource_id)) : 0;
        runtime_program.filter_resource_id = parser_program.filter_resource_id > 0 ? stable_id(patch.fixture_uuid, "filter:" + std::to_string(parser_program.filter_resource_id)) : 0;
        runtime_program.color_space_name = parser_program.color_space_name;
        scene.source_programs.push_back(runtime_program);
        for (const runtime::CompiledBeamOpticalProfile &beam : scene.beam_profiles) {
            if (beam.fixture_id != fixture_id || !color_channel_controls_beam(*geometry_it->second, beam)) continue;
            runtime::CompiledColorTargetProgram &target = targets_by_beam_id[beam.render_target_id];
            if (target.beam_render_target_id == 0) {
                target.color_target_id = stable_id(patch.fixture_uuid, "color:target:" + beam.geometry_path);
                target.fixture_id = fixture_id;
                target.beam_render_target_id = beam.render_target_id;
                target.geometry_id = beam.geometry_instance_id;
                target.geometry_name = beam.geometry_path;
                target.geometry_key = beam.geometry_key;
            }
            const bool additive = semantic == runtime::CompiledSemantic::ColorAddRed || semantic == runtime::CompiledSemantic::ColorAddGreen || semantic == runtime::CompiledSemantic::ColorAddBlue || semantic == runtime::CompiledSemantic::ColorAddWhite || semantic == runtime::CompiledSemantic::ColorAddAmber || semantic == runtime::CompiledSemantic::ColorAddLime;
            target.additive_source = target.additive_source || additive;
            const bool valid_additive_physical = !additive || (parser_program.physical_from >= 0.0 && parser_program.physical_from <= 1.0 && parser_program.physical_to >= 0.0 && parser_program.physical_to <= 1.0);
            target.inputs.push_back({runtime_program.program_id, semantic, 0.0, !valid_additive_physical, runtime_program.emitter_resource_id, runtime_program.filter_resource_id});
        }
    }
    for (auto &[_, target] : targets_by_beam_id) {
        if (!target.inputs.empty()) scene.color_targets.push_back(target);
    }
}

// Finds a parser-owned wheel by local ID.
const ParsedWheel *find_wheel(const CompiledGdtfFixtureType &fixture, int32_t wheel_id) {
    for (const ParsedWheel &wheel : fixture.wheels) if (wheel.id == wheel_id) return &wheel;
    return nullptr;
}

struct WheelTransmissionCook {
    runtime::LinearRgb shape{1.0, 1.0, 1.0};
    double gain = 1.0;
    bool valid = true;
    bool closed = false;
    bool clamped_negative = false;
};

// Clamps passive filter scalar transmission to the renderer-supported range.
double clamp_passive_filter_gain(runtime::CompiledRuntimeScene &scene, const SceneModel::FixturePatch &patch, const std::string &subject, double gain) {
    if (!std::isfinite(gain) || gain < 0.0) return 0.0;
    if (gain > 1.0) {
        scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-TRANSMISSION-CLAMPED", "warning", "Passive wheel Filter transmission above 1.0 was clamped to avoid creating energy.", patch.fixture_uuid + " " + subject + " gain=" + std::to_string(gain)});
        return 1.0;
    }
    return gain;
}

// Converts linear RGB into bounded transmission shape and an optional scalar gain.
WheelTransmissionCook cook_transmission_from_linear(runtime::CompiledRuntimeScene &scene,
                                                    const SceneModel::FixturePatch &patch,
                                                    const std::string &subject,
                                                    runtime::LinearRgb linear,
                                                    bool extract_gain,
                                                    bool zero_source_means_closed) {
    WheelTransmissionCook cooked;
    const double values[3] = {linear.r, linear.g, linear.b};
    cooked.clamped_negative = values[0] < 0.0 || values[1] < 0.0 || values[2] < 0.0;
    if (cooked.clamped_negative) {
        scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-RGB-CLAMPED", "warning", "Wheel Filter RGB transmission contained negative components that were clamped for subtractive rendering.", patch.fixture_uuid + " " + subject});
    }
    runtime::LinearRgb safe{std::isfinite(linear.r) ? std::max(0.0, linear.r) : 0.0,
                            std::isfinite(linear.g) ? std::max(0.0, linear.g) : 0.0,
                            std::isfinite(linear.b) ? std::max(0.0, linear.b) : 0.0};
    const double max_component = std::max(safe.r, std::max(safe.g, safe.b));
    if (max_component <= 0.0 || !std::isfinite(max_component)) {
        if (zero_source_means_closed) {
            cooked.shape = {1.0, 1.0, 1.0};
            cooked.gain = 0.0;
            cooked.closed = true;
            return cooked;
        }
        cooked.valid = false;
        return cooked;
    }
    cooked.shape = {std::clamp(safe.r / max_component, 0.0, 1.0),
                    std::clamp(safe.g / max_component, 0.0, 1.0),
                    std::clamp(safe.b / max_component, 0.0, 1.0)};
    cooked.gain = extract_gain ? max_component : 1.0;
    return cooked;
}

// Derives a bounded transmission shape from a ColorCIE value and extracts Y-derived energy once when requested.
WheelTransmissionCook cook_transmission_from_cie(runtime::CompiledRuntimeScene &scene,
                                                 const SceneModel::FixturePatch &patch,
                                                 const std::string &subject,
                                                 const PhysicalColorCIE &color,
                                                 bool extract_gain) {
    const runtime::CieXyz xyz = runtime::cie_xyy_to_xyz({color.x, color.y, color.Y, true});
    const runtime::LinearRgb rgb = runtime::xyz_to_linear_srgb(xyz);
    return cook_transmission_from_linear(scene, patch, subject, rgb, extract_gain, color.Y <= 0.0);
}

// Chooses the most complete Filter measurement for full-insertion wheel slots.
const PhysicalColorMeasurement *select_filter_measurement(const PhysicalFilterResource &filter) {
    const PhysicalColorMeasurement *measurement = nullptr;
    for (const PhysicalColorMeasurement &candidate : filter.measurements) {
        if (measurement == nullptr || candidate.physical_percent >= measurement->physical_percent) measurement = &candidate;
    }
    return measurement;
}

// Cooks one wheel slot into immutable renderer-ready optical data.
runtime::CompiledWheelPaletteSlot cook_wheel_slot(runtime::CompiledRuntimeScene &scene, const SceneModel::FixturePatch &patch, const CompiledGdtfFixtureType &fixture_type, const ParsedWheelSlot &slot) {
    runtime::CompiledWheelPaletteSlot out;
    out.slot_index = slot.slot_index;
    out.name = slot.name;
    out.filter_resource_id = slot.filter_resource_id;
    out.media_file_name = slot.media_file_name;
    out.provenance = slot.provenance;
    WheelTransmissionCook cooked;
    if (slot.filter_resource_id > 0) {
        bool found_filter = false;
        for (const PhysicalFilterResource &filter : fixture_type.filters) {
            if (filter.id != slot.filter_resource_id) continue;
            found_filter = true;
            const PhysicalColorMeasurement *measurement = select_filter_measurement(filter);
            if (measurement != nullptr) {
                cooked.gain = clamp_passive_filter_gain(scene, patch, "filter=" + filter.name, measurement->transmission);
                std::vector<runtime::SpectralSample> samples;
                for (const PhysicalSpectralPoint &point : measurement->spectral_points) samples.push_back({point.wavelength_nm, point.energy});
                const runtime::CieXyz xyz = runtime::spectrum_to_xyz(samples);
                if (xyz.valid) {
                    cooked = cook_transmission_from_linear(scene, patch, "filter=" + filter.name, runtime::xyz_to_linear_srgb(xyz), false, false);
                    cooked.gain = clamp_passive_filter_gain(scene, patch, "filter=" + filter.name, measurement->transmission);
                    out.provenance = "filter_measurement_spectrum_relative_shape:" + filter.name;
                    scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-SPECTRUM-RELATIVE", "info", "Wheel Filter measurement spectrum is used as relative chromatic shape; Measurement.Transmission supplies scalar gain.", patch.fixture_uuid + " filter=" + filter.name});
                } else if (filter.color.valid) {
                    cooked = cook_transmission_from_cie(scene, patch, "filter=" + filter.name, filter.color, false);
                    cooked.gain = clamp_passive_filter_gain(scene, patch, "filter=" + filter.name, measurement->transmission);
                    out.provenance = "filter_measurement_color_cie_shape:" + filter.name;
                } else {
                    cooked.shape = {1.0, 1.0, 1.0};
                    cooked.gain = clamp_passive_filter_gain(scene, patch, "filter=" + filter.name, measurement->transmission);
                    out.provenance = "filter_measurement_neutral_shape:" + filter.name;
                }
            } else if (filter.color.valid) {
                cooked = cook_transmission_from_cie(scene, patch, "filter=" + filter.name, filter.color, true);
                cooked.gain = clamp_passive_filter_gain(scene, patch, "filter=" + filter.name, cooked.gain);
                out.provenance = "filter_color_cie_shape_gain:" + filter.name;
                scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-COLORCIE-NO-MEASUREMENT", "info", "Wheel Filter ColorCIE is used for both relative chromatic shape and scalar transmission because no measurement transmission is present.", patch.fixture_uuid + " filter=" + filter.name});
            }
            break;
        }
        if (!found_filter) {
            scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-LINK-MISSING", "warning", "Wheel Slot references a missing Filter; using identity transmission fallback.", patch.fixture_uuid + " slot=" + std::to_string(slot.slot_index)});
        }
    } else if (slot.color.valid) {
        cooked = cook_transmission_from_cie(scene, patch, "slot=" + std::to_string(slot.slot_index), slot.color, true);
        cooked.gain = clamp_passive_filter_gain(scene, patch, "slot=" + std::to_string(slot.slot_index), cooked.gain);
    }
    if (!cooked.valid) {
        scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-SLOT-COOK-FALLBACK", "warning", "Wheel Slot color cooked to invalid RGB; using identity fallback.", patch.fixture_uuid + " slot=" + std::to_string(slot.slot_index)});
        cooked.shape = {1.0, 1.0, 1.0};
        cooked.gain = 1.0;
    }
    out.linear_red = static_cast<float>(cooked.shape.r);
    out.linear_green = static_cast<float>(cooked.shape.g);
    out.linear_blue = static_cast<float>(cooked.shape.b);
    out.gain = static_cast<float>(cooked.gain);
    out.srgb_red = cooked.gain <= 0.0 ? 0.0f : static_cast<float>(runtime::srgb_encode(cooked.shape.r));
    out.srgb_green = cooked.gain <= 0.0 ? 0.0f : static_cast<float>(runtime::srgb_encode(cooked.shape.g));
    out.srgb_blue = cooked.gain <= 0.0 ? 0.0f : static_cast<float>(runtime::srgb_encode(cooked.shape.b));
    out.identity = out.media_file_name.empty() && std::fabs(out.linear_red - 1.0f) < 0.001f && std::fabs(out.linear_green - 1.0f) < 0.001f && std::fabs(out.linear_blue - 1.0f) < 0.001f && std::fabs(out.gain - 1.0f) < 0.001f;
    return out;
}


// Classifies GDTF color-wheel attributes into the supported native wheel runtime modes.
runtime::CompiledWheelMode classify_wheel_mode(const std::string &attribute_name) {
    const std::string lower = dmx::lower_ascii(dmx::trim_ascii(attribute_name));
    if (lower.find("wheelaudio") != std::string::npos) return runtime::CompiledWheelMode::AudioUnsupported;
    if (lower.find("wheelrandom") != std::string::npos) return runtime::CompiledWheelMode::Random;
    if (lower.find("wheelspin") != std::string::npos) return runtime::CompiledWheelMode::Spin;
    if (lower.find("wheelindex") != std::string::npos) return runtime::CompiledWheelMode::Index;
    return runtime::CompiledWheelMode::Select;
}

// Appends color-wheel palettes and exact Beam target bindings for seated selection.
void append_wheel_targets(runtime::CompiledRuntimeScene &scene,
                          const SceneModel::FixturePatch &patch,
                          const CompiledGdtfFixtureType &fixture_type,
                          int artnet_universe,
                          int32_t fixture_id,
                          int32_t &next_program_id) {
    std::unordered_map<int32_t, const AttributeIdentity *> attributes_by_id;
    std::unordered_map<int32_t, const GeometryInstance *> geometries_by_id;
    for (const AttributeIdentity &attribute : fixture_type.attributes) attributes_by_id[attribute.id] = &attribute;
    for (const GeometryInstance &geometry : fixture_type.geometries) geometries_by_id[geometry.id] = &geometry;
    std::unordered_map<int32_t, int32_t> renderer_id_by_wheel;
    for (const ParsedWheel &wheel : fixture_type.wheels) {
        if (wheel.slots.empty()) continue;
        runtime::CompiledWheelPalette palette;
        palette.fixture_id = fixture_id;
        palette.wheel_renderer_id = stable_id(patch.fixture_uuid, "wheel:palette:" + wheel.name);
        palette.name = wheel.name;
        int32_t expected_slot_index = 1;
        for (const ParsedWheelSlot &slot : wheel.slots) {
            runtime::CompiledWheelPaletteSlot compiled_slot = cook_wheel_slot(scene, patch, fixture_type, slot);
            if (slot.slot_index != expected_slot_index || compiled_slot.slot_index != slot.slot_index) {
                scene.diagnostics.push_back({"PVZ-GDTF-WHEEL-SLOT-INTEGRITY", "error", "Wheel Slot declaration order and compiled one-based index diverged.", patch.fixture_uuid + " wheel=" + wheel.name + " slot=" + std::to_string(slot.slot_index)});
            }
            palette.slots.push_back(compiled_slot);
            ++expected_slot_index;
        }
        renderer_id_by_wheel[wheel.id] = palette.wheel_renderer_id;
        scene.wheel_palettes.push_back(palette);
    }
    for (const ChannelProgram &parser_program : fixture_type.channel_programs) {
        if (parser_program.wheel_id <= 0) continue;
        const runtime::CompiledWheelMode wheel_mode = classify_wheel_mode(parser_program.attribute_name);
        if (wheel_mode == runtime::CompiledWheelMode::Select && parser_program.wheel_channel_sets.empty()) continue;
        if (wheel_mode == runtime::CompiledWheelMode::Index) scene.diagnostics.push_back({"PVZ-WHEEL-INDEX-AGGREGATE-FALLBACK", "info", "Color wheel index uses PeravizIndexedWheelAggregateFallback until spatial split rendering is implemented.", patch.fixture_uuid + " attribute=" + parser_program.attribute_name});
        auto attribute_it = attributes_by_id.find(parser_program.attribute_id);
        auto geometry_it = geometries_by_id.find(parser_program.geometry_instance_id);
        if (attribute_it == attributes_by_id.end() || geometry_it == geometries_by_id.end()) continue;
        if (attribute_it->second->canonical_family != "Color" && dmx::lower_ascii(parser_program.attribute_name).find("color") == std::string::npos) continue;
        runtime::CompiledDmxSourceProgram runtime_program;
        runtime_program.program_id = next_program_id++;
        runtime_program.semantic = runtime::CompiledSemantic::Unknown;
        runtime_program.sources = make_sources(scene, patch, parser_program, artnet_universe);
        if (runtime_program.sources.empty()) continue;
        runtime_program.dmx_from = parser_program.dmx_from;
        runtime_program.dmx_to = parser_program.dmx_to;
        runtime_program.physical_from = parser_program.physical_from;
        runtime_program.physical_to = parser_program.physical_to;
        runtime_program.attribute_name = parser_program.attribute_name;
        runtime_program.function_name = parser_program.function_name.empty() ? parser_program.attribute_name : parser_program.function_name;
        runtime_program.geometry_id = parser_program.geometry_instance_id;
        runtime_program.geometry_name = geometry_it->second->path;
        scene.source_programs.push_back(runtime_program);
        for (const runtime::CompiledBeamOpticalProfile &beam : scene.beam_profiles) {
            if (beam.fixture_id != fixture_id || !color_channel_controls_beam(*geometry_it->second, beam)) continue;
            runtime::CompiledWheelTargetBinding binding;
            binding.binding_id = stable_id(patch.fixture_uuid, "wheel:binding:" + std::to_string(parser_program.id) + ":" + beam.geometry_path);
            binding.fixture_id = fixture_id;
            binding.beam_render_target_id = beam.render_target_id;
            binding.wheel_renderer_id = renderer_id_by_wheel[parser_program.wheel_id];
            binding.source_program_id = runtime_program.program_id;
            binding.mode = wheel_mode;
            binding.snap = parser_program.snap;
            for (const ParsedWheelChannelSet &set : parser_program.wheel_channel_sets) binding.channel_sets.push_back({set.declared_dmx_from, set.effective_dmx_to, set.wheel_slot_index, set.name});
            if (binding.wheel_renderer_id > 0) scene.wheel_bindings.push_back(binding);
        }
    }
    scene.wheel_palette_count = static_cast<int32_t>(scene.wheel_palettes.size());
    scene.wheel_binding_count = static_cast<int32_t>(scene.wheel_bindings.size());
}

} // namespace

// Compiles scene fixture patches and parser-owned GDTF ChannelFunctions into visual runtime programs.
runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset) {
    runtime::CompiledRuntimeScene out;
    out.mvr_fixture_patches = static_cast<int32_t>(scene.fixture_patches.size());
    int32_t next_program_id = 1;
    std::unordered_set<int32_t> generated_ids;
    std::unordered_map<std::string, CompiledGdtfFixtureType> fixture_type_cache;
    for (const SceneModel::FixturePatch &patch : scene.fixture_patches) {
        if (patch.fixture_uuid.empty() || patch.mvr_universe <= 0 || patch.mvr_address <= 0 || patch.mvr_address > 512 || patch.dmx_mode.empty() || patch.gdtf_path.empty()) {
            out.diagnostics.push_back({"PVZ-GDTF-FIXTURE-SKIPPED", "warning", "Fixture patch is missing UUID, mode, GDTF path, universe, or address.", patch.fixture_uuid});
            continue;
        }
        const int artnet_universe = patch.mvr_universe + universe_offset;
        const int32_t fixture_id = stable_id(patch.fixture_uuid, "fixture");
        check_generated_id(generated_ids, out, fixture_id, patch.fixture_uuid);
        const std::string cache_key = fixture_type_cache_key(patch);
        auto cache_it = fixture_type_cache.find(cache_key);
        if (cache_it == fixture_type_cache.end()) {
            cache_it = fixture_type_cache.emplace(cache_key, compile_gdtf_fixture_type(patch.gdtf_path, patch.dmx_mode)).first;
            add_fixture_type_counters(out, cache_it->second);
        }
        const CompiledGdtfFixtureType &fixture_type = cache_it->second;
        for (const RuntimeDiagnostic &diagnostic : fixture_type.diagnostics) {
            out.diagnostics.push_back({diagnostic.code, diagnostic.severity, diagnostic.message, patch.fixture_uuid + " mode=" + patch.dmx_mode + " " + diagnostic.subject});
        }
        for (const PhysicalEmitterResource &emitter : fixture_type.emitters) {
            runtime::CompiledEmitterResource compiled;
            compiled.resource_id = stable_id(patch.fixture_uuid, "emitter:" + std::to_string(emitter.id));
            compiled.name = emitter.name;
            compiled.color = {emitter.color.x, emitter.color.y, emitter.color.Y, emitter.color.valid};
            compiled.dominant_wavelength_nm = emitter.dominant_wavelength_nm;
            compiled.has_dominant_wavelength = emitter.has_dominant_wavelength;
            for (const PhysicalColorMeasurement &measurement : emitter.measurements) {
                runtime::CompiledColorMeasurement cm;
                cm.physical_percent = measurement.physical_percent;
                cm.luminous_intensity = measurement.luminous_intensity;
                cm.transmission = measurement.transmission;
                cm.interpolation_to = measurement.interpolation_to;
                for (const PhysicalSpectralPoint &point : measurement.spectral_points) cm.spectral_points.push_back({point.wavelength_nm, point.energy});
                std::vector<runtime::SpectralSample> samples;
                for (const runtime::CompiledSpectralPoint &point : cm.spectral_points) samples.push_back({point.wavelength_nm, point.energy});
                const runtime::CieXyz xyz = runtime::spectrum_to_xyz(samples);
                cm.has_spectrum_xyz = xyz.valid;
                cm.xyz_x = xyz.x; cm.xyz_y = xyz.y; cm.xyz_z = xyz.z;
                compiled.measurements.push_back(cm);
            }
            const runtime::CieXyz xyz = compiled.color.valid ? runtime::cie_xyy_to_xyz({compiled.color.x, compiled.color.y, compiled.color.Y, true}) : runtime::dominant_wavelength_to_xyz(compiled.dominant_wavelength_nm);
            const runtime::LinearRgb rgb = runtime::xyz_to_linear_srgb(xyz);
            compiled.fallback_linear_r = rgb.r; compiled.fallback_linear_g = rgb.g; compiled.fallback_linear_b = rgb.b;
            compiled.valid = xyz.valid || !compiled.measurements.empty();
            out.emitter_resources.push_back(compiled);
        }
        for (const PhysicalFilterResource &filter : fixture_type.filters) {
            runtime::CompiledFilterResource compiled;
            compiled.resource_id = stable_id(patch.fixture_uuid, "filter:" + std::to_string(filter.id));
            compiled.name = filter.name;
            compiled.color = {filter.color.x, filter.color.y, filter.color.Y, filter.color.valid};
            for (const PhysicalColorMeasurement &measurement : filter.measurements) {
                runtime::CompiledColorMeasurement cm;
                cm.physical_percent = measurement.physical_percent;
                cm.luminous_intensity = measurement.luminous_intensity;
                cm.transmission = measurement.transmission;
                cm.interpolation_to = measurement.interpolation_to;
                for (const PhysicalSpectralPoint &point : measurement.spectral_points) cm.spectral_points.push_back({point.wavelength_nm, point.energy});
                std::vector<runtime::SpectralSample> samples;
                for (const runtime::CompiledSpectralPoint &point : cm.spectral_points) samples.push_back({point.wavelength_nm, point.energy});
                const runtime::CieXyz xyz = runtime::spectrum_to_xyz(samples);
                cm.has_spectrum_xyz = xyz.valid;
                cm.xyz_x = xyz.x; cm.xyz_y = xyz.y; cm.xyz_z = xyz.z;
                compiled.measurements.push_back(cm);
            }
            const runtime::CieXyz xyz = runtime::cie_xyy_to_xyz({compiled.color.x, compiled.color.y, compiled.color.Y, compiled.color.valid});
            const runtime::LinearRgb rgb = runtime::xyz_to_linear_srgb(xyz);
            compiled.fallback_linear_r = rgb.r; compiled.fallback_linear_g = rgb.g; compiled.fallback_linear_b = rgb.b;
            compiled.fallback_transmission = compiled.color.valid ? std::clamp(compiled.color.Y, 0.0, 1.0) : 1.0;
            compiled.valid = xyz.valid || !compiled.measurements.empty();
            out.filter_resources.push_back(compiled);
        }
        out.fixtures.push_back({fixture_id, patch.fixture_uuid, patch.gdtf_path, patch.dmx_mode, artnet_universe, patch.mvr_address, 10000.0, 25.0, 1.0, 20.0});
        append_beam_profiles(out, scene, patch, fixture_id);
        std::unordered_map<int32_t, std::vector<const ChannelProgram *>> programs_by_component;
        for (const ChannelProgram &program : fixture_type.channel_programs) programs_by_component[program.component_id].push_back(&program);
        const size_t property_start = out.properties.size();
        for (const ComponentBinding &component : fixture_type.components) append_property(out, patch, fixture_type, component, programs_by_component[component.component_id], artnet_universe, fixture_id, next_program_id);
        append_color_targets(out, patch, fixture_type, artnet_universe, fixture_id, next_program_id);
        append_wheel_targets(out, patch, fixture_type, artnet_universe, fixture_id, next_program_id);
        if (out.properties.size() == property_start && out.color_targets.empty()) out.diagnostics.push_back({"PVZ-GDTF-NO-SUPPORTED-PROPERTIES", "error", "Fixture has no supported Dimmer/Pan/Tilt/Zoom ChannelFunction records in the selected mode.", patch.fixture_uuid + " mode=" + patch.dmx_mode + " universe=" + std::to_string(artnet_universe) + " address=" + std::to_string(patch.mvr_address)});
    }
    for (const auto &property : out.properties) {
        check_generated_id(generated_ids, out, property.property_id, std::to_string(property.fixture_id));
        check_generated_id(generated_ids, out, property.component_id, std::to_string(property.fixture_id));
        if (property.render_target_id != property.component_id && property.render_target_id != property.property_id) check_generated_id(generated_ids, out, property.render_target_id, std::to_string(property.fixture_id));
    }
    for (const auto &target : out.color_targets) {
        check_generated_id(generated_ids, out, target.color_target_id, std::to_string(target.fixture_id));
    }
    return out;
}

} // namespace peraviz::gdtf_runtime
