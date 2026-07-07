#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include <cctype>

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

// Builds a small fixture model that proves repeated GDTF wheel families remain independent.
CompiledGdtfFixtureType make_two_gobo_wheel_regression_fixture() {
    CompiledGdtfFixtureType fixture;
    fixture.fixture_type_name = "Peraviz Two Gobo Wheel Regression";
    fixture.dmx_mode_name = "Mode 1";
    fixture.attributes.push_back(normalize_attribute_identity(1, "Dimmer"));
    fixture.attributes.push_back(normalize_attribute_identity(2, "Gobo1"));
    fixture.attributes.push_back(normalize_attribute_identity(3, "Gobo2"));
    fixture.geometries.push_back({1, 0, "Base", "Geometry"});
    fixture.geometries.push_back({2, 1, "Head", "Beam"});
    fixture.components.push_back({1, 2, 1, 0, 1});
    fixture.components.push_back({2, 2, 2, 1, 2});
    fixture.components.push_back({3, 2, 3, 2, 3});
    fixture.channel_programs.push_back({1, 0, 8, 1, 2, 1, 0, 255, 0.0, 1.0});
    fixture.channel_programs.push_back({2, 1, 8, 2, 2, 2, 0, 127, 0.0, 6.0});
    fixture.channel_programs.push_back({3, 2, 8, 3, 2, 3, 128, 255, 0.0, 6.0});
    fixture.diagnostics.push_back({"PVZ-GDTF-UNKNOWN-PRESERVED", "info", "Unknown and custom attributes are retained in the semantic model before runtime compilation.", "AttributeDefinitions"});
    return fixture;
}

} // namespace peraviz::gdtf_runtime
