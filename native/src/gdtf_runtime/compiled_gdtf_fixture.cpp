#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/gdtf_xml_reader.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <unordered_map>

namespace peraviz::gdtf_runtime {
namespace {

struct AttributePattern {
    const char *family;
    const char *canonical_pattern;
    int wildcard_count;
};

constexpr AttributePattern kOfficialAttributePatterns[] = {
    {"Dimmer", "Dimmer", 0}, {"Pan", "Pan", 0}, {"Tilt", "Tilt", 0}, {"Zoom", "Zoom", 0},
    {"Cyan", "Cyan", 0}, {"Magenta", "Magenta", 0}, {"Yellow", "Yellow", 0}, {"Strobe", "Strobe", 0},
    {"Gobo", "Gobo(n)", 1}, {"Gobo", "Gobo(n)SelectShake", 1}, {"Gobo", "Gobo(n)Index", 1}, {"Gobo", "Gobo(n)Rotate", 1},
    {"AnimationWheel", "AnimationWheel(n)", 1}, {"Color", "Color(n)", 1}, {"Prism", "Prism(n)", 1},
    {"Blade", "Blade(n)A", 1}, {"Blade", "Blade(n)B", 1}, {"VideoEffect", "VideoEffect(n)Parameter(n)", 2},
};

// Reads a decimal number starting at offset and advances the cursor when present.
bool read_number(const std::string &name, size_t &offset, int32_t &value) {
    const size_t start = offset;
    while (offset < name.size() && std::isdigit(static_cast<unsigned char>(name[offset])) != 0) {
        ++offset;
    }
    if (start == offset) {
        return false;
    }
    value = std::stoi(name.substr(start, offset - start));
    return true;
}

// Matches the official wildcard families needed by the shared Peraviz/Perastage registry.
bool match_official_pattern(const std::string &name, const AttributePattern &pattern, std::vector<int32_t> &indexes) {
    const std::string family(pattern.family);
    if (name.rfind(family, 0) != 0) {
        return false;
    }
    size_t offset = family.size();
    indexes.clear();
    if (pattern.wildcard_count == 0) {
        return offset == name.size();
    }
    int32_t primary = 0;
    if (!read_number(name, offset, primary)) {
        return false;
    }
    indexes.push_back(primary);
    const std::string canonical(pattern.canonical_pattern);
    if (canonical == "Gobo(n)SelectShake") return name.substr(offset) == "SelectShake";
    if (canonical == "Gobo(n)Index") return name.substr(offset) == "Index";
    if (canonical == "Gobo(n)Rotate") return name.substr(offset) == "Rotate";
    if (canonical == "Blade(n)A") return name.substr(offset) == "A";
    if (canonical == "Blade(n)B") return name.substr(offset) == "B";
    if (canonical == "VideoEffect(n)Parameter(n)") {
        if (name.substr(offset, 9) != "Parameter") return false;
        offset += 9;
        int32_t secondary = 0;
        if (!read_number(name, offset, secondary)) return false;
        indexes.push_back(secondary);
        return offset == name.size();
    }
    return offset == name.size();
}

// Returns a case-insensitive XML attribute value from parser-owned GDTF traversal.
std::string read_attr(tinyxml2::XMLElement *element, const char *upper, const char *lower) {
    return dmx::read_attr_ci(element, upper, lower);
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

// Returns the maximum raw value for a source byte count.
uint32_t max_for_source_count(size_t source_count) {
    uint32_t max_value = 0;
    for (size_t index = 0; index < source_count && index < 4; ++index) {
        max_value = (max_value << 8U) | 0xffU;
    }
    return max_value;
}

// Parses a full-resolution GDTF DMX value and converts it to the compiled source width.
bool parse_dmx_value(const std::string &raw, size_t source_count, uint32_t &out) {
    std::string value = dmx::trim_ascii(raw);
    if (value.empty()) return false;
    int declared_bytes = 1;
    const size_t slash = value.find('/');
    if (slash != std::string::npos) {
        const std::string resolution = dmx::trim_ascii(value.substr(slash + 1));
        value = dmx::trim_ascii(value.substr(0, slash));
        if (!resolution.empty()) {
            char *end = nullptr;
            const long parsed = std::strtol(resolution.c_str(), &end, 10);
            if (end != resolution.c_str() && parsed > 0L) declared_bytes = static_cast<int>(std::clamp(parsed, 1L, 4L));
        }
    }
    char *end = nullptr;
    const unsigned long long parsed = std::strtoull(value.c_str(), &end, 10);
    if (end == value.c_str()) return false;
    const uint32_t declared_max = max_for_source_count(static_cast<size_t>(declared_bytes));
    const uint32_t target_max = max_for_source_count(std::max<size_t>(source_count, 1));
    const uint32_t clamped = static_cast<uint32_t>(std::min<unsigned long long>(parsed, declared_max));
    out = declared_max == target_max ? clamped : static_cast<uint32_t>((static_cast<unsigned long long>(clamped) * target_max + declared_max / 2U) / declared_max);
    return true;
}

// Finds the selected DMX mode element by name.
tinyxml2::XMLElement *find_mode(tinyxml2::XMLElement *root, const std::string &dmx_mode_name) {
    for (tinyxml2::XMLElement *mode : dmx::collect_elements_by_name(root, "dmxmode")) {
        if (read_attr(mode, "Name", "name") == dmx_mode_name) return mode;
    }
    const std::string expected = dmx::lower_ascii(dmx_mode_name);
    for (tinyxml2::XMLElement *mode : dmx::collect_elements_by_name(root, "dmxmode")) {
        if (dmx::lower_ascii(read_attr(mode, "Name", "name")) == expected) return mode;
    }
    return nullptr;
}

// Returns an existing attribute ID or creates a new parser-owned identity.
int32_t attribute_id_for(CompiledGdtfFixtureType &fixture, std::unordered_map<std::string, int32_t> &ids, const std::string &attribute_name) {
    auto it = ids.find(attribute_name);
    if (it != ids.end()) return it->second;
    const int32_t id = static_cast<int32_t>(fixture.attributes.size() + 1);
    ids[attribute_name] = id;
    fixture.attributes.push_back(normalize_attribute_identity(id, attribute_name));
    return id;
}

// Returns an existing geometry ID or creates a new parser-owned geometry identity.
int32_t geometry_id_for(CompiledGdtfFixtureType &fixture, std::unordered_map<std::string, int32_t> &ids, const std::string &geometry_name) {
    const std::string name = geometry_name.empty() ? "Fixture" : geometry_name;
    auto it = ids.find(name);
    if (it != ids.end()) return it->second;
    const int32_t id = static_cast<int32_t>(fixture.geometries.size() + 1);
    ids[name] = id;
    fixture.geometries.push_back({id, 0, name, name, "Geometry"});
    return id;
}

} // namespace

// Produces the canonical serialization-neutral identity used by Peraviz and Perastage test vectors.
AttributeIdentity normalize_attribute_identity(int32_t id, const std::string &attribute_name) {
    AttributeIdentity identity;
    identity.id = id;
    identity.name = attribute_name;
    for (const AttributePattern &pattern : kOfficialAttributePatterns) {
        std::vector<int32_t> indexes;
        if (!match_official_pattern(attribute_name, pattern, indexes)) {
            continue;
        }
        identity.canonical_family = pattern.family;
        identity.wildcard_indexes = indexes;
        identity.primary_index = indexes.empty() ? 0 : indexes[0];
        identity.secondary_index = indexes.size() > 1 ? indexes[1] : 0;
        identity.known_official = true;
        identity.custom = false;
        return identity;
    }
    identity.canonical_family = attribute_name;
    identity.custom = true;
    return identity;
}

// Compiles one selected GDTF DMX mode into a parser-owned fixture type model.
CompiledGdtfFixtureType compile_gdtf_fixture_type(const std::string &gdtf_path, const std::string &dmx_mode_name) {
    CompiledGdtfFixtureType fixture;
    fixture.fixture_type_name = gdtf_path;
    fixture.dmx_mode_name = dmx_mode_name;
    const std::string xml_content = dmx::read_gdtf_description_xml(gdtf_path);
    if (xml_content.empty()) {
        fixture.diagnostics.push_back({"PVZ-GDTF-XML-MISSING", "warning", "GDTF description.xml not found.", gdtf_path});
        return fixture;
    }
    tinyxml2::XMLDocument doc;
    if (doc.Parse(xml_content.c_str()) != tinyxml2::XML_SUCCESS || doc.RootElement() == nullptr) {
        fixture.diagnostics.push_back({"PVZ-GDTF-XML-PARSE", "warning", "GDTF description.xml could not be parsed.", gdtf_path});
        return fixture;
    }
    tinyxml2::XMLElement *selected_mode = find_mode(doc.RootElement(), dmx_mode_name);
    if (!selected_mode) {
        fixture.diagnostics.push_back({"PVZ-GDTF-MODE-MISSING", "warning", "Selected DMX mode was not found in the parsed GDTF.", dmx_mode_name});
        return fixture;
    }
    std::unordered_map<std::string, int32_t> attribute_ids;
    std::unordered_map<std::string, int32_t> geometry_ids;
    int32_t next_component_id = 1;
    int32_t next_program_id = 1;
    std::unordered_map<std::string, int32_t> component_by_key;
    for (tinyxml2::XMLElement *container : dmx::collect_direct_children_by_name(selected_mode, "dmxchannels")) {
        for (tinyxml2::XMLElement *channel : dmx::collect_direct_children_by_name(container, "dmxchannel")) {
            const std::vector<int> offsets = dmx::parse_offsets(read_attr(channel, "Offset", "offset").c_str());
            if (offsets.empty()) continue;
            const std::string geometry_name = read_attr(channel, "Geometry", "geometry");
            const int32_t geometry_id = geometry_id_for(fixture, geometry_ids, geometry_name);
            for (tinyxml2::XMLElement *logical : dmx::collect_direct_children_by_name(channel, "logicalchannel")) {
                const std::string logical_attribute = read_attr(logical, "Attribute", "attribute");
                for (tinyxml2::XMLElement *fn : dmx::collect_direct_children_by_name(logical, "channelfunction")) {
                    std::string attribute_name = read_attr(fn, "Attribute", "attribute");
                    if (attribute_name.empty()) attribute_name = logical_attribute;
                    if (attribute_name.empty()) continue;
                    const int32_t attribute_id = attribute_id_for(fixture, attribute_ids, attribute_name);
                    const std::string component_key = std::to_string(geometry_id) + ":" + std::to_string(attribute_id);
                    int32_t component_id = component_by_key[component_key];
                    if (component_id == 0) {
                        component_id = next_component_id++;
                        component_by_key[component_key] = component_id;
                        fixture.components.push_back({component_id, geometry_id, attribute_id, 0, component_id});
                    }
                    uint32_t dmx_from = 0;
                    uint32_t dmx_to = max_for_source_count(offsets.size());
                    if (!parse_dmx_value(read_attr(fn, "DMXFrom", "dmxfrom"), offsets.size(), dmx_from)) dmx_from = 0;
                    if (!parse_dmx_value(read_attr(fn, "DMXTo", "dmxto"), offsets.size(), dmx_to)) dmx_to = max_for_source_count(offsets.size());
                    if (dmx_to < dmx_from) std::swap(dmx_to, dmx_from);
                    double physical_from = 0.0;
                    double physical_to = 1.0;
                    const bool has_physical = read_float_attr(fn, "PhysicalFrom", "physicalfrom", physical_from) && read_float_attr(fn, "PhysicalTo", "physicalto", physical_to);
                    if (!has_physical) fixture.diagnostics.push_back({"PVZ-GDTF-PHYSICAL-MISSING", "warning", "ChannelFunction is missing PhysicalFrom/PhysicalTo.", attribute_name});
                    const std::string function_name = read_attr(fn, "Name", "name").empty() ? attribute_name : read_attr(fn, "Name", "name");
                    ChannelProgram program;
                    program.id = next_program_id++;
                    for (int offset : offsets) program.dmx_offsets_1_based.push_back(offset);
                    program.bit_depth = static_cast<int32_t>(std::min<size_t>(offsets.size(), 4) * 8U);
                    program.attribute_id = attribute_id;
                    program.geometry_instance_id = geometry_id;
                    program.component_id = component_id;
                    program.dmx_from = dmx_from;
                    program.dmx_to = dmx_to;
                    program.physical_from = physical_from;
                    program.physical_to = physical_to;
                    program.attribute_name = attribute_name;
                    program.function_name = function_name;
                    fixture.channel_programs.push_back(program);
                }
            }
        }
    }
    return fixture;
}

// Builds a small fixture model that proves repeated GDTF wheel families remain independent.
CompiledGdtfFixtureType make_two_gobo_wheel_regression_fixture() {
    CompiledGdtfFixtureType fixture;
    fixture.fixture_type_name = "Peraviz Two Gobo Wheel Regression";
    fixture.dmx_mode_name = "Mode 1";
    fixture.attributes.push_back(normalize_attribute_identity(1, "Dimmer"));
    fixture.attributes.push_back(normalize_attribute_identity(2, "Gobo1"));
    fixture.attributes.push_back(normalize_attribute_identity(3, "Gobo2"));
    fixture.geometries.push_back({1, 0, "Base", "Base", "Geometry"});
    fixture.geometries.push_back({2, 1, "Head", "Head", "Beam"});
    fixture.components.push_back({1, 2, 1, 0, 1});
    fixture.components.push_back({2, 2, 2, 1, 2});
    fixture.components.push_back({3, 2, 3, 2, 3});
    fixture.channel_programs.push_back({1, {1}, 8, 1, 2, 1, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
    fixture.channel_programs.push_back({2, {2}, 8, 2, 2, 2, 0, 127, 0.0, 6.0, "Gobo1", "Gobo1"});
    fixture.channel_programs.push_back({3, {3}, 8, 3, 2, 3, 128, 255, 0.0, 6.0, "Gobo2", "Gobo2"});
    fixture.diagnostics.push_back({"PVZ-GDTF-UNKNOWN-PRESERVED", "info", "Unknown and custom attributes are retained in the semantic model before runtime compilation.", "AttributeDefinitions"});
    return fixture;
}

} // namespace peraviz::gdtf_runtime
