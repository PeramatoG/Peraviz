#include "gdtf_runtime/runtime_scene_compiler.h"

#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/gdtf_physical_ranges.h"
#include "dmx/gdtf_xml_reader.h"

#include <algorithm>
#include <cstdint>
#include <cmath>
#include <unordered_set>

#include <tinyxml2.h>

namespace peraviz::gdtf_runtime {
namespace {

struct CompiledFunctionCandidate {
    runtime::CompiledSemantic semantic = runtime::CompiledSemantic::Unknown;
    std::string attribute_name;
    std::string function_name;
    std::string geometry_name;
    std::vector<int> offsets_1_based;
    uint32_t dmx_from = 0;
    uint32_t dmx_to = 255;
    double physical_from = 0.0;
    double physical_to = 1.0;
    bool used_physical_fallback = false;
};

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

// Returns a case-compatible XML attribute value.
const char *attr(tinyxml2::XMLElement *element, const char *upper, const char *lower) {
    const char *value = element ? element->Attribute(upper) : nullptr;
    return value ? value : (element ? element->Attribute(lower) : nullptr);
}

// Reads a float XML attribute with common GDTF casing variants.
bool read_float_attr(tinyxml2::XMLElement *element, const char *upper, const char *lower, double &out) {
    float value = 0.0F;
    if (element && (element->QueryFloatAttribute(upper, &value) == tinyxml2::XML_SUCCESS || element->QueryFloatAttribute(lower, &value) == tinyxml2::XML_SUCCESS)) {
        out = static_cast<double>(value);
        return true;
    }
    return false;
}

// Maps supported GDTF attributes into the current runtime semantic slice.
runtime::CompiledSemantic semantic_for_attribute(const std::string &attribute) {
    const dmx::ParsedAttribute parsed = dmx::parse_attribute_name(attribute);
    if (parsed.role == dmx::AttributeRole::kDimmer) return runtime::CompiledSemantic::Dimmer;
    if (parsed.role == dmx::AttributeRole::kPan) return runtime::CompiledSemantic::Pan;
    if (parsed.role == dmx::AttributeRole::kTilt) return runtime::CompiledSemantic::Tilt;
    return runtime::CompiledSemantic::Unknown;
}

// Returns the explicit physical range or a diagnostic fallback for the supported semantic.
bool resolve_physical(runtime::CompiledRuntimeScene &scene, const SceneModel::FixturePatch &patch, runtime::CompiledSemantic semantic, tinyxml2::XMLElement *fn, double &from, double &to) {
    if (read_float_attr(fn, "PhysicalFrom", "physicalfrom", from) && read_float_attr(fn, "PhysicalTo", "physicalto", to)) {
        return true;
    }
    if (semantic == runtime::CompiledSemantic::Dimmer) { from = 0.0; to = 1.0; }
    if (semantic == runtime::CompiledSemantic::Pan) { from = -270.0; to = 270.0; }
    if (semantic == runtime::CompiledSemantic::Tilt) { from = -135.0; to = 135.0; }
    scene.diagnostics.push_back({"PVZ-GDTF-PHYSICAL-FALLBACK", "warning", "ChannelFunction is missing a valid physical range; using explicit runtime fallback.", patch.fixture_uuid});
    return false;
}

// Parses selected GDTF mode ChannelFunction records into supported runtime candidates.
std::vector<CompiledFunctionCandidate> collect_candidates(runtime::CompiledRuntimeScene &scene, const SceneModel::FixturePatch &patch) {
    std::vector<CompiledFunctionCandidate> out;
    const std::string xml = dmx::read_gdtf_description_xml(patch.gdtf_path);
    if (xml.empty()) { scene.diagnostics.push_back({"PVZ-GDTF-XML-MISSING", "warning", "GDTF description.xml not found.", patch.fixture_uuid}); return out; }
    tinyxml2::XMLDocument doc;
    if (doc.Parse(xml.c_str()) != tinyxml2::XML_SUCCESS || doc.RootElement() == nullptr) { scene.diagnostics.push_back({"PVZ-GDTF-XML-PARSE", "warning", "GDTF description.xml could not be parsed.", patch.fixture_uuid}); return out; }
    tinyxml2::XMLElement *selected_mode = nullptr;
    for (tinyxml2::XMLElement *mode : dmx::collect_elements_by_name(doc.RootElement(), "dmxmode")) {
        const char *name = attr(mode, "Name", "name");
        if (name && patch.dmx_mode == name) { selected_mode = mode; break; }
    }
    if (!selected_mode) { scene.diagnostics.push_back({"PVZ-GDTF-MODE-MISSING", "warning", "Selected DMX mode was not found in the parsed GDTF.", patch.fixture_uuid}); return out; }
    for (tinyxml2::XMLElement *channel : dmx::collect_direct_children_by_name(selected_mode, "dmxchannel")) {
        const std::vector<int> offsets = dmx::parse_offsets(attr(channel, "Offset", "offset"));
        if (offsets.empty()) continue;
        const char *geometry = attr(channel, "Geometry", "geometry");
        for (tinyxml2::XMLElement *logical : dmx::collect_direct_children_by_name(channel, "logicalchannel")) {
            const char *logical_attribute = attr(logical, "Attribute", "attribute");
            std::vector<tinyxml2::XMLElement *> functions = dmx::collect_direct_children_by_name(logical, "channelfunction");
            std::vector<int> starts;
            for (tinyxml2::XMLElement *fn : functions) {
                int dmx_from = dmx::parse_dmx_value_8bit(attr(fn, "DMXFrom", "dmxfrom"));
                starts.push_back(std::clamp(dmx_from < 0 ? 0 : dmx_from, 0, 255));
            }
            for (size_t i = 0; i < functions.size(); ++i) {
                tinyxml2::XMLElement *fn = functions[i];
                const char *attribute = attr(fn, "Attribute", "attribute");
                if (!attribute) attribute = logical_attribute;
                if (!attribute) continue;
                const runtime::CompiledSemantic semantic = semantic_for_attribute(attribute);
                if (semantic == runtime::CompiledSemantic::Unknown) continue;
                int dmx_to = dmx::parse_dmx_value_8bit(attr(fn, "DMXTo", "dmxto"));
                if (dmx_to < 0) dmx_to = (i + 1 < starts.size() && starts[i + 1] > starts[i]) ? starts[i + 1] - 1 : 255;
                double physical_from = 0.0;
                double physical_to = 1.0;
                const bool has_physical = resolve_physical(scene, patch, semantic, fn, physical_from, physical_to);
                const char *fn_name = attr(fn, "Name", "name");
                out.push_back({semantic, attribute, fn_name ? fn_name : attribute, geometry ? geometry : "", offsets, static_cast<uint32_t>(starts[i]), static_cast<uint32_t>(std::clamp(dmx_to, starts[i], 255)), physical_from, physical_to, !has_physical});
            }
        }
    }
    return out;
}


// Returns the maximum raw value for a compiled source byte width.
uint32_t max_for_source_count(size_t source_count) {
    uint32_t max_value = 0;
    for (size_t index = 0; index < source_count && index < 4; ++index) {
        max_value = (max_value << 8U) | 0xffU;
    }
    return max_value;
}

// Expands 8-bit ChannelFunction DMX ranges to the source byte width when needed.
uint32_t scale_dmx_range_value(uint32_t value, size_t source_count) {
    if (source_count <= 1 || value > 255U) return value;
    return static_cast<uint32_t>(std::round((static_cast<double>(value) / 255.0) * static_cast<double>(max_for_source_count(source_count))));
}

// Appends a compiled property/program pair from one real ChannelFunction candidate.
void add_candidate(runtime::CompiledRuntimeScene &scene, const SceneModel::FixturePatch &patch, int32_t &next_program_id, const CompiledFunctionCandidate &candidate) {
    std::vector<runtime::CompiledDmxByteSource> sources;
    for (size_t i = 0; i < candidate.offsets_1_based.size() && i < 4; ++i) {
        const int address = (patch.mvr_address - 1) + (candidate.offsets_1_based[i] - 1);
        sources.push_back({patch.mvr_universe, address, static_cast<int32_t>(i)});
    }
    if (sources.empty()) return;
    if (candidate.offsets_1_based.size() > 4) scene.diagnostics.push_back({"PVZ-GDTF-UNSUPPORTED-BIT-DEPTH", "warning", "Runtime compiler supports up to 32-bit source values.", patch.fixture_uuid});
    const int32_t fixture_id = stable_id(patch.fixture_uuid, "fixture");
    const std::string semantic_label = candidate.semantic == runtime::CompiledSemantic::Pan ? "pan" : candidate.semantic == runtime::CompiledSemantic::Tilt ? "tilt" : "dimmer";
    const int32_t component_id = stable_id(patch.fixture_uuid, semantic_label + ":component:" + candidate.geometry_name);
    const int32_t target_id = candidate.semantic == runtime::CompiledSemantic::Dimmer ? stable_id(patch.fixture_uuid, semantic_label + ":target:" + candidate.geometry_name) : component_id;
    const int32_t program_id = next_program_id++;
    const uint32_t dmx_from = scale_dmx_range_value(candidate.dmx_from, sources.size());
    const uint32_t dmx_to = scale_dmx_range_value(candidate.dmx_to, sources.size());
    scene.source_programs.push_back({program_id, candidate.semantic, sources, dmx_from, dmx_to, candidate.physical_from, candidate.physical_to, candidate.attribute_name, candidate.function_name});
    scene.properties.push_back({fixture_id, component_id, target_id, candidate.semantic, {{program_id, 1.0, runtime::CompiledContributorOperation::WeightedAdd}}});
}

// Checks for nonzero ID collisions in native-generated runtime records.
void check_id(std::unordered_set<int32_t> &ids, runtime::CompiledRuntimeScene &scene, int32_t id, const std::string &subject) {
    if (id <= 0 || !ids.insert(id).second) scene.diagnostics.push_back({"PVZ-RUNTIME-ID-COLLISION", "error", "Native compiler generated an invalid or duplicate runtime ID.", subject});
}

} // namespace

// Compiles scene fixture patches and parser-owned GDTF ChannelFunctions into visual runtime programs.
runtime::CompiledRuntimeScene compile_runtime_scene(const SceneModel &scene, int universe_offset) {
    runtime::CompiledRuntimeScene out;
    int32_t next_program_id = 1;
    std::unordered_set<int32_t> ids;
    for (const SceneModel::FixturePatch &patch : scene.fixture_patches) {
        if (patch.fixture_uuid.empty() || patch.mvr_universe <= 0 || patch.mvr_address <= 0 || patch.mvr_address > 512 || patch.dmx_mode.empty() || patch.gdtf_path.empty()) {
            out.diagnostics.push_back({"PVZ-GDTF-FIXTURE-SKIPPED", "warning", "Fixture patch is missing UUID, mode, GDTF path, universe, or address.", patch.fixture_uuid});
            continue;
        }
        SceneModel::FixturePatch artnet_patch = patch;
        artnet_patch.mvr_universe = patch.mvr_universe + universe_offset;
        const int32_t fixture_id = stable_id(patch.fixture_uuid, "fixture");
        check_id(ids, out, fixture_id, patch.fixture_uuid);
        out.fixtures.push_back({fixture_id, patch.fixture_uuid, patch.gdtf_path, patch.dmx_mode, artnet_patch.mvr_universe, patch.mvr_address, 10000.0, 25.0, 1.0, 20.0});
        const size_t property_start = out.properties.size();
        for (const CompiledFunctionCandidate &candidate : collect_candidates(out, artnet_patch)) add_candidate(out, artnet_patch, next_program_id, candidate);
        if (out.properties.size() == property_start) out.diagnostics.push_back({"PVZ-GDTF-NO-SUPPORTED-PROPERTIES", "warning", "Fixture has no supported Dimmer/Pan/Tilt ChannelFunction records in the selected mode.", patch.fixture_uuid});
    }
    for (const auto &property : out.properties) {
        check_id(ids, out, property.component_id, std::to_string(property.fixture_id));
        if (property.render_target_id != property.component_id) check_id(ids, out, property.render_target_id, std::to_string(property.fixture_id));
    }
    return out;
}

} // namespace peraviz::gdtf_runtime
