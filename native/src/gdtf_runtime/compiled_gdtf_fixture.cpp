#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include "dmx/gdtf_attribute_classifier.h"
#include "dmx/gdtf_xml_reader.h"
#include "gdtf_runtime/gdtf_geometry_identity.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <functional>
#include <cmath>
#include <sstream>
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

// Parses a physical ColorCIE attribute and normalizes percentage-style Y values.
bool parse_color_cie_value(const std::string &raw, PhysicalColorCIE &out) {
    std::string value = raw;
    for (char &ch : value) if (ch == ',' || ch == ';') ch = ' ';
    std::istringstream stream(value);
    if (!(stream >> out.x >> out.y >> out.Y)) return false;
    if (out.Y > 1.0) out.Y *= 0.01;
    out.valid = std::isfinite(out.x) && std::isfinite(out.y) && std::isfinite(out.Y) && out.x >= 0.0 && out.y > 0.0 && out.Y >= 0.0;
    return out.valid;
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
    const std::string trimmed_name = dmx::trim_ascii(dmx_mode_name);
    for (tinyxml2::XMLElement *mode : dmx::collect_elements_by_name(root, "dmxmode")) {
        if (dmx::trim_ascii(read_attr(mode, "Name", "name")) == trimmed_name) return mode;
    }
    const std::string expected = dmx::lower_ascii(trimmed_name);
    for (tinyxml2::XMLElement *mode : dmx::collect_elements_by_name(root, "dmxmode")) {
        if (dmx::lower_ascii(dmx::trim_ascii(read_attr(mode, "Name", "name"))) == expected) return mode;
    }
    return nullptr;
}

// Collects all DMXChannel descendants scoped to the selected DMXMode while ignoring nested modes.
std::vector<tinyxml2::XMLElement *> collect_mode_dmx_channels(tinyxml2::XMLElement *selected_mode) {
    std::vector<tinyxml2::XMLElement *> channels;
    std::function<void(tinyxml2::XMLElement *)> visit = [&](tinyxml2::XMLElement *element) {
        if (!element) return;
        const std::string name = dmx::lower_ascii(element->Name() ? element->Name() : "");
        if (element != selected_mode && name == "dmxmode") return;
        if (name == "dmxchannel") {
            channels.push_back(element);
            return;
        }
        for (tinyxml2::XMLElement *child = element->FirstChildElement(); child; child = child->NextSiblingElement()) visit(child);
    };
    visit(selected_mode);
    return channels;
}

// Collects ChannelFunction descendants for a logical channel without leaving the selected DMXChannel scope.
std::vector<tinyxml2::XMLElement *> collect_logical_channel_functions(tinyxml2::XMLElement *logical) {
    std::vector<tinyxml2::XMLElement *> functions;
    std::function<void(tinyxml2::XMLElement *)> visit = [&](tinyxml2::XMLElement *element) {
        if (!element) return;
        const std::string name = dmx::lower_ascii(element->Name() ? element->Name() : "");
        if (name == "channelfunction") {
            functions.push_back(element);
            return;
        }
        for (tinyxml2::XMLElement *child = element->FirstChildElement(); child; child = child->NextSiblingElement()) visit(child);
    };
    visit(logical);
    return functions;
}

// Counts direct DMXChannels containers for setup diagnostics.
int32_t count_mode_dmxchannels_containers(tinyxml2::XMLElement *selected_mode) {
    int32_t count = 0;
    for (tinyxml2::XMLElement *child = selected_mode ? selected_mode->FirstChildElement() : nullptr; child; child = child->NextSiblingElement()) {
        if (dmx::lower_ascii(child->Name() ? child->Name() : "") == "dmxchannels") ++count;
    }
    return count;
}

// Builds a best-effort geometry-name to hierarchical path map from the parsed GDTF geometry tree.
std::unordered_map<std::string, std::string> build_geometry_paths(tinyxml2::XMLElement *root, const std::string &root_geometry_name) {
    std::unordered_map<std::string, tinyxml2::XMLElement *> geometry_by_name;
    std::function<void(tinyxml2::XMLElement *)> collect = [&](tinyxml2::XMLElement *element) {
        if (!element) return;
        const std::string name = dmx::trim_ascii(read_attr(element, "Name", "name"));
        if (!name.empty()) geometry_by_name[name] = element;
        for (tinyxml2::XMLElement *child = element->FirstChildElement(); child; child = child->NextSiblingElement()) collect(child);
    };
    for (tinyxml2::XMLElement *geometries : dmx::collect_elements_by_name(root, "geometries")) {
        for (tinyxml2::XMLElement *geometry = geometries->FirstChildElement(); geometry; geometry = geometry->NextSiblingElement()) collect(geometry);
    }
    tinyxml2::XMLElement *root_geometry = nullptr;
    if (!root_geometry_name.empty()) {
        auto it = geometry_by_name.find(root_geometry_name);
        if (it != geometry_by_name.end()) root_geometry = it->second;
    }
    if (!root_geometry && !geometry_by_name.empty()) root_geometry = geometry_by_name.begin()->second;
    std::unordered_map<std::string, std::string> paths;
    std::function<void(tinyxml2::XMLElement *, const std::string &)> visit = [&](tinyxml2::XMLElement *geometry, const std::string &parent_path) {
        if (!geometry) return;
        const std::string tag = dmx::lower_ascii(geometry->Name() ? geometry->Name() : "");
        if (tag == "geometryreference") {
            const std::string reference_name = dmx::trim_ascii(read_attr(geometry, "Geometry", "geometry"));
            auto referenced = geometry_by_name.find(reference_name);
            if (referenced != geometry_by_name.end()) {
                const std::string instance_name = dmx::trim_ascii(read_attr(geometry, "Name", "name"));
                const std::string reference_path = append_geometry_path(parent_path, instance_name);
                visit(referenced->second, reference_path);
            }
            return;
        }
        const std::string name = dmx::trim_ascii(read_attr(geometry, "Name", "name"));
        if (name.empty()) return;
        const std::string path = append_geometry_path(parent_path, name);
        paths[name] = path;
        for (tinyxml2::XMLElement *child = geometry->FirstChildElement(); child; child = child->NextSiblingElement()) {
            visit(child, path);
        }
    };
    visit(root_geometry, "");
    return paths;
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
int32_t geometry_id_for(CompiledGdtfFixtureType &fixture, std::unordered_map<std::string, int32_t> &ids, const std::string &geometry_name, const std::string &geometry_path) {
    const std::string name = geometry_name.empty() ? "Fixture" : geometry_name;
    const std::string path = geometry_path.empty() ? name : geometry_path;
    auto it = ids.find(name);
    if (it != ids.end()) return it->second;
    const int32_t id = static_cast<int32_t>(fixture.geometries.size() + 1);
    ids[name] = id;
    fixture.geometries.push_back({id, 0, name, path, "Geometry"});
    return id;
}

// Parses physical color measurements from an Emitter or Filter resource.
void parse_physical_measurements(tinyxml2::XMLElement *resource, std::vector<PhysicalColorMeasurement> &measurements) {
    for (tinyxml2::XMLElement *measurement : dmx::collect_direct_children_by_name(resource, "measurement")) {
        PhysicalColorMeasurement parsed;
        read_float_attr(measurement, "Physical", "physical", parsed.physical_percent);
        read_float_attr(measurement, "LuminousIntensity", "luminousintensity", parsed.luminous_intensity);
        read_float_attr(measurement, "Transmission", "transmission", parsed.transmission);
        const std::string interpolation = dmx::trim_ascii(read_attr(measurement, "InterpolationTo", "interpolationto"));
        if (!interpolation.empty()) parsed.interpolation_to = interpolation;
        for (tinyxml2::XMLElement *point : dmx::collect_direct_children_by_name(measurement, "measurementpoint")) {
            PhysicalSpectralPoint spectral;
            if (read_float_attr(point, "WaveLength", "wavelength", spectral.wavelength_nm) && read_float_attr(point, "Energy", "energy", spectral.energy)) {
                parsed.spectral_points.push_back(spectral);
            }
        }
        measurements.push_back(parsed);
    }
    std::sort(measurements.begin(), measurements.end(), [](const PhysicalColorMeasurement &a, const PhysicalColorMeasurement &b) { return a.physical_percent < b.physical_percent; });
}

// Parses parser-owned immutable Emitter and Filter physical color resources.
void parse_physical_color_resources(tinyxml2::XMLElement *root, CompiledGdtfFixtureType &fixture) {
    int32_t next_emitter_id = 1;
    int32_t next_filter_id = 1;
    for (tinyxml2::XMLElement *physical : dmx::collect_elements_by_name(root, "physicaldescriptions")) {
        for (tinyxml2::XMLElement *emitters : dmx::collect_direct_children_by_name(physical, "emitters")) {
            for (tinyxml2::XMLElement *emitter : dmx::collect_direct_children_by_name(emitters, "emitter")) {
                PhysicalEmitterResource parsed;
                parsed.id = next_emitter_id++;
                parsed.name = dmx::trim_ascii(read_attr(emitter, "Name", "name"));
                if (parsed.name.empty()) continue;
                parse_color_cie_value(read_attr(emitter, "Color", "color"), parsed.color);
                parsed.has_dominant_wavelength = read_float_attr(emitter, "DominantWaveLength", "dominantwavelength", parsed.dominant_wavelength_nm);
                parse_physical_measurements(emitter, parsed.measurements);
                fixture.emitters.push_back(parsed);
            }
        }
        for (tinyxml2::XMLElement *filters : dmx::collect_direct_children_by_name(physical, "filters")) {
            for (tinyxml2::XMLElement *filter : dmx::collect_direct_children_by_name(filters, "filter")) {
                PhysicalFilterResource parsed;
                parsed.id = next_filter_id++;
                parsed.name = dmx::trim_ascii(read_attr(filter, "Name", "name"));
                if (parsed.name.empty()) continue;
                parse_color_cie_value(read_attr(filter, "Color", "color"), parsed.color);
                parse_physical_measurements(filter, parsed.measurements);
                fixture.filters.push_back(parsed);
            }
        }
    }
}

// Resolves a ChannelFunction physical resource link to a parser-owned stable integer ID.
template <typename Resource>
int32_t resolve_physical_resource_link(const std::vector<Resource> &resources, const std::string &name) {
    if (name.empty()) return 0;
    for (const Resource &resource : resources) {
        if (resource.name == name) return resource.id;
    }
    return -1;
}

// Parses ordered GDTF wheel slots and their direct color/filter metadata.
void parse_wheels(tinyxml2::XMLElement *root, CompiledGdtfFixtureType &fixture) {
    int32_t next_wheel_id = 1;
    for (tinyxml2::XMLElement *wheels : dmx::collect_elements_by_name(root, "wheels")) {
        for (tinyxml2::XMLElement *wheel_node : dmx::collect_direct_children_by_name(wheels, "wheel")) {
            ParsedWheel wheel;
            wheel.id = next_wheel_id++;
            wheel.name = dmx::trim_ascii(read_attr(wheel_node, "Name", "name"));
            if (wheel.name.empty()) {
                fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-NAME-MISSING", "warning", "Wheel has no Name and cannot be linked by ChannelFunction.Wheel.", "Wheels"});
                continue;
            }
            int32_t slot_index = 1;
            for (tinyxml2::XMLElement *slot_node : dmx::collect_direct_children_by_name(wheel_node, "slot")) {
                ParsedWheelSlot slot;
                slot.slot_index = slot_index++;
                slot.name = dmx::trim_ascii(read_attr(slot_node, "Name", "name"));
                slot.media_file_name = dmx::trim_ascii(read_attr(slot_node, "MediaFileName", "mediafilename"));
                const std::string filter_name = dmx::trim_ascii(read_attr(slot_node, "Filter", "filter"));
                const std::string color_value = dmx::trim_ascii(read_attr(slot_node, "Color", "color"));
                if (!filter_name.empty()) {
                    slot.filter_resource_id = resolve_physical_resource_link(fixture.filters, filter_name);
                    slot.provenance = "filter:" + filter_name;
                    if (slot.filter_resource_id < 0) fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-FILTER-LINK-MISSING", "warning", "Wheel Slot references an unknown Filter.", wheel.name + ":" + slot.name});
                    if (!color_value.empty()) fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-SLOT-COLOR-IGNORED", "info", "Wheel Slot has both Filter and Color; Filter takes precedence.", wheel.name + ":" + slot.name});
                } else if (!color_value.empty()) {
                    if (parse_color_cie_value(color_value, slot.color)) {
                        slot.provenance = "slot_color_cie";
                    } else {
                        slot.provenance = "malformed_color_fallback_white";
                        fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-SLOT-COLOR-INVALID", "warning", "Wheel Slot ColorCIE is malformed; using diagnostic white fallback.", wheel.name + ":" + slot.name});
                    }
                } else {
                    slot.provenance = "default_white";
                }
                wheel.slots.push_back(slot);
            }
            if (wheel.slots.empty()) fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-EMPTY", "warning", "Wheel has no ordered Slot children.", wheel.name});
            fixture.wheels.push_back(wheel);
        }
    }
}

// Resolves an exact ChannelFunction.Wheel link to a parser-owned wheel ID.
int32_t resolve_wheel_link(const CompiledGdtfFixtureType &fixture, const std::string &wheel_name) {
    if (wheel_name.empty()) return 0;
    for (const ParsedWheel &wheel : fixture.wheels) {
        if (wheel.name == wheel_name) return wheel.id;
    }
    return -1;
}

// Reads ordered ChannelSet rows with exact one-based WheelSlotIndex metadata.
std::vector<ParsedWheelChannelSet> parse_wheel_channel_sets(tinyxml2::XMLElement *fn, size_t source_count, CompiledGdtfFixtureType &fixture, const ParsedWheel *wheel) {
    std::vector<ParsedWheelChannelSet> sets;
    uint32_t previous_from = 0;
    bool has_previous = false;
    for (tinyxml2::XMLElement *set_node : dmx::collect_direct_children_by_name(fn, "channelset")) {
        ParsedWheelChannelSet set;
        set.name = dmx::trim_ascii(read_attr(set_node, "Name", "name"));
        if (!parse_dmx_value(read_attr(set_node, "DMXFrom", "dmxfrom"), source_count, set.dmx_from)) set.dmx_from = has_previous ? previous_from : 0;
        if (!parse_dmx_value(read_attr(set_node, "DMXTo", "dmxto"), source_count, set.dmx_to)) set.dmx_to = max_for_source_count(source_count);
        int parsed_slot = 0;
        const std::string slot_raw = read_attr(set_node, "WheelSlotIndex", "wheelslotindex");
        if (!slot_raw.empty()) parsed_slot = std::atoi(slot_raw.c_str());
        set.wheel_slot_index = parsed_slot;
        if (!wheel || parsed_slot < 1 || parsed_slot > static_cast<int32_t>(wheel->slots.size())) {
            fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-SLOT-INVALID", "warning", "ChannelSet WheelSlotIndex is outside the linked wheel slot range.", set.name});
            continue;
        }
        sets.push_back(set);
        previous_from = set.dmx_to + 1U;
        has_previous = true;
    }
    std::stable_sort(sets.begin(), sets.end(), [](const ParsedWheelChannelSet &a, const ParsedWheelChannelSet &b) { return a.dmx_from < b.dmx_from; });
    return sets;
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
    fixture.gdtf_files_opened = 1;
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
    fixture.selected_modes_found = 1;
    parse_physical_color_resources(doc.RootElement(), fixture);
    parse_wheels(doc.RootElement(), fixture);
    fixture.dmxchannels_containers_found = count_mode_dmxchannels_containers(selected_mode);
    const std::unordered_map<std::string, std::string> geometry_paths =
        build_geometry_paths(doc.RootElement(), dmx::trim_ascii(read_attr(selected_mode, "Geometry", "geometry")));
    std::unordered_map<std::string, int32_t> attribute_ids;
    std::unordered_map<std::string, int32_t> geometry_ids;
    int32_t next_component_id = 1;
    int32_t next_program_id = 1;
    std::unordered_map<std::string, int32_t> component_by_key;
    const std::vector<tinyxml2::XMLElement *> dmx_channels = collect_mode_dmx_channels(selected_mode);
    fixture.dmxchannel_records_found = static_cast<int32_t>(dmx_channels.size());
    for (tinyxml2::XMLElement *channel : dmx_channels) {
        const std::vector<int> offsets = dmx::parse_offsets(read_attr(channel, "Offset", "offset").c_str());
        if (offsets.empty()) continue;
        const std::string geometry_name = dmx::trim_ascii(read_attr(channel, "Geometry", "geometry"));
        const auto geometry_path_it = geometry_paths.find(geometry_name);
        const std::string geometry_path = geometry_path_it == geometry_paths.end() ? geometry_name : geometry_path_it->second;
        const int32_t geometry_id = geometry_id_for(fixture, geometry_ids, geometry_name, geometry_path);
        for (tinyxml2::XMLElement *logical : dmx::collect_direct_children_by_name(channel, "logicalchannel")) {
            ++fixture.logical_channels_found;
            const std::string logical_attribute = dmx::trim_ascii(read_attr(logical, "Attribute", "attribute"));
            std::vector<tinyxml2::XMLElement *> functions = collect_logical_channel_functions(logical);
            std::sort(functions.begin(), functions.end(), [&](tinyxml2::XMLElement *lhs, tinyxml2::XMLElement *rhs) {
                uint32_t lhs_from = 0;
                uint32_t rhs_from = 0;
                parse_dmx_value(read_attr(lhs, "DMXFrom", "dmxfrom"), offsets.size(), lhs_from);
                parse_dmx_value(read_attr(rhs, "DMXFrom", "dmxfrom"), offsets.size(), rhs_from);
                return lhs_from < rhs_from;
            });
            uint32_t previous_to = 0;
            bool has_previous = false;
            for (size_t function_index = 0; function_index < functions.size(); ++function_index) {
                tinyxml2::XMLElement *fn = functions[function_index];
                ++fixture.channel_functions_found;
                std::string attribute_name = dmx::trim_ascii(read_attr(fn, "Attribute", "attribute"));
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
                if (!parse_dmx_value(read_attr(fn, "DMXFrom", "dmxfrom"), offsets.size(), dmx_from)) dmx_from = 0;
                uint32_t dmx_to = max_for_source_count(offsets.size());
                if (!parse_dmx_value(read_attr(fn, "DMXTo", "dmxto"), offsets.size(), dmx_to)) {
                    if (function_index + 1 < functions.size()) {
                        uint32_t next_from = 0;
                        if (parse_dmx_value(read_attr(functions[function_index + 1], "DMXFrom", "dmxfrom"), offsets.size(), next_from) && next_from > 0) {
                            dmx_to = next_from - 1U;
                        }
                    }
                }
                if (dmx_to < dmx_from) {
                    fixture.diagnostics.push_back({"PVZ-GDTF-DMX-RANGE-INVALID", "warning", "ChannelFunction DMXTo is smaller than DMXFrom.", attribute_name});
                    continue;
                }
                if (has_previous && dmx_from <= previous_to) {
                    fixture.diagnostics.push_back({"PVZ-GDTF-DMX-RANGE-OVERLAP", "warning", "Overlapping ChannelFunction ranges are not compiled for the verified DPT runtime slice.", attribute_name});
                    continue;
                }
                previous_to = dmx_to;
                has_previous = true;
                double physical_from = 0.0;
                double physical_to = 1.0;
                const bool has_physical = read_float_attr(fn, "PhysicalFrom", "physicalfrom", physical_from) && read_float_attr(fn, "PhysicalTo", "physicalto", physical_to);
                if (!has_physical) fixture.diagnostics.push_back({"PVZ-GDTF-PHYSICAL-MISSING", "warning", "ChannelFunction is missing PhysicalFrom/PhysicalTo.", attribute_name});
                const std::string read_function_name = dmx::trim_ascii(read_attr(fn, "Name", "name"));
                const std::string function_name = read_function_name.empty() ? attribute_name : read_function_name;
                const std::string wheel_link = dmx::trim_ascii(read_attr(fn, "Wheel", "wheel"));
                const int32_t resolved_wheel_id = resolve_wheel_link(fixture, wheel_link);
                const ParsedWheel *resolved_wheel = nullptr;
                for (const ParsedWheel &wheel : fixture.wheels) if (wheel.id == resolved_wheel_id) resolved_wheel = &wheel;
                if (!wheel_link.empty() && resolved_wheel_id < 0) fixture.diagnostics.push_back({"PVZ-GDTF-WHEEL-LINK-MISSING", "warning", "ChannelFunction references an unknown Wheel.", attribute_name + " wheel=" + wheel_link});
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
                program.emitter_resource_id = resolve_physical_resource_link(fixture.emitters, dmx::trim_ascii(read_attr(fn, "Emitter", "emitter")));
                program.filter_resource_id = resolve_physical_resource_link(fixture.filters, dmx::trim_ascii(read_attr(fn, "Filter", "filter")));
                program.color_space_name = dmx::trim_ascii(read_attr(fn, "ColorSpace", "colorspace"));
                program.wheel_id = resolved_wheel_id > 0 ? resolved_wheel_id : 0;
                program.wheel_family_number = normalize_attribute_identity(0, attribute_name).primary_index;
                program.snap = dmx::lower_ascii(dmx::trim_ascii(read_attr(logical, "Snap", "snap"))) == "yes" || dmx::lower_ascii(dmx::trim_ascii(read_attr(logical, "Snap", "snap"))) == "true" || dmx::trim_ascii(read_attr(logical, "Snap", "snap")) == "1";
                if (program.wheel_id > 0) program.wheel_channel_sets = parse_wheel_channel_sets(fn, offsets.size(), fixture, resolved_wheel);
                if (program.emitter_resource_id < 0) fixture.diagnostics.push_back({"PVZ-GDTF-EMITTER-LINK-MISSING", "warning", "ChannelFunction references an unknown Emitter.", attribute_name});
                if (program.filter_resource_id < 0) fixture.diagnostics.push_back({"PVZ-GDTF-FILTER-LINK-MISSING", "warning", "ChannelFunction references an unknown Filter.", attribute_name});
                fixture.channel_programs.push_back(program);
                if (dmx::lower_ascii(attribute_name) == "dimmer") ++fixture.dimmer_program_count;
                if (dmx::lower_ascii(attribute_name) == "pan") ++fixture.pan_program_count;
                if (dmx::lower_ascii(attribute_name) == "tilt") ++fixture.tilt_program_count;
                if (dmx::lower_ascii(attribute_name) == "zoom") ++fixture.zoom_program_count;
                {
                    const std::string lower_attribute = dmx::lower_ascii(attribute_name);
                    if (lower_attribute == "coloradd_r" || lower_attribute == "coloradd_g" || lower_attribute == "coloradd_b" || lower_attribute == "coloradd_w" || lower_attribute == "coloradd_ry" || lower_attribute == "coloradd_gy" || lower_attribute == "colorsub_c" || lower_attribute == "colorsub_m" || lower_attribute == "colorsub_y" || lower_attribute == "cyan" || lower_attribute == "magenta" || lower_attribute == "yellow") ++fixture.color_program_count;
                }
            }
        }
    }
    if (fixture.dmxchannel_records_found == 0) {
        fixture.diagnostics.push_back({"PVZ-GDTF-DMXCHANNELS-MISSING", "error", "Selected DMX mode contains no DMXChannel records after scoped parser traversal.", dmx_mode_name});
    }
    if (!dmx_channels.empty() && fixture.channel_programs.empty()) {
        fixture.diagnostics.push_back({"PVZ-GDTF-DPT-PROGRAMS-MISSING", "error", "Selected DMX mode produced no compiled Dimmer/Pan/Tilt/Zoom ChannelFunction programs.", dmx_mode_name});
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
