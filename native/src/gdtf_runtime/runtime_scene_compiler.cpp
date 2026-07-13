#include "gdtf_runtime/runtime_scene_compiler.h"

#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/gdtf_xml_reader.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>

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
    const dmx::ParsedAttribute parsed = dmx::parse_attribute_name(attribute.name);
    if (parsed.role == dmx::AttributeRole::kDimmer) return runtime::CompiledSemantic::Dimmer;
    if (parsed.role == dmx::AttributeRole::kPan) return runtime::CompiledSemantic::Pan;
    if (parsed.role == dmx::AttributeRole::kTilt) return runtime::CompiledSemantic::Tilt;
    if (parsed.role == dmx::AttributeRole::kZoom) return runtime::CompiledSemantic::Zoom;
    return runtime::CompiledSemantic::Unknown;
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
    if (semantic == runtime::CompiledSemantic::Unknown) return;
    const std::string semantic_label = semantic == runtime::CompiledSemantic::Pan ? "pan" : semantic == runtime::CompiledSemantic::Tilt ? "tilt" : semantic == runtime::CompiledSemantic::Zoom ? "zoom" : "dimmer";
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
        out.fixtures.push_back({fixture_id, patch.fixture_uuid, patch.gdtf_path, patch.dmx_mode, artnet_universe, patch.mvr_address, 10000.0, 25.0, 1.0, 20.0});
        append_beam_profiles(out, scene, patch, fixture_id);
        std::unordered_map<int32_t, std::vector<const ChannelProgram *>> programs_by_component;
        for (const ChannelProgram &program : fixture_type.channel_programs) programs_by_component[program.component_id].push_back(&program);
        const size_t property_start = out.properties.size();
        for (const ComponentBinding &component : fixture_type.components) append_property(out, patch, fixture_type, component, programs_by_component[component.component_id], artnet_universe, fixture_id, next_program_id);
        if (out.properties.size() == property_start) out.diagnostics.push_back({"PVZ-GDTF-NO-SUPPORTED-PROPERTIES", "error", "Fixture has no supported Dimmer/Pan/Tilt/Zoom ChannelFunction records in the selected mode.", patch.fixture_uuid + " mode=" + patch.dmx_mode + " universe=" + std::to_string(artnet_universe) + " address=" + std::to_string(patch.mvr_address)});
    }
    for (const auto &property : out.properties) {
        check_generated_id(generated_ids, out, property.property_id, std::to_string(property.fixture_id));
        check_generated_id(generated_ids, out, property.component_id, std::to_string(property.fixture_id));
        if (property.render_target_id != property.component_id && property.render_target_id != property.property_id) check_generated_id(generated_ids, out, property.render_target_id, std::to_string(property.fixture_id));
    }
    return out;
}

} // namespace peraviz::gdtf_runtime
